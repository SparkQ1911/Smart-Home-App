class SensorData {
  const SensorData({
    required this.temperature,
    required this.humidity,
    required this.updatedAt,
    this.extra = const {},
    this.rooms = const [],
  });

  final double? temperature;
  final double? humidity;
  final DateTime? updatedAt;
  final Map<String, Object?> extra;
  final List<RoomSensorData> rooms;

  factory SensorData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final rawRooms = data['rooms'];
    if (rawRooms != null && rawRooms is! List) {
      throw const FormatException(
          'Danh sách cảm biến theo phòng không hợp lệ.');
    }
    final rooms = rawRooms == null
        ? const <RoomSensorData>[]
        : rawRooms
            .map<RoomSensorData>(
                (room) => RoomSensorData.fromJson(_asMap(room)))
            .toList(growable: false);
    final latestRoom = rooms.isEmpty ? null : rooms.first;
    final updatedAt = _parseDate(
      data['updatedAt'] ?? data['updated_at'] ?? latestRoom?.updatedAt,
    );
    return SensorData(
      temperature: _parseNumber(data['temperature']) ?? latestRoom?.temperature,
      humidity: _parseNumber(data['humidity']) ?? latestRoom?.humidity,
      updatedAt: updatedAt,
      extra: Map<String, Object?>.from(data)
        ..remove('temperature')
        ..remove('humidity')
        ..remove('updatedAt')
        ..remove('updated_at')
        ..remove('rooms'),
      rooms: rooms,
    );
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Dữ liệu cảm biến theo phòng không hợp lệ.');
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) {
      throw const FormatException('Thời gian cập nhật cảm biến không hợp lệ.');
    }
    return parsed;
  }

  static double? _parseNumber(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    if (parsed == null) {
      throw const FormatException('Giá trị cảm biến không hợp lệ.');
    }
    return parsed;
  }
}

class RoomSensorData {
  const RoomSensorData({
    required this.room,
    required this.temperature,
    required this.humidity,
    required this.updatedAt,
    this.extra = const {},
  });

  final String room;
  final double? temperature;
  final double? humidity;
  final DateTime? updatedAt;
  final Map<String, Object?> extra;

  factory RoomSensorData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final rawRoom = data['room'] ?? data['area'] ?? data['name'];
    final room = rawRoom?.toString().trim();
    return RoomSensorData(
      room: room == null || room.isEmpty ? 'Chưa phân loại' : room,
      temperature: SensorData._parseNumber(data['temperature']),
      humidity: SensorData._parseNumber(data['humidity']),
      updatedAt: SensorData._parseDate(
        data['updatedAt'] ?? data['updated_at'],
      ),
      extra: Map<String, Object?>.from(data)
        ..remove('room')
        ..remove('area')
        ..remove('name')
        ..remove('temperature')
        ..remove('humidity')
        ..remove('updatedAt')
        ..remove('updated_at'),
    );
  }
}
