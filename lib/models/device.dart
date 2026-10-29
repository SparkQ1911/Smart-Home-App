import 'package:flutter/material.dart';

class Device {
  const Device({
    required this.id,
    required this.name,
    required this.type,
    required this.isOn,
    this.room = 'Chưa phân loại',
  });

  final String id;
  final String name;
  final String type;
  final bool isOn;
  final String room;

  IconData get icon {
    switch (type.toLowerCase()) {
      case 'light':
      case 'lamp':
      case 'den':
        return Icons.lightbulb_outline_rounded;
      case 'fan':
      case 'quat':
        return Icons.toys_rounded;
      case 'air_conditioner':
      case 'ac':
        return Icons.ac_unit_rounded;
      case 'door':
        return Icons.door_front_door_outlined;
      default:
        return Icons.power_rounded;
    }
  }

  factory Device.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final name = json['name']?.toString();
    final type = json['type']?.toString();
    final room = (json['room'] ?? json['area'])?.toString();
    final status = json['status'] ?? json['state'];
    if (id == null || id.isEmpty || name == null || type == null) {
      throw const FormatException('Thiết bị thiếu id, name hoặc type.');
    }
    return Device(
      id: id,
      name: name,
      type: type,
      isOn: _parseState(status),
      room: room == null || room.trim().isEmpty ? 'Chưa phân loại' : room,
    );
  }

  Device copyWith({String? name, String? type, bool? isOn, String? room}) =>
      Device(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        isOn: isOn ?? this.isOn,
        room: room ?? this.room,
      );

  static bool parseState(Object? value) => _parseState(value);

  static bool _parseState(Object? value) {
    if (value is bool) return value;
    switch (value?.toString().toUpperCase()) {
      case 'ON':
      case 'TRUE':
      case '1':
        return true;
      case 'OFF':
      case 'FALSE':
      case '0':
        return false;
      default:
        throw const FormatException('Trạng thái thiết bị không hợp lệ.');
    }
  }
}
