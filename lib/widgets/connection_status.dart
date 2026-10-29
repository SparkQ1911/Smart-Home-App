import 'package:flutter/material.dart';

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({
    required this.isConnected,
    required this.isDemo,
    this.error,
    super.key,
  });

  final bool isConnected;
  final bool isDemo;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final color = isDemo
        ? const Color(0xFFB26A00)
        : isConnected
            ? const Color(0xFF18864B)
            : const Color(0xFFB42318);
    final label = isDemo
        ? 'Chế độ demo'
        : isConnected
            ? 'Đã kết nối Server'
            : 'Chưa kết nối Server';
    final icon = isDemo
        ? Icons.science_outlined
        : isConnected
            ? Icons.cloud_done_rounded
            : Icons.cloud_off_rounded;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w700)),
                if (error != null && error!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(error!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
