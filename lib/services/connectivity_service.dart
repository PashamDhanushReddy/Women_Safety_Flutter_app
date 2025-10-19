import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_signal_strength/flutter_signal_strength.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isMonitoring = false;

  // Emergency numbers for India
  static const String POLICE_NUMBER = '100';
  static const String MEDICAL_EMERGENCY_NUMBER = '108';
  static const String FIRE_EMERGENCY_NUMBER = '101';

  // Stream for connectivity changes
  Stream<List<ConnectivityResult>> get connectivityStream => _connectivity.onConnectivityChanged;

  /// Check current connectivity status
  Future<List<ConnectivityResult>> checkConnectivity() async {
    try {
      return await _connectivity.checkConnectivity();
    } catch (e) {
      print('Error checking connectivity: $e');
      return [ConnectivityResult.none];
    }
  }

  /// Check if there's active network connection (WiFi or Mobile Data)
  Future<bool> hasNetworkConnection() async {
    final results = await checkConnectivity();
    return results.isNotEmpty && !results.contains(ConnectivityResult.none);
  }

  /// Check if there's mobile data connection specifically
  Future<bool> hasMobileDataConnection() async {
    final results = await checkConnectivity();
    return results.contains(ConnectivityResult.mobile);
  }

  /// Check if there's WiFi connection
  Future<bool> hasWiFiConnection() async {
    final results = await checkConnectivity();
    return results.contains(ConnectivityResult.wifi);
  }

  /// Start monitoring connectivity changes
  void startConnectivityMonitoring(Function(bool) onConnectivityChanged) {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final hasConnection = results.isNotEmpty && !results.contains(ConnectivityResult.none);
        print('Connectivity changed: $results, hasConnection: $hasConnection');
        onConnectivityChanged(hasConnection);
      },
      onError: (error) {
        print('Connectivity monitoring error: $error');
      },
    );
  }

  /// Stop monitoring connectivity changes
  void stopConnectivityMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isMonitoring = false;
  }

  /// Make emergency call with fallback logic
  /// If no signal, try calling emergency numbers directly
  Future<bool> makeEmergencyCall({String? contactNumber}) async {
    try {
      // Check phone permission first
      final phonePermission = await Permission.phone.status;
      if (!phonePermission.isGranted) {
        print('Phone permission not granted for emergency call');
        return false;
      }

      // Check connectivity status
      final hasConnection = await hasNetworkConnection();
      
      if (hasConnection && contactNumber != null) {
        // Normal case: has network connection, call the contact
        print('Making emergency call to contact: $contactNumber');
        final result = await FlutterPhoneDirectCaller.callNumber(contactNumber);
        return result ?? false;
      } else if (!hasConnection) {
        // No network connection - try emergency numbers
        print('No network connection detected - attempting emergency numbers');
        return await _callEmergencyNumbers();
      } else {
        // Has connection but no contact provided - use emergency numbers
        print('No contact provided - using emergency numbers');
        return await _callEmergencyNumbers();
      }
    } catch (e) {
      print('Error making emergency call: $e');
      // Fallback: try emergency numbers even if there are errors
      return await _callEmergencyNumbers();
    }
  }

  /// Try calling emergency numbers (100, 108, 101) in sequence
  Future<bool> _callEmergencyNumbers() async {
    final emergencyNumbers = [POLICE_NUMBER, MEDICAL_EMERGENCY_NUMBER, FIRE_EMERGENCY_NUMBER];
    
    for (final number in emergencyNumbers) {
      try {
        print('Attempting emergency call to $number');
        final success = await FlutterPhoneDirectCaller.callNumber(number);
        if (success ?? false) {
          print('Successfully connected to emergency number: $number');
          return true;
        }
      } catch (e) {
        print('Failed to call $number: $e');
        continue;
      }
    }
    
    print('All emergency numbers failed');
    return false;
  }

  /// Get current connectivity status as a readable string
  Future<String> getConnectivityStatus() async {
    final results = await checkConnectivity();
    
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      return 'No Network Connection';
    }
    
    final statusParts = <String>[];
    
    if (results.contains(ConnectivityResult.wifi)) {
      statusParts.add('WiFi');
    }
    if (results.contains(ConnectivityResult.mobile)) {
      statusParts.add('Mobile Data');
    }
    if (results.contains(ConnectivityResult.ethernet)) {
      statusParts.add('Ethernet');
    }
    if (results.contains(ConnectivityResult.bluetooth)) {
      statusParts.add('Bluetooth');
    }
    
    return statusParts.isNotEmpty ? '${statusParts.join(' + ')} Connected' : 'Unknown Connection';
  }

  /// Check if emergency calling is possible
  Future<Map<String, dynamic>> checkEmergencyCallingStatus() async {
    final hasConnection = await hasNetworkConnection();
    final hasMobileData = await hasMobileDataConnection();
    final phonePermission = await Permission.phone.status;
    
    return {
      'hasNetworkConnection': hasConnection,
      'hasMobileData': hasMobileData,
      'phonePermissionGranted': phonePermission.isGranted,
      'canMakeEmergencyCall': phonePermission.isGranted,
      'connectivityStatus': await getConnectivityStatus(),
      'emergencyNumbersAvailable': [POLICE_NUMBER, MEDICAL_EMERGENCY_NUMBER, FIRE_EMERGENCY_NUMBER],
    };
  }

  /// Dispose resources
  void dispose() {
    stopConnectivityMonitoring();
  }

  /// Get mobile signal strength (0-4 bars)
  Future<int> getMobileSignalStrength() async {
    try {
      // First check if mobile data is available
      final hasMobileData = await hasMobileDataConnection();
      if (!hasMobileData) {
        print('Mobile data is turned off or not available');
        return -1; // Special value to indicate no signal
      }
      
      final signalStrength = FlutterSignalStrength();
      final cellularSignal = await signalStrength.getCellularSignalStrength();
      print('Raw cellular signal strength: $cellularSignal');
      
      // The plugin returns signal level 0-4 directly
      if (cellularSignal != null) {
        return cellularSignal.clamp(0, 4);
      }
      return 0; // 0 bars means very poor signal but still connected
    } catch (e) {
      print('Error getting mobile signal strength: $e');
      return -1; // Special value to indicate no signal/error
    }
  }

  /// Get detailed mobile signal information
  Future<Map<String, dynamic>> getMobileSignalInfo() async {
    try {
      // First check if mobile data is available
      final hasMobileData = await hasMobileDataConnection();
      if (!hasMobileData) {
        print('Mobile data is turned off or not available');
        return {
          'signalBars': -1,
          'signalQuality': 'No Signal',
          'rawSignalLevel': 'N/A',
          'rawSignalDbm': 'N/A',
          'networkType': 'No Signal',
          'isRoaming': false,
          'error': 'Mobile data is turned off or not available',
        };
      }
      
      final signalStrength = FlutterSignalStrength();
      final cellularSignal = await signalStrength.getCellularSignalStrength();
      final cellularSignalDbm = await signalStrength.getCellularSignalStrengthDbm();
      
      print('Cellular signal level: $cellularSignal');
      print('Cellular signal dBm: $cellularSignalDbm');
      
      // Convert signal level to bars (0-4)
      int signalBars = 0;
      String signalQuality = 'Unknown';
      
      if (cellularSignal != null) {
        signalBars = cellularSignal.clamp(0, 4);
        
        // Map signal level to quality description
        switch (signalBars) {
          case 4:
            signalQuality = 'Excellent';
            break;
          case 3:
            signalQuality = 'Good';
            break;
          case 2:
            signalQuality = 'Fair';
            break;
          case 1:
            signalQuality = 'Poor';
            break;
          default:
            signalQuality = 'Very Poor';
            break;
        }
      }

      return {
        'signalBars': signalBars,
        'signalQuality': signalQuality,
        'rawSignalLevel': cellularSignal ?? 'N/A',
        'rawSignalDbm': cellularSignalDbm ?? 'N/A',
        'networkType': 'Mobile', // Basic network type since flutter_signal_strength doesn't provide detailed type
        'isRoaming': false, // Not available in flutter_signal_strength
      };
    } catch (e) {
      print('Error getting mobile signal info: $e');
      return {
        'signalBars': -1,
        'signalQuality': 'No Signal',
        'rawSignalLevel': 'N/A',
        'rawSignalDbm': 'N/A',
        'networkType': 'No Signal',
        'isRoaming': false,
        'error': 'Mobile data is turned off or not available',
      };
    }
  }

  /// Convert network type to readable name
  String _getNetworkTypeName(dynamic networkType) {
    if (networkType == null) return 'Unknown';
    
    switch (networkType.toString()) {
      case 'NETWORK_TYPE_GPRS':
      case 'NETWORK_TYPE_EDGE':
        return '2G';
      case 'NETWORK_TYPE_UMTS':
      case 'NETWORK_TYPE_HSPA':
      case 'NETWORK_TYPE_HSPAP':
        return '3G';
      case 'NETWORK_TYPE_LTE':
        return '4G';
      case 'NETWORK_TYPE_NR':
        return '5G';
      default:
        return 'Mobile';
    }
  }
}