import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/device.dart';
import '../models/auth_user.dart';
import '../models/history_entry.dart';
import '../models/sensor_data.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class HistoryNotSupportedException extends ApiException {
  const HistoryNotSupportedException()
      : super('Server chưa hỗ trợ API lịch sử.');
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AuthUser user;
}

class ApiEndpoints {
  const ApiEndpoints({
    this.devices = '/api/devices',
    this.latestSensors = '/api/sensors/latest',
    this.deviceStatus = '/api/devices/{id}/status',
    this.deviceControl = '/api/devices/{id}/control',
    this.deviceCommand = '/api/devices/{id}/commands/{commandId}',
    this.history = '/api/history',
  });

  final String devices;
  final String latestSensors;
  final String deviceStatus;
  final String deviceControl;
  final String deviceCommand;
  final String history;
}

class ApiService {
  ApiService({
    http.Client? client,
    this.endpoints = const ApiEndpoints(),
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final ApiEndpoints endpoints;
  final Duration timeout;
  Uri? _baseUri;
  String? _accessToken;

  String? get baseUrl => _baseUri?.toString().replaceFirst(RegExp(r'/$'), '');

  void setAccessToken(String? token) => _accessToken = token;

  void configure(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null ||
        !parsed.hasScheme ||
        !const ['http', 'https'].contains(parsed.scheme.toLowerCase()) ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const ApiException(
        'Địa chỉ phải là URL http/https hợp lệ, không chứa thông tin đăng nhập.',
      );
    }
    _baseUri = parsed.replace(
      path: parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/',
    );
  }

  Future<List<Device>> getDevices() async {
    final payload = await _get(endpoints.devices);
    final raw = payload is List
        ? payload
        : payload is Map<String, dynamic>
            ? payload['devices']
            : null;
    if (raw is! List) {
      throw const ApiException('API thiết bị phải trả về một danh sách JSON.');
    }
    try {
      return raw
          .map((item) => Device.fromJson(_asMap(item, 'thiết bị')))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw ApiException('Dữ liệu thiết bị không hợp lệ: ${error.message}');
    }
  }

  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final payload = await _request(
      'POST',
      '/api/auth/register',
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
      authenticated: false,
    );
    return _parseAuthSession(payload);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final payload = await _request(
      'POST',
      '/api/auth/login',
      body: jsonEncode({'email': email, 'password': password}),
      authenticated: false,
    );
    return _parseAuthSession(payload);
  }

  Future<AuthUser> getCurrentUser() async {
    final payload = await _get('/api/auth/me');
    final map = _asMap(payload, 'tài khoản');
    return _parseUser(map['user']);
  }

  Future<void> deleteAccount({required String password}) async {
    final uri = _uri('/api/auth/me');
    late http.Response response;
    try {
      response = await _client
          .delete(
            uri,
            headers: _headers()..['Content-Type'] = 'application/json',
            body: jsonEncode({'password': password}),
          )
          .timeout(timeout);
    } on Exception catch (error) {
      throw ApiException(_networkMessage(error));
    }
    _decodeResponse(response);
  }

  Future<SensorData> getLatestSensors() async {
    final payload = await _get(endpoints.latestSensors);
    try {
      return SensorData.fromJson(_asMap(payload, 'cảm biến'));
    } on FormatException catch (error) {
      throw ApiException('Dữ liệu cảm biến không hợp lệ: ${error.message}');
    }
  }

  Future<bool> getDeviceStatus(String id) async {
    final path = _devicePath(endpoints.deviceStatus, id);
    final payload = await _get(path);
    if (payload is String || payload is bool) {
      return _parseState(payload);
    }
    final map = _asMap(payload, 'trạng thái thiết bị');
    return _parseState(map['status'] ?? map['state']);
  }

