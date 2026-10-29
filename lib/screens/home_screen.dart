import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../providers/smart_home_provider.dart';
import '../widgets/connection_status.dart';
import '../widgets/device_card.dart';
import '../widgets/device_control_feedback.dart';
import '../widgets/sensor_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SmartHomeProvider>();
    final sensors = provider.sensors;
    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ConnectionStatus(
            isConnected: provider.isConnected,
            isDemo: provider.mode == DataMode.demo,
            error: provider.connectionError,
          ),
          const SizedBox(height: 16),
          _WelcomeCard(
            temperature: sensors?.temperature,
            activeDevices: provider.activeDeviceCount,
          ),
          const SizedBox(height: 22),
          Text('Trong nhà hôm nay',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  )),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SensorCard(
                  title: 'Nhiệt độ',
                  value: sensors?.temperature?.toStringAsFixed(1) ?? '--',
                  unit: '°C',
                  icon: Icons.thermostat_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SensorCard(
                  title: 'Độ ẩm',
                  value: sensors?.humidity?.toStringAsFixed(0) ?? '--',
                  unit: '%',
                  icon: Icons.water_drop_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Tổng thiết bị',
                  value: '${provider.devices.length}',
                  icon: Icons.devices_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryCard(
                  label: 'Đang bật',
                  value: '${provider.activeDeviceCount}',
                  icon: Icons.power_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text('Thiết bị trong nhà',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
              ),
              Text('${provider.devices.length} thiết bị',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          if (provider.isLoadingDevices)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (provider.devicesError != null)
            _InfoMessage(
              icon: Icons.error_outline_rounded,
              text: provider.devicesError!,
            )
          else if (provider.devices.isEmpty)
            const _InfoMessage(
              icon: Icons.devices_other_rounded,
              text: 'Chưa có thiết bị nào từ Server.',
            )
          else
            for (final room in _groupByRoom(provider.devices).entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
                child: Text(
                  room.key,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              for (final device in room.value)
                DeviceCard(
                  device: device,
                  isDemo: provider.mode == DataMode.demo,
                  isBusy: provider.isDeviceBusy(device.id),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.temperature,
    required this.activeDevices,
  });

  final double? temperature;
  final int activeDevices;

  @override
  Widget build(BuildContext context) {
    final temperatureLabel =
        temperature == null ? '--°' : '${temperature!.toStringAsFixed(0)}°';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF315BC5), Color(0xFF547DE5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF315BC5).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Không gian sống',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$activeDevices thiết bị đang hoạt động',
                  style: const TextStyle(
                    color: Color(0xFFDCE6FF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.thermostat_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      temperature == null
                          ? 'Chưa có dữ liệu nhiệt độ'
                          : 'Nhiệt độ trong nhà',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              const Icon(
                Icons.wb_sunny_rounded,
                size: 32,
                color: Color(0xFFFFD979),
              ),
              const SizedBox(height: 4),
              Text(
                temperatureLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'trong nhà',
                style: TextStyle(color: Color(0xFFDCE6FF), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoMessage extends StatelessWidget {
  const _InfoMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: Column(
            children: [
              Icon(icon, size: 30, color: Colors.blueGrey),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
