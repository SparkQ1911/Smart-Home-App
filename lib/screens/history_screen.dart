import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/smart_home_provider.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SmartHomeProvider>();
    return RefreshIndicator(
      onRefresh: provider.loadHistory,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (provider.mode == DataMode.demo)
            const _HistoryMessage(
              icon: Icons.science_outlined,
              message: 'Chế độ demo không lưu lịch sử trên Server.',
            )
          else if (provider.isLoadingHistory)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              ),
            )
          else if (provider.historyError != null)
            _HistoryMessage(
              icon: Icons.error_outline_rounded,
              message: provider.historyError!,
            )
          else if (!provider.historySupported)
            const _HistoryMessage(
              icon: Icons.history_toggle_off_rounded,
              message: 'Server chưa hỗ trợ API lịch sử.',
            )
          else if (provider.history.isEmpty)
            const _HistoryMessage(
              icon: Icons.history_rounded,
              message: 'Server chưa có dữ liệu lịch sử.',
            )
          else
            ...provider.history.map(
              (entry) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.event_note_rounded),
                  ),
                  title: Text(entry.title),
                  subtitle: Text(entry.detail),
                  trailing: Text(
                    _formatDate(entry.timestamp),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '--';
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            Icon(icon, size: 38, color: Colors.blueGrey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      );
}
