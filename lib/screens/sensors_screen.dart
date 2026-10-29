import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sensor_data.dart';
import '../providers/smart_home_provider.dart';
import '../widgets/sensor_card.dart';

class SensorsScreen extends StatelessWidget {
  const SensorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SmartHomeProvider>();
    final data = provider.sensors;
    return RefreshIndicator(
      onRefresh: provider.loadSensors,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            provider.mode == DataMode.demo
                ? 'Dữ liệu minh họa (demo), không phải số đo thiết bị thật.'
                : 'Dữ liệu cảm biến được lấy trực tiếp từ Server.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (provider.isLoadingSensors)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              ),
            )
          else if (provider.sensorsError != null)
            _SensorMessage(
              icon: Icons.cloud_off_rounded,
              message: provider.sensorsError!,
            )
          else if (data == null ||
              (data.temperature == null &&
                  data.humidity == null &&
                  data.extra.isEmpty &&
                  data.rooms.isEmpty))
            const _SensorMessage(
              icon: Icons.sensors_off_rounded,
              message: 'Server chưa có dữ liệu cảm biến.',
            )
          else ...[
            if (data.rooms.isNotEmpty)
              for (final room in data.rooms) ...[
                _RoomSensorSection(room: room),
                const SizedBox(height: 8),
              ]
            else ...[
              if (data.temperature != null)
                SensorCard(
                  title: 'Nhiệt độ',
                  value: data.temperature!.toStringAsFixed(1),
                  unit: '°C',
                  icon: Icons.thermostat_rounded,
                ),
              if (data.humidity != null)
                SensorCard(
                  title: 'Độ ẩm',
                  value: data.humidity!.toStringAsFixed(0),
                  unit: '%',
                  icon: Icons.water_drop_outlined,
                ),
              ...data.extra.entries.map(
                (entry) => SensorCard(
                  title: entry.key,
                  value: entry.value?.toString() ?? '--',
                  unit: '',
                  icon: Icons.sensors_rounded,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('Cập nhật gần nhất'),
                subtitle: Text(_formatDate(data.updatedAt)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Server chưa cung cấp thời gian cập nhật.';
    final date = value.toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} lúc $hour:$minute';
  }
}

class _RoomSensorSection extends StatelessWidget {
  const _RoomSensorSection({required this.room});

  final RoomSensorData room;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
            child: Text(
              room.room,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (room.temperature != null)
            SensorCard(
              title: 'Nhiệt độ',
              value: room.temperature!.toStringAsFixed(1),
              unit: '°C',
              icon: Icons.thermostat_rounded,
            ),
          if (room.humidity != null)
            SensorCard(
              title: 'Độ ẩm',
              value: room.humidity!.toStringAsFixed(0),
              unit: '%',
              icon: Icons.water_drop_outlined,
            ),
          ...room.extra.entries.map(
            (entry) => SensorCard(
              title: entry.key,
              value: entry.value?.toString() ?? '--',
              unit: '',
              icon: Icons.sensors_rounded,
            ),
          ),
        ],
      );
}

class _SensorMessage extends StatelessWidget {
  const _SensorMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Column(
          children: [
            Icon(icon, size: 36, color: Colors.blueGrey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      );
}
