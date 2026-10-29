import 'package:flutter/material.dart';

import '../models/device.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    required this.device,
    required this.onChanged,
    this.isBusy = false,
    this.isDemo = false,
    super.key,
  });

  final Device device;
  final ValueChanged<bool> onChanged;
  final bool isBusy;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final accent = device.isOn ? const Color(0xFF3867D6) : Colors.blueGrey;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(device.icon, color: accent, size: 25),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      )),
                  const SizedBox(height: 4),
                  Text(
                    isBusy
                        ? 'Đang chờ Server xác nhận...'
                        : isDemo
                            ? 'Demo · ${device.isOn ? 'Đang bật' : 'Đang tắt'}'
                            : 'Đã xác nhận · ${device.isOn ? 'Đang bật' : 'Đang tắt'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (isBusy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: device.isOn,
                onChanged: onChanged,
                activeThumbColor: accent,
              ),
          ],
        ),
      ),
    );
  }
}
