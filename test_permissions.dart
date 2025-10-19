import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  print('=== Testing Permission Handler ===');
  
  // Clear SharedPreferences to simulate first launch
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  print('SharedPreferences cleared - app will show permission screen on next launch');
  
  // Test individual permissions
  final permissions = [
    Permission.microphone,
    Permission.location,
    Permission.phone,
    Permission.sms,
    Permission.notification,
    Permission.contacts,
    Permission.camera,
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.ignoreBatteryOptimizations,
  ];
  
  print('\nTesting permission statuses before requesting:');
  for (var permission in permissions) {
    final status = await permission.status;
    print('${permission.toString()}: $status');
  }
  
  print('\n=== Requesting all permissions ===');
  final statuses = await permissions.request();
  
  print('\nTesting permission statuses after requesting:');
  for (var permission in permissions) {
    final status = statuses[permission] ?? await permission.status;
    print('${permission.toString()}: $status');
  }
  
  print('\n=== Testing Android version specific behavior ===');
  print('Note: On Android 12+, BLUETOOTH_SCAN and BLUETOOTH_CONNECT are required');
  print('On Android 11 and below, only BLUETOOTH permission is needed');
}