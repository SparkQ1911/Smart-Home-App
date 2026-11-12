import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/auth_user.dart';
import '../models/device.dart';
import '../models/history_entry.dart';
import '../models/sensor_data.dart';
import '../services/api_service.dart';
import '../services/session_store.dart';

enum DataMode { demo, server }

class SmartHomeProvider extends ChangeNotifier {
  SmartHomeProvider({
    required ApiService apiService,
    SessionStore? sessionStore,
  })  : _apiService = apiService,
        _sessionStore = sessionStore ?? MemorySessionStore() {
    _apiService.configure(AppConfig.apiBaseUrl);
  }

  final ApiService _apiService;
  final SessionStore _sessionStore;
  DataMode mode = DataMode.demo;
  AuthUser? currentUser;
  String? authError;
  bool isInitializing = true;
  bool isAuthBusy = false;
  bool isConnected = false;
  bool isCheckingConnection = false;
  bool isLoadingDevices = false;
  bool isLoadingSensors = false;
  bool isLoadingHistory = false;
  String? connectionError;
  String? devicesError;
  String? sensorsError;
  String? historyError;
  bool historySupported = true;
  SensorData? sensors;
  List<Device> devices = const [];
  List<HistoryEntry> history = const [];
  final Set<String> _busyDeviceIds = {};
  Timer? _pollTimer;
  bool _isRefreshing = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _apiService.dispose();
    super.dispose();
  }

  bool isDeviceBusy(String id) => _busyDeviceIds.contains(id);
  int get activeDeviceCount => devices.where((device) => device.isOn).length;

  void initialize() {
    unawaited(restoreSession());
  }

  Future<void> restoreSession() async {
    isInitializing = true;
    notifyListeners();
    try {
      final token = await _sessionStore.readToken();
      if (token == null || token.isEmpty) return;
      _apiService.setAccessToken(token);
      currentUser = await _apiService.getCurrentUser();
      await connectToServer();
    } on ApiException catch (error) {
      authError = error.message;
      currentUser = null;
      _apiService.setAccessToken(null);
    } on Exception catch (error) {
      authError = 'Không thể khôi phục phiên đăng nhập: $error';
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await _authenticate(
      () => _apiService.register(
        name: name,
        email: email,
        password: password,
      ),
    );
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _authenticate(
      () => _apiService.login(email: email, password: password),
    );
  }

  Future<void> _authenticate(
    Future<AuthSession> Function() authenticate,
  ) async {
    if (isAuthBusy) return;
    isAuthBusy = true;
    authError = null;
    notifyListeners();
    try {
      final session = await authenticate();
      await _sessionStore.writeToken(session.token);
      _apiService.setAccessToken(session.token);
      currentUser = session.user;
      await connectToServer();
    } on ApiException catch (error) {
      authError = error.message;
      rethrow;
    } on Exception catch (error) {
      authError = 'Không thể lưu phiên đăng nhập an toàn: $error';
      throw ApiException(authError!);
    } finally {
      isAuthBusy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _sessionStore.clearToken();
    _apiService.setAccessToken(null);
    currentUser = null;
    authError = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _loadDemoData();
  }

  Future<void> deleteAccount({required String password}) async {
    await _apiService.deleteAccount(password: password);
    await logout();
  }

  void _loadDemoData() {
    mode = DataMode.demo;
    isConnected = false;
    connectionError = null;
    devicesError = null;
    sensorsError = null;
    historyError = null;
    historySupported = true;
    devices = const [
      Device(
        id: 'demo_light',
        name: 'Đèn phòng khách',
        type: 'light',
        isOn: true,
        room: 'Phòng khách',
      ),
      Device(
        id: 'demo_fan',
        name: 'Quạt phòng ngủ',
        type: 'fan',
        isOn: false,
        room: 'Phòng ngủ',
      ),
      Device(
        id: 'demo_ac',
        name: 'Điều hòa nhà bếp',
        type: 'air_conditioner',
        isOn: false,
        room: 'Nhà bếp',
      ),
    ];
    sensors = SensorData(
      temperature: 28,
      humidity: 65,
      updatedAt: DateTime.now(),
      extra: const {'Chất lượng không khí': 'Tốt'},
      rooms: [
        RoomSensorData(
          room: 'Phòng khách',
          temperature: 28,
          humidity: 65,
          updatedAt: DateTime.now(),
        ),
        RoomSensorData(
          room: 'Nhà bếp',
          temperature: 29,
          humidity: 61,
          updatedAt: DateTime.now(),
        ),
        RoomSensorData(
          room: 'Phòng ngủ',
          temperature: 26.5,
          humidity: 58,
          updatedAt: DateTime.now(),
        ),
      ],
    );
    history = const [];
    notifyListeners();
  }

  void useDemoMode() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _loadDemoData();
  }

  Future<void> connectToServer() async {
    if (isCheckingConnection) return;
    isCheckingConnection = true;
    connectionError = null;
    notifyListeners();
    try {
      mode = DataMode.server;
      isConnected = false;
      devices = const [];
      sensors = null;
      history = const [];
      devicesError = null;
      sensorsError = null;
      historyError = null;
      historySupported = true;
      notifyListeners();

      devices = await _apiService.getDevices();
      isConnected = true;
      connectionError = null;
      notifyListeners();
      await Future.wait([loadSensors(), loadHistory()]);
      _startPolling();
    } on ApiException catch (error) {
      mode = DataMode.server;
      isConnected = false;
      devices = const [];
      sensors = null;
      history = const [];
      connectionError = error.message;
      devicesError = error.message;
      sensorsError = error.message;
      notifyListeners();
    } finally {
      isCheckingConnection = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (mode == DataMode.demo) {
      _loadDemoData();
      return;
    }
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      await Future.wait([loadDevices(), loadSensors(), loadHistory()]);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> loadDevices() async {
    if (mode == DataMode.demo) return;
    isLoadingDevices = true;
    devicesError = null;
    notifyListeners();
    try {
      devices = await _apiService.getDevices();
      isConnected = true;
      connectionError = null;
    } on ApiException catch (error) {
      devicesError = error.message;
      isConnected = false;
      connectionError = error.message;
    } finally {
      isLoadingDevices = false;
      notifyListeners();
    }
  }

  Future<void> loadSensors() async {
    if (mode == DataMode.demo) return;
    isLoadingSensors = true;
    sensorsError = null;
    notifyListeners();
    try {
      sensors = await _apiService.getLatestSensors();
      isConnected = true;
    } on ApiException catch (error) {
      sensorsError = error.message;
    } finally {
      isLoadingSensors = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory() async {
    if (mode == DataMode.demo) return;
    isLoadingHistory = true;
    historyError = null;
    notifyListeners();
    try {
      history = await _apiService.getHistory();
      historySupported = true;
    } on HistoryNotSupportedException {
      history = const [];
      historySupported = false;
    } on ApiException catch (error) {
      historyError = error.message;
    } finally {
      isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<bool> setDeviceState(String id, bool turnOn) async {
    if (mode == DataMode.server && _busyDeviceIds.contains(id)) return false;
    final index = devices.indexWhere((device) => device.id == id);
    if (index < 0 || devices[index].isOn == turnOn) return false;

    _busyDeviceIds.add(id);
    notifyListeners();
    try {
      final confirmedState = mode == DataMode.demo
          ? turnOn
          : await _apiService.controlDevice(id, turnOn);
      devices = [
        for (final device in devices)
          if (device.id == id)
            device.copyWith(isOn: confirmedState)
          else
            device,
      ];
      if (mode == DataMode.server && confirmedState != turnOn) {
        throw const ApiException(
          'Server chưa xác nhận trạng thái thiết bị theo yêu cầu.',
        );
      }
      return true;
    } on ApiException catch (error) {
      connectionError = error.message;
      notifyListeners();
      rethrow;
    } finally {
      _busyDeviceIds.remove(id);
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mode == DataMode.server &&
          !isCheckingConnection &&
          !_isRefreshing &&
          !isLoadingDevices &&
          !isLoadingSensors &&
          !isLoadingHistory) {
        refresh();
      }
    });
  }
}
