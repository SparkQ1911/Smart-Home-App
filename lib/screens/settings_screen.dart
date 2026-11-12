import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/smart_home_provider.dart';
import '../widgets/connection_status.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SmartHomeProvider>();
    final user = provider.currentUser;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ConnectionStatus(
          isConnected: provider.isConnected,
          isDemo: provider.mode == DataMode.demo,
          error: provider.connectionError,
        ),
        const SizedBox(height: 20),
        Text(
          'Tài khoản',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 34,
                  child: Text(
                    user?.name.isNotEmpty == true
                        ? user!.name.substring(0, 1).toUpperCase()
                        : '?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user?.name ?? 'Chưa đăng nhập',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (user != null) ...[
                  const SizedBox(height: 4),
                  Text(user.email),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: user == null ? null : () => _logout(context),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Đăng xuất'),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: user == null ? null : () => _deleteAccount(context),
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Xóa tài khoản'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Xóa tài khoản sẽ gỡ thông tin đăng nhập của bạn. Dữ liệu cảm biến '
          'và thiết bị dùng chung không bị xóa.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await context.read<SmartHomeProvider>().logout();
    } on Exception catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Không thể đăng xuất: $error');
      }
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa tài khoản?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thao tác này không thể hoàn tác. Nhập mật khẩu để xác nhận.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passwordController,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mật khẩu'),
              onSubmitted: (_) =>
                  Navigator.of(dialogContext).pop(passwordController.text),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(passwordController.text),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Xóa tài khoản'),
          ),
        ],
      ),
    );
    passwordController.dispose();
    if (password == null || password.isEmpty || !context.mounted) return;

    try {
      await context.read<SmartHomeProvider>().deleteAccount(password: password);
    } on Exception catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Không thể xóa tài khoản: $error');
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
