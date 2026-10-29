import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/smart_home_provider.dart';
import 'screens/devices_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/sensors_screen.dart';
import 'screens/settings_screen.dart';
import 'services/api_service.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final provider = SmartHomeProvider(apiService: ApiService())
          ..initialize();
        const serverUrl = String.fromEnvironment(
          'SMART_HOME_SERVER_URL',
          defaultValue: 'https://smart-home-demo-api.onrender.com',
        );
        if (serverUrl.isNotEmpty) {
          unawaited(provider.connectToServer(serverUrl));
        }
        return provider;
      },
      child: const SmartHomeApp(),
    ),
  );
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3867D6),
          surface: const Color(0xFFF6F8FC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
        fontFamily: 'Roboto',
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFE8ECF4)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F8FC),
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF17233C),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
          iconTheme: IconThemeData(color: Color(0xFF34435F)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFF3867D6).withValues(alpha: 0.12),
          elevation: 0,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            );
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE0E6F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE0E6F0)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: const SmartHomeShell(),
    );
  }
}

class SmartHomeShell extends StatefulWidget {
  const SmartHomeShell({super.key});

  @override
  State<SmartHomeShell> createState() => _SmartHomeShellState();
}

class _SmartHomeShellState extends State<SmartHomeShell> {
  int _selectedIndex = 0;

  static const _screens = <Widget>[
    HomeScreen(),
    DevicesScreen(),
    SensorsScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  static const _titles = <String>[
    'Smart Home',
    'Thiết bị',
    'Cảm biến',
    'Lịch sử',
    'Cài đặt',
  ];

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Trang chủ',
    ),
    NavigationDestination(
      icon: Icon(Icons.devices_outlined),
      selectedIcon: Icon(Icons.devices_rounded),
      label: 'Thiết bị',
    ),
    NavigationDestination(
      icon: Icon(Icons.sensors_outlined),
      selectedIcon: Icon(Icons.sensors_rounded),
      label: 'Cảm biến',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_rounded),
      label: 'Lịch sử',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Cài đặt',
    ),
  ];

  void _selectDestination(int index) {
    setState(() => _selectedIndex = index);
    final provider = context.read<SmartHomeProvider>();
    if (index == 1) {
      provider.loadDevices();
    } else if (index == 2) {
      provider.loadSensors();
    } else if (index == 3) {
      provider.loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'Làm mới dữ liệu',
            onPressed: context.read<SmartHomeProvider>().refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final useRail = constraints.maxWidth >= 800;
          return Row(
            children: [
              if (useRail)
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectDestination,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Colors.white,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: Text('Trang chủ'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.devices_outlined),
                      selectedIcon: Icon(Icons.devices_rounded),
                      label: Text('Thiết bị'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.sensors_outlined),
                      selectedIcon: Icon(Icons.sensors_rounded),
                      label: Text('Cảm biến'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.history_rounded),
                      label: Text('Lịch sử'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings_rounded),
                      label: Text('Cài đặt'),
                    ),
                  ],
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: _screens,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 800
          ? NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectDestination,
              destinations: _destinations,
            )
          : null,
    );
  }
}
