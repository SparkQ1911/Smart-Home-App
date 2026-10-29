import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/smart_home_provider.dart';
import '../widgets/connection_status.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(
      text: context.read<SmartHomeProvider>().serverAddress,
    );
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SmartHomeProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ConnectionStatus(
          isConnected: provider.isConnected,
          isDemo: provider.mode == DataMode.demo,
          error: provider.connectionError,
        ),
        const SizedBox(height: 20),
        Text('Cấu hình Server',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                )),
        const SizedBox(height: 8),
        const Text(
          'Nhập địa chỉ gốc của REST API, ví dụ http://192.168.1.10:8080. '
          'Không nhập mật khẩu hoặc thông tin đăng nhập vào địa chỉ này.',
        ),
        const SizedBox(height: 6),
        Text(
          'App tự đồng bộ dữ liệu Server mỗi 3 giây khi đang kết nối.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _addressController,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Địa chỉ Server',
            hintText: 'http://192.168.1.10:8080',
            prefixIcon: Icon(Icons.link_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: provider.isCheckingConnection ? null : _checkConnection,
          icon: provider.isCheckingConnection
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_find_rounded),
          label: Text(provider.isCheckingConnection
              ? 'Đang kiểm tra...'
              : 'Kiểm tra và kết nối'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed:
              provider.isCheckingConnection ? null : provider.useDemoMode,
          icon: const Icon(Icons.science_outlined),
          label: const Text('Chuyển về chế độ demo'),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Endpoint mặc định',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 10),
                const Text('GET  /api/devices'),
                const Text('GET  /api/sensors/latest'),
                const Text('GET  /api/devices/{id}/status'),
                const Text('POST /api/devices/{id}/control'),
                const Text('GET  /api/history'),
                const Text('POST /api/simulator/publish'),
                const SizedBox(height: 10),
                Text(
                  'Có thể thay đổi đường dẫn endpoint trong '
                  'lib/services/api_service.dart.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _checkConnection() async {
    final provider = context.read<SmartHomeProvider>();
    await provider.connectToServer(_addressController.text);
    if (!mounted) return;
    final message = provider.isConnected
        ? 'Kết nối Server thành công.'
        : provider.connectionError ?? 'Không thể kết nối Server.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
