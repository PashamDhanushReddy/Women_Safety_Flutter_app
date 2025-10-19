import 'package:permission_handler/permission_handler.dart';

void main() async {
  print('=== Bluetooth Permission Test ===');
  
  // Test individual Bluetooth permissions
  final bluetoothPermissions = [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ];
  
  print('\n1. Checking Bluetooth permission statuses before requesting:');
  for (var permission in bluetoothPermissions) {
    final status = await permission.status;
    print('${permission.toString()}: $status');
  }
  
  print('\n2. Requesting Bluetooth permissions individually:');
  for (var permission in bluetoothPermissions) {
    print('\nRequesting: $permission');
    final status = await permission.request();
    print('Result: $status');
    
    if (status.isGranted) {
      print('✓ Permission granted');
    } else if (status.isDenied) {
      print('✗ Permission denied');
    } else if (status.isPermanentlyDenied) {
      print('✗ Permission permanently denied - user needs to enable in settings');
    } else if (status.isRestricted) {
      print('⚠ Permission restricted');
    } else if (status.isLimited) {
      print('⚠ Permission limited');
    }
    
    // Wait a bit between requests
    await Future.delayed(const Duration(seconds: 1));
  }
  
  print('\n3. Final status check:');
  for (var permission in bluetoothPermissions) {
    final status = await permission.status;
    print('${permission.toString()}: $status');
  }
  
  print('\n=== Test Complete ===');
  print('If no dialogs appeared, check:');
  print('- Android manifest has correct permissions');
  print('- Device/emulator supports Bluetooth');
  print('- App is not in background');
  print('- Permission handler plugin version is compatible');
}