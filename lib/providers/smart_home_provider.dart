import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/history_entry.dart';
import '../models/sensor_data.dart';
import '../services/api_service.dart';

enum DataMode { demo, server }

class SmartHomeProvider extends ChangeNotifier {
  SmartHomeProvider({required ApiService apiService})
      : _apiService = apiService;

  final ApiService _apiService;
  DataMode mode = DataMode.demo;
  String serverAddress = '';
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
    _loadDemoData();
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

  Future<void> connectToServer(String address) async {
    if (isCheckingConnection) return;
    isCheckingConnection = true;
    connectionError = null;
    notifyListeners();
    try {
      _apiService.configure(address);
      serverAddress = _apiService.baseUrl ?? address.trim();
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
