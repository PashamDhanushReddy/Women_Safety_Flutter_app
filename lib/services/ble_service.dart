import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'background_service.dart';

// Import the global function
import 'background_service.dart' as bg_service;

class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  // Bluetooth state
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  
  // Device discovery
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final StreamController<List<ScanResult>> _scanResultsController = StreamController<List<ScanResult>>.broadcast();
  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;
  
  // Connected device
  BluetoothDevice? _connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  final StreamController<BluetoothDevice?> _deviceConnectionController = StreamController<BluetoothDevice?>.broadcast();
  Stream<BluetoothDevice?> get deviceConnection => _deviceConnectionController.stream;
  
  // Device data
  final StreamController<Map<String, dynamic>> _deviceDataController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get deviceData => _deviceDataController.stream;
  
  // Heart rate monitoring
  Timer? _heartRateMonitorTimer;
  int _currentHeartRate = 0;
  static const int HEART_RATE_SOS_THRESHOLD = 120; // BPM - adjust as needed
  static const Duration HEART_RATE_CHECK_INTERVAL = Duration(seconds: 10);
  bool _sosTriggeredForHighHR = false;
  
  // Fastrack specific constants
  static const String TARGET_DEVICE_NAME = 'Fastrack Reflex 8601';
  static const String TARGET_DEVICE_PREFIX = 'Fastrack';
  static const Duration SCAN_TIMEOUT = Duration(seconds: 30);
  static const Duration CONNECTION_TIMEOUT = Duration(seconds: 15);
  
  // GATT Service UUIDs (common for many smartwatches)
  static const String DEVICE_INFORMATION_SERVICE = '0000180a-0000-1000-8000-00805f9b34fb';
  static const String BATTERY_SERVICE = '0000180f-0000-1000-8000-00805f9b34fb';
  static const String HEART_RATE_SERVICE = '0000180d-0000-1000-8000-00805f9b34fb';
  static const String FITNESS_SERVICE = '00001816-0000-1000-8000-00805f9b34fb';
  
  // Initialize BLE service
  Future<bool> initialize() async {
    try {
      print('=== Initializing BLE Service ===');
      
      // Check permissions
      if (!await _checkPermissions()) {
        print('❌ BLE permissions not granted');
        return false;
      }
      
      // Initialize adapter state monitoring
      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
        _adapterState = state;
        print('📡 Bluetooth adapter state: $state');
      });
      
      // Wait for adapter to be ready
      await _waitForAdapterReady();
      
      // Check if Bluetooth is actually enabled
      if (_adapterState != BluetoothAdapterState.on) {
        print('❌ Bluetooth is not enabled');
        return false;
      }
      
      print('✅ BLE Service initialized successfully');
      return true;
    } catch (e) {
      print('❌ Error initializing BLE Service: $e');
      return false;
    }
  }

  // Check and request permissions
  Future<bool> _checkPermissions() async {
    try {
      print('🔍 Checking BLE permissions...');
      
      // Request Bluetooth permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      
      // Check if all permissions are granted
      bool allGranted = statuses.values.every((status) => status.isGranted);
      
      if (allGranted) {
        print('✅ All BLE permissions granted');
      } else {
        print('❌ Some permissions denied: $statuses');
      }
      
      return allGranted;
    } catch (e) {
      print('❌ Error checking permissions: $e');
      return false;
    }
  }

  // Wait for Bluetooth adapter to be ready
  Future<void> _waitForAdapterReady() async {
    try {
      print('⏳ Waiting for Bluetooth adapter to be ready...');
      
      // Wait up to 10 seconds for adapter to be ready
      int attempts = 0;
      while (_adapterState != BluetoothAdapterState.on && attempts < 20) {
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
      }
      
      if (_adapterState == BluetoothAdapterState.on) {
        print('✅ Bluetooth adapter is ready');
      } else {
        print('⚠️ Bluetooth adapter not ready after timeout');
      }
    } catch (e) {
      print('❌ Error waiting for adapter: $e');
    }
  }

  // Start scanning for devices
  Future<bool> startScanning() async {
    try {
      print('🔍 Starting device scan...');
      
      if (_adapterState != BluetoothAdapterState.on) {
        print('❌ Bluetooth is not enabled');
        return false;
      }
      
      // Stop any existing scan
      await stopScanning();
      
      // Start scanning with results stream
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          print('📱 Found ${results.length} devices');
          _scanResultsController.add(results);
          
          // Look for Fastrack device
          for (var result in results) {
            final device = result.device;
            final deviceName = device.platformName ?? 'Unknown';
            
            if (deviceName.contains(TARGET_DEVICE_PREFIX) || 
                deviceName.contains('Reflex') || 
                deviceName.contains('Fastrack')) {
              print('🎯 Found potential Fastrack device: $deviceName (${device.remoteId})');
              print('  RSSI: ${result.rssi} dBm');
              print('  Connectable: ${result.advertisementData.connectable}');
            }
          }
        },
        onError: (error) {
          print('❌ Scan error: $error');
        },
      );
      
      // Start scanning with timeout
      await FlutterBluePlus.startScan(
        timeout: SCAN_TIMEOUT,
        androidUsesFineLocation: true,
      );
      
      print('✅ Device scan started');
      return true;
    } catch (e) {
      print('❌ Error starting scan: $e');
      return false;
    }
  }

  // Stop scanning for devices
  Future<void> stopScanning() async {
    try {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      await FlutterBluePlus.stopScan();
      print('⏹️ Device scan stopped');
    } catch (e) {
      print('❌ Error stopping scan: $e');
    }
  }

  // Connect to a specific device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      print('🔌 Connecting to device: ${device.platformName} (${device.remoteId})');
      
      // Disconnect from any existing device
      await disconnect();
      
      // Set connection timeout
      final connectionFuture = device.connect(timeout: CONNECTION_TIMEOUT);
      
      // Monitor connection state
      _connectionSubscription = device.connectionState.listen((state) async {
        print('📡 Connection state: $state');
        
        if (state == BluetoothConnectionState.connected) {
          _connectedDevice = device;
          _deviceConnectionController.add(device);
          print('✅ Connected to ${device.platformName}');
          
          // Discover services after connection
          await _discoverServices(device);
        } else if (state == BluetoothConnectionState.disconnected) {
          _connectedDevice = null;
          _deviceConnectionController.add(null);
          print('❌ Disconnected from ${device.platformName}');
        }
      });
      
      await connectionFuture;
      return true;
    } catch (e) {
      print('❌ Connection error: $e');
      return false;
    }
  }

  // Disconnect from current device
  Future<void> disconnect() async {
    try {
      if (_connectedDevice != null) {
        print('🔌 Disconnecting from ${_connectedDevice!.platformName}');
        await _connectedDevice!.disconnect();
        await _connectionSubscription?.cancel();
        _connectionSubscription = null;
        _connectedDevice = null;
        _deviceConnectionController.add(null);
      }
    } catch (e) {
      print('❌ Error disconnecting: $e');
    }
  }

  // Discover GATT services
  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      print('🔍 Discovering GATT services for ${device.platformName}...');
      
      List<BluetoothService> services = await device.discoverServices();
      print('📋 Found ${services.length} services');
      
      Map<String, dynamic> deviceData = {};
      
      for (BluetoothService service in services) {
        final serviceUuid = service.uuid.str128.toLowerCase();
        print('\n📡 Service: $serviceUuid');
        
        // Check for known services
        if (serviceUuid == DEVICE_INFORMATION_SERVICE) {
          deviceData['device_info'] = await _readDeviceInformation(service);
        } else if (serviceUuid == BATTERY_SERVICE) {
          deviceData['battery'] = await _readBatteryLevel(service);
        } else if (serviceUuid == HEART_RATE_SERVICE) {
          deviceData['heart_rate'] = await _readHeartRate(service);
        } else if (serviceUuid == FITNESS_SERVICE) {
          deviceData['fitness'] = await _readFitnessData(service);
        }
        
        // Print all characteristics for debugging
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          final charUuid = characteristic.uuid.str128.toLowerCase();
          print('  🔍 Characteristic: $charUuid');
          print('    Properties: ${characteristic.properties}');
        }
      }
      
      // Emit device data
      _deviceDataController.add(deviceData);
      print('✅ Device data discovered: $deviceData');
      
    } catch (e) {
      print('❌ Error discovering services: $e');
    }
  }

  // Read device information
  Future<Map<String, String>> _readDeviceInformation(BluetoothService service) async {
    Map<String, String> info = {};
    
    try {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        final charUuid = characteristic.uuid.str128.toLowerCase();
        
        if (characteristic.properties.read) {
          try {
            List<int> value = await characteristic.read();
            String stringValue = String.fromCharCodes(value);
            
            switch (charUuid) {
              case '00002a29-0000-1000-8000-00805f9b34fb': // Manufacturer Name
                info['manufacturer'] = stringValue;
                break;
              case '00002a24-0000-1000-8000-00805f9b34fb': // Model Number
                info['model'] = stringValue;
                break;
              case '00002a25-0000-1000-8000-00805f9b34fb': // Serial Number
                info['serial'] = stringValue;
                break;
              case '00002a27-0000-1000-8000-00805f9b34fb': // Hardware Revision
                info['hardware'] = stringValue;
                break;
              case '00002a28-0000-1000-8000-00805f9b34fb': // Software Revision
                info['software'] = stringValue;
                break;
            }
          } catch (e) {
            print('⚠️ Could not read characteristic $charUuid: $e');
          }
        }
      }
    } catch (e) {
      print('❌ Error reading device information: $e');
    }
    
    return info;
  }

  // Read battery level
  Future<int?> _readBatteryLevel(BluetoothService service) async {
    try {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        final charUuid = characteristic.uuid.str128.toLowerCase();
        
        if (charUuid == '00002a19-0000-1000-8000-00805f9b34fb' && characteristic.properties.read) { // Battery Level
          List<int> value = await characteristic.read();
          if (value.isNotEmpty) {
            return value[0];
          }
        }
      }
    } catch (e) {
      print('❌ Error reading battery level: $e');
    }
    return null;
  }

  // Read heart rate data
  Future<Map<String, dynamic>?> _readHeartRate(BluetoothService service) async {
    try {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        final charUuid = characteristic.uuid.str128.toLowerCase();
        
        if (charUuid == '00002a37-0000-1000-8000-00805f9b34fb') { // Heart Rate Measurement
          Map<String, dynamic> heartRateData = {};
          
          if (characteristic.properties.read) {
            List<int> value = await characteristic.read();
            if (value.isNotEmpty) {
              heartRateData['current_hr'] = value[1];
            }
          }
          
          // Enable notifications if supported
          if (characteristic.properties.notify) {
            await characteristic.setNotifyValue(true);
            characteristic.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                final heartRate = value[1];
                _currentHeartRate = heartRate;
                _deviceDataController.add({'heart_rate': {'current_hr': heartRate}});
                print('❤️ Heart rate update: $heartRate bpm');
                
                // Check heart rate for SOS trigger
                _checkHeartRateForSOS();
              }
            });
            
            // Start heart rate monitoring
            _startHeartRateMonitoring();
          }
          
          return heartRateData;
        }
      }
    } catch (e) {
      print('❌ Error reading heart rate: $e');
    }
    return null;
  }

  // Read fitness data
  Future<Map<String, dynamic>?> _readFitnessData(BluetoothService service) async {
    try {
      Map<String, dynamic> fitnessData = {};
      
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        final charUuid = characteristic.uuid.str128.toLowerCase();
        
        if (characteristic.properties.read) {
          try {
            List<int> value = await characteristic.read();
            
            // Common fitness data characteristic UUIDs
            if (charUuid.contains('2a53') || charUuid.contains('steps')) {
              // Steps data (manufacturer specific)
              fitnessData['steps'] = _parseStepsData(value);
            } else if (charUuid.contains('2a54') || charUuid.contains('distance')) {
              // Distance data
              fitnessData['distance'] = _parseDistanceData(value);
            } else if (charUuid.contains('2a55') || charUuid.contains('calories')) {
              // Calories data
              fitnessData['calories'] = _parseCaloriesData(value);
            }
          } catch (e) {
            print('⚠️ Could not read fitness characteristic $charUuid: $e');
          }
        }
      }
      
      return fitnessData.isNotEmpty ? fitnessData : null;
    } catch (e) {
      print('❌ Error reading fitness data: $e');
      return null;
    }
  }

  // Parse steps data (manufacturer specific)
  int _parseStepsData(List<int> value) {
    if (value.length >= 4) {
      // Common format: 4 bytes little-endian
      return value[0] | (value[1] << 8) | (value[2] << 16) | (value[3] << 24);
    }
    return 0;
  }

  // Parse distance data (manufacturer specific)
  double _parseDistanceData(List<int> value) {
    if (value.length >= 4) {
      // Common format: 4 bytes little-endian, in meters
      int meters = value[0] | (value[1] << 8) | (value[2] << 16) | (value[3] << 24);
      return meters.toDouble();
    }
    return 0.0;
  }

  // Parse calories data (manufacturer specific)
  double _parseCaloriesData(List<int> value) {
    if (value.length >= 2) {
      // Common format: 2 bytes little-endian, in kcal
      int calories = value[0] | (value[1] << 8);
      return calories.toDouble();
    }
    return 0.0;
  }

  // Get current connected device
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // Check if connected to Fastrack device
  bool get isConnectedToFastrack {
    if (_connectedDevice == null) return false;
    final deviceName = _connectedDevice!.platformName ?? '';
    return deviceName.contains(TARGET_DEVICE_PREFIX) || 
           deviceName.contains('Reflex') || 
           deviceName.contains('Fastrack');
  }

  // Get current heart rate
  int get currentHeartRate => _currentHeartRate;

  // Get heart rate threshold
  int get heartRateThreshold => HEART_RATE_SOS_THRESHOLD;

  // Update heart rate threshold (if you want to make it configurable)
  void updateHeartRateThreshold(int newThreshold) {
    print('📊 Updating heart rate threshold from $HEART_RATE_SOS_THRESHOLD to $newThreshold BPM');
    // Note: This would require making HEART_RATE_SOS_THRESHOLD non-constant
    // For now, we'll just log it and restart monitoring
    _startHeartRateMonitoring();
  }

  // Start heart rate monitoring
  void _startHeartRateMonitoring() {
    _heartRateMonitorTimer?.cancel();
    
    print('🔍 Starting heart rate monitoring (threshold: $HEART_RATE_SOS_THRESHOLD BPM)');
    
    _heartRateMonitorTimer = Timer.periodic(HEART_RATE_CHECK_INTERVAL, (timer) {
      _checkHeartRateForSOS();
    });
  }

  // Check heart rate and trigger SOS if threshold exceeded
  void _checkHeartRateForSOS() {
    if (_currentHeartRate <= 0) return;
    
    print('🔍 Checking heart rate: $_currentHeartRate BPM (threshold: $HEART_RATE_SOS_THRESHOLD BPM)');
    
    if (_currentHeartRate > HEART_RATE_SOS_THRESHOLD) {
      print('⚠️ HIGH HEART RATE DETECTED: $_currentHeartRate BPM');
      
      // Only trigger SOS once per elevated heart rate episode
      if (!_sosTriggeredForHighHR) {
        _sosTriggeredForHighHR = true;
        _triggerSOSForHighHeartRate();
      }
    } else {
      // Reset SOS trigger when heart rate returns to normal
      if (_sosTriggeredForHighHR) {
        print('✅ Heart rate returned to normal: $_currentHeartRate BPM');
        _sosTriggeredForHighHR = false;
      }
    }
  }

  // Trigger SOS for high heart rate
  void _triggerSOSForHighHeartRate() async {
    print('🚨 TRIGGERING SOS FOR HIGH HEART RATE: $_currentHeartRate BPM');
    
    try {
      // Use the global triggerEmergencyFromCheckpoint function
      await bg_service.triggerEmergencyFromCheckpoint();
      
      print('✅ SOS triggered successfully for high heart rate');
    } catch (e) {
      print('❌ Error triggering SOS for high heart rate: $e');
    }
  }

  // Dispose resources
  void dispose() {
    print('🧹 Disposing BLE Service...');
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _scanResultsController.close();
    _deviceConnectionController.close();
    _deviceDataController.close();
    _heartRateMonitorTimer?.cancel();
    stopScanning();
    disconnect();
  }
}