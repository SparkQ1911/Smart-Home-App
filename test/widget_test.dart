import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smart_home_app/main.dart';
import 'package:smart_home_app/models/auth_user.dart';
import 'package:smart_home_app/providers/smart_home_provider.dart';
import 'package:smart_home_app/services/api_service.dart';

void main() {
  testWidgets('demo home and all navigation destinations render',
      (WidgetTester tester) async {
    final provider = SmartHomeProvider(apiService: ApiService());
    addTearDown(provider.dispose);
    await provider.restoreSession();
    provider.currentUser = const AuthUser(
      id: 'test-user',
      name: 'Test User',
      email: 'test@example.com',
    );
    provider.useDemoMode();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const SmartHomeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Smart Home'), findsWidgets);
    expect(find.text('Chế độ demo'), findsOneWidget);
    expect(find.text('28.0 °C'), findsOneWidget);
    expect(find.text('Phòng khách'), findsOneWidget);

    await tester.tap(find.text('Cảm biến').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Dữ liệu minh họa'), findsOneWidget);
    expect(find.text('Nhà bếp'), findsOneWidget);

    await tester.tap(find.text('Lịch sử').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Chế độ demo không lưu lịch sử trên Server.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cài đặt').last);
    await tester.pumpAndSettle();
    expect(find.text('test@example.com'), findsOneWidget);
    expect(find.text('Cấu hình Server'), findsNothing);
    expect(find.text('Endpoint mặc định'), findsNothing);
  });

  testWidgets('unauthenticated users see login and registration forms',
      (WidgetTester tester) async {
    final provider = SmartHomeProvider(apiService: ApiService());
    addTearDown(provider.dispose);
    await provider.restoreSession();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const SmartHomeApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập'), findsWidgets);

    await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
    await tester.pumpAndSettle();
    expect(find.text('Tạo tài khoản'), findsOneWidget);
    expect(find.text('Tên hiển thị'), findsOneWidget);
    expect(find.text('Nhập lại mật khẩu'), findsOneWidget);
  });
}
