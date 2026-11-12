import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_home_app/models/device.dart';
import 'package:smart_home_app/services/api_service.dart';

void main() {
  group('ApiService', () {
    test('resolves endpoint paths under the configured base path', () async {
      final client = _FakeClient((request) async {
        expect(
            request.url.toString(), 'http://192.0.2.1:8080/home/api/devices');
        return http.Response.bytes(
          utf8.encode(jsonEncode([
            {
              'id': 'lamp-1',
              'name': 'Đèn phòng khách',
              'type': 'light',
              'status': 'OFF',
            }
          ])),
          200,
        );
      });
      final service = ApiService(client: client);
      service.configure('http://192.0.2.1:8080/home');

      final devices = await service.getDevices();

      expect(devices, hasLength(1));
      expect(devices.single.isOn, isFalse);
      service.dispose();
    });

    test('sends a control command and returns only the server-confirmed state',
        () async {
      final client = _FakeClient((request) async {
        if (request.method == 'POST') {
          expect(request.url.path, '/api/devices/lamp-1/control');
          if (request is! http.Request) {
            fail('Control request must contain a JSON body.');
          }
          expect(jsonDecode(request.body), {'state': 'ON'});
          return http.Response(
            jsonEncode({'commandId': 'command-1', 'status': 'pending'}),
            202,
          );
        }
        expect(request.url.path, '/api/devices/lamp-1/commands/command-1');
        return http.Response(
          jsonEncode({'status': 'completed', 'reportedState': 'ON'}),
          200,
        );
      });
      final service = ApiService(client: client);
      service.configure('http://192.0.2.1:8080');

      expect(await service.controlDevice('lamp-1', true), isTrue);
      service.dispose();
    });

    test('registers, authenticates protected requests, and deletes account',
        () async {
      String? token;
      final client = _FakeClient((request) async {
        if (request.url.path == '/api/auth/register') {
          expect(request.method, 'POST');
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(jsonDecode((request as http.Request).body), {
            'name': 'Linh',
            'email': 'linh@example.com',
            'password': 'safe-password',
          });
          return http.Response(
            jsonEncode({
              'token': 'signed-session',
              'user': {
                'id': 'user-1',
                'name': 'Linh',
                'email': 'linh@example.com',
              },
            }),
            200,
          );
        }
        expect(request.headers['Authorization'], 'Bearer signed-session');
        if (request.method == 'GET') {
          expect(request.url.path, '/api/auth/me');
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'user-1',
                'name': 'Linh',
                'email': 'linh@example.com',
              },
            }),
            200,
          );
        }
        expect(request.method, 'DELETE');
        expect(jsonDecode((request as http.Request).body),
            {'password': 'safe-password'});
        return http.Response(jsonEncode({'deleted': true}), 200);
      });
      final service = ApiService(client: client)
        ..configure('https://api.example.com');

      final session = await service.register(
        name: 'Linh',
        email: 'linh@example.com',
        password: 'safe-password',
      );
      token = session.token;
      service.setAccessToken(token);
      expect((await service.getCurrentUser()).email, 'linh@example.com');
      await service.deleteAccount(password: 'safe-password');
      service.dispose();
    });

    test('returns only state confirmed by the device command response',
        () async {
      final client = _FakeClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'commandId': 'command-2', 'status': 'pending'}),
            202,
          );
        }
        expect(request.url.path, '/api/devices/lamp-1/commands/command-2');
        return http.Response(
          jsonEncode({'status': 'completed', 'reportedState': 'OFF'}),
          200,
        );
      });
      final service = ApiService(client: client);
      service.configure('http://192.0.2.1:8080');

      expect(await service.controlDevice('lamp-1', true), isFalse);
      service.dispose();
    });

    test('rejects a non-HTTP URL and invalid device status', () async {
      final service = ApiService(client: _FakeClient((_) async {
        return http.Response(jsonEncode({'status': 'UNKNOWN'}), 200);
      }));

      expect(
        () => service.configure('ftp://192.0.2.1'),
        throwsA(isA<ApiException>()),
      );
      service.configure('http://192.0.2.1');
      await expectLater(
        service.getDeviceStatus('lamp-1'),
        throwsA(isA<ApiException>()),
      );
      service.dispose();
    });

    test('parses confirmed device states strictly', () {
      expect(Device.parseState('ON'), isTrue);
      expect(Device.parseState('OFF'), isFalse);
    });

    test('parses devices and sensor readings grouped by room', () async {
      final client = _FakeClient((request) async {
        if (request.url.path == '/api/devices') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'devices': [
                {
                  'id': 'kitchen-light',
                  'name': 'Đèn bếp',
                  'type': 'light',
                  'status': 'ON',
                  'room': 'Nhà bếp',
                }
              ],
            })),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'rooms': [
              {
                'room': 'Nhà bếp',
                'temperature': 29.5,
                'humidity': 60,
                'updatedAt': '2026-10-28T10:00:00Z',
              }
            ],
          })),
          200,
        );
      });
      final service = ApiService(client: client);
      service.configure('http://192.0.2.1:8080');

      final devices = await service.getDevices();
      final sensors = await service.getLatestSensors();

      expect(devices.single.room, 'Nhà bếp');
      expect(sensors.rooms.single.room, 'Nhà bếp');
      expect(sensors.temperature, 29.5);
      service.dispose();
    });
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this._respond);

  final Future<http.Response> Function(http.BaseRequest request) _respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _respond(request);
    final bytes = response.bodyBytes;
    return http.StreamedResponse(
      Stream<Uint8List>.value(bytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