  Future<bool> controlDevice(String id, bool turnOn) async {
    final path = _devicePath(endpoints.deviceControl, id);
    final payload = await _request(
      'POST',
      path,
      body: jsonEncode({'state': turnOn ? 'ON' : 'OFF'}),
    );
    final response = _asMap(payload, 'lệnh điều khiển');
    final commandId = response['commandId'];
    if (commandId is! String || commandId.isEmpty) {
      if (response.containsKey('status') || response.containsKey('state')) {
        return _parseState(response['status'] ?? response['state']);
      }
      throw const ApiException('Server không trả về mã lệnh điều khiển.');
    }
    final commandPath = endpoints.deviceCommand
        .replaceAll('{id}', Uri.encodeComponent(id))
        .replaceAll('{commandId}', Uri.encodeComponent(commandId));
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final command = _asMap(await _get(commandPath), 'trạng thái lệnh');
      switch (command['status']) {
        case 'completed':
          return _parseState(command['reportedState']);
        case 'failed':
          throw const ApiException(
            'Thiết bị phản hồi trạng thái khác với yêu cầu.',
          );
        case 'pending':
          break;
        default:
          throw const ApiException(
              'Server trả về trạng thái lệnh không hợp lệ.');
      }
    }
    throw const ApiException(
      'Thiết bị chưa phản hồi lệnh. Kiểm tra kết nối ESP32 rồi thử lại.',
    );
  }

  Future<List<HistoryEntry>> getHistory() async {
    final uri = _uri(endpoints.history);
    late http.Response response;
    try {
      response = await _client.get(uri, headers: _headers()).timeout(timeout);
    } on Exception catch (error) {
      throw ApiException(_networkMessage(error));
    }
    if (response.statusCode == 404 || response.statusCode == 501) {
      throw const HistoryNotSupportedException();
    }
    final payload = _decodeResponse(response);
    final raw = payload is List
        ? payload
        : payload is Map<String, dynamic>
            ? payload['history'] ?? payload['items']
            : null;
    if (raw is! List) {
      throw const ApiException('API lịch sử phải trả về một danh sách JSON.');
    }
    try {
      return raw
          .map((item) => HistoryEntry.fromJson(_asMap(item, 'mục lịch sử')))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw ApiException('Dữ liệu lịch sử không hợp lệ: ${error.message}');
    }
  }

  Future<Object?> _get(String path) async {
    final uri = _uri(path);
    late http.Response response;
    try {
      response = await _client.get(uri, headers: _headers()).timeout(timeout);
    } on Exception catch (error) {
      throw ApiException(_networkMessage(error));
    }
    return _decodeResponse(response);
  }

  Future<Object?> _request(
    String method,
    String path, {
    String? body,
    bool authenticated = true,
  }) async {
    final uri = _uri(path);
    final headers = _headers(authenticated: authenticated)
      ..putIfAbsent('Content-Type', () => 'application/json');
    late http.Response response;
    try {
      response = switch (method) {
        'POST' => await _client
            .post(
              uri,
              headers: headers,
              body: body,
            )
            .timeout(timeout),
        _ => throw ArgumentError.value(method, 'method', 'Không hỗ trợ'),
      };
    } on Exception catch (error) {
      throw ApiException(_networkMessage(error));
    }
    return _decodeResponse(response);
  }

  Object? _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? detail;
      try {
        final payload = jsonDecode(utf8.decode(response.bodyBytes));
        if (payload is Map<String, dynamic> && payload['error'] is String) {
          detail = payload['error'] as String;
        }
      } on FormatException {
        detail = null;
      }
      throw ApiException(
        detail ??
            'Server trả về HTTP ${response.statusCode}'
                '${response.reasonPhrase == null ? '' : ': ${response.reasonPhrase}'}.',
      );
    }
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ApiException('Server trả về JSON không hợp lệ.');
    }
  }

  Uri _uri(String path) {
    final base = _baseUri;
    if (base == null) {
      throw const ApiException('Chưa cấu hình địa chỉ Server.');
    }
    return base.resolve(path.replaceFirst(RegExp(r'^/+'), ''));
  }

  Map<String, String> _headers({bool authenticated = true}) {
    final token = authenticated ? _accessToken : null;
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  AuthSession _parseAuthSession(Object? payload) {
    final map = _asMap(payload, 'phiên đăng nhập');
    final token = map['token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException('Server không trả về mã phiên hợp lệ.');
    }
    return AuthSession(
      token: token,
      user: _parseUser(map['user']),
    );
  }

  AuthUser _parseUser(Object? value) {
    try {
      return AuthUser.fromJson(_asMap(value, 'tài khoản'));
    } on FormatException catch (error) {
      throw ApiException(error.message);
    }
  }

  String _devicePath(String template, String id) =>
      template.replaceAll('{id}', Uri.encodeComponent(id));

  Map<String, dynamic> _asMap(Object? value, String label) {
    if (value is Map<String, dynamic>) return value;
    throw ApiException('Dữ liệu $label phải là một JSON object.');
  }

  bool _parseState(Object? value) {
    try {
      return Device.parseState(value);
    } on FormatException catch (error) {
      throw ApiException(error.message);
    }
  }

  String _networkMessage(Exception error) {
    if (error is ApiException) return error.message;
    if (error is http.ClientException) {
      return 'Không thể kết nối Server. Hãy kiểm tra mạng và địa chỉ Server.';
    }
    if (error is FormatException) return 'Dữ liệu Server trả về không hợp lệ.';
    return 'Kết nối Server thất bại hoặc đã hết thời gian chờ.';
  }

  void dispose() => _client.close();
}
