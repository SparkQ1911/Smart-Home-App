import 'package:flutter/material.dart';

import '../providers/smart_home_provider.dart';

Future<void> controlDeviceWithFeedback(
  BuildContext context,
  SmartHomeProvider provider,
  String deviceName,
  String deviceId,
  bool value,
) async {
  try {
    final changed = await provider.setDeviceState(deviceId, value);
    if (changed && context.mounted && provider.mode == DataMode.demo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$deviceName đã đổi trạng thái trong chế độ demo.')),
      );
    }
  } on Exception catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể điều khiển $deviceName: $error')),
      );
    }
  }
}
