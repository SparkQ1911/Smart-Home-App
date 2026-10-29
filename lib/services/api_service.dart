import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/device.dart';
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

class ApiEndpoints {
  const ApiEndpoints({
    this.devices = '/api/devices',
    this.latestSensors = '/api/sensors/latest',
    this.deviceStatus = '/api/devices/{id}/status',
    this.deviceControl = '/api/devices/{id}/control',
    this.history = '/api/history',
  });

  final String devices;
  final String latestSensors;
  final String deviceStatus;
  final String deviceControl;
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

  String? get baseUrl => _baseUri?.toString().replaceFirst(RegExp(r'/$'), '');

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
    if (payload is Map<String, dynamic> &&
        (payload.containsKey('status') || payload.containsKey('state'))) {
      return _parseState(payload['status'] ?? payload['state']);
    }
    return getDeviceStatus(id);
  }

  Future<List<HistoryEntry>> getHistory() async {
    final uri = _uri(endpoints.history);
    late http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
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
      response = await _client.get(uri).timeout(timeout);
    } on Exception catch (error) {
      throw ApiException(_networkMessage(error));
    }
    return _decodeResponse(response);
  }

  Future<Object?> _request(
    String method,
    String path, {
    String? body,
  }) async {
    final uri = _uri(path);
    late http.Response response;
    try {
      response = switch (method) {
        'POST' => await _client
            .post(
              uri,
              headers: const {'Content-Type': 'application/json'},
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
      throw ApiException(
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
