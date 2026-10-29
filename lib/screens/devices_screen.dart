import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../providers/smart_home_provider.dart';
import '../widgets/device_card.dart';
import '../widgets/device_control_feedback.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SmartHomeProvider>();
    return RefreshIndicator(
      onRefresh: provider.loadDevices,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            provider.mode == DataMode.demo
                ? 'Thiết bị mẫu · thao tác chỉ mô phỏng trên ứng dụng.'
                : 'Trạng thái hiển thị là trạng thái Server xác nhận.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (provider.isLoadingDevices)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (provider.devicesError != null)
            _Message(text: provider.devicesError!, isError: true)
          else if (provider.devices.isEmpty)
            const _Message(text: 'Chưa có thiết bị nào được cung cấp.')
          else
            for (final room in _groupByRoom(provider.devices).entries) ...[
              _RoomHeading(name: room.key, count: room.value.length),
              for (final device in room.value)
                DeviceCard(
                  device: device,
                  isBusy: provider.isDeviceBusy(device.id),
                  isDemo: provider.mode == DataMode.demo,
                  onChanged: (value) => controlDeviceWithFeedback(
                    context,
                    provider,
                    device.name,
                    device.id,
                    value,
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

Map<String, List<Device>> _groupByRoom(List<Device> devices) {
  final groups = <String, List<Device>>{};
  for (final device in devices) {
    groups.putIfAbsent(device.room, () => []).add(device);
  }
  return groups;
}

class _RoomHeading extends StatelessWidget {
  const _RoomHeading({required this.name, required this.count});

  final String name;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
        child: Row(
          children: [
            const Icon(Icons.meeting_room_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Text('$count thiết bị',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: isError ? Colors.red.shade700 : null),
        ),
      );
}
