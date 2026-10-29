import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smart_home_app/main.dart';
import 'package:smart_home_app/providers/smart_home_provider.dart';
import 'package:smart_home_app/services/api_service.dart';

void main() {
  testWidgets('demo home and all navigation destinations render',
      (WidgetTester tester) async {
    final provider = SmartHomeProvider(apiService: ApiService())..initialize();
    addTearDown(provider.dispose);

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
  });
}
