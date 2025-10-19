import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hershield/screens/home_screen.dart';
import 'package:hershield/services/background_service.dart';
import 'package:hershield/services/overlay_service.dart';
import 'package:hershield/services/contacts_service.dart';
import 'package:hershield/services/safety_checkpoint_service.dart';
import 'package:hershield/services/google_fit_service.dart';

import 'package:hershield/services/mms_service.dart';
// Removed overlay assistant widget import
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shake/shake.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:send_message/send_message.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    print('✅ Firebase initialized successfully');
  } catch (e) {
    print('⚠️  Firebase initialization failed: $e');
    print('💡 This is expected if google-services.json is not configured yet.');
  }
  
  // Check if this is the first launch
  final prefs = await SharedPreferences.getInstance();
  final bool hasSeenPermissions = prefs.getBool('hasSeenPermissions') ?? false;
  
  // Initialize Google Fit service with authentication
  final googleFitService = GoogleFitService();
  await googleFitService.initialize();
  
  runApp(MyApp(hasSeenPermissions: hasSeenPermissions));
}

class ShakeDetectorHandler extends StatefulWidget {
  final Widget child;
  
  const ShakeDetectorHandler({super.key, required this.child});
  
  @override
  State<ShakeDetectorHandler> createState() => _ShakeDetectorHandlerState();
}

class _ShakeDetectorHandlerState extends State<ShakeDetectorHandler> {
  ShakeDetector? _shakeDetector;
  
  @override
  void initState() {
    super.initState();
    _initializeShakeDetector();
  }
  
  void _initializeShakeDetector() {
    _shakeDetector = ShakeDetector.autoStart(
      onPhoneShake: (ShakeEvent event) {
        _triggerEmergencyFromShake();
      },
      minimumShakeCount: 2, // Require 2 shakes to trigger
      shakeSlopTimeMS: 500, // Time between shakes
      shakeCountResetTime: 3000, // Reset after 3 seconds
      shakeThresholdGravity: 2.5, // Sensitivity
    );
  }
  
  Future<void> _triggerEmergencyFromShake() async {
    try {
      final first = await ContactsService.getFirstContact();
      final recipients = await ContactsService.getRecipientPhones();

      if (first == null || first.phone.isEmpty) {
        return; // No emergency contact set
      }
      
      // Get current location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () async =>
            await Geolocator.getLastKnownPosition() ??
            Position(
              latitude: 0,
              longitude: 0,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            ),
      );

      // Make emergency call - handle potential background limitations
      try {
        await FlutterPhoneDirectCaller.callNumber(first.phone);
        print('Emergency call initiated to ${first.name}');
      } catch (e) {
        print('Call failed: $e');
        // Even if call fails, SMS will still be sent
      }

      // Send emergency SMS message (no photos)
      String message = '🚨 EMERGENCY SOS from Emergency App! '
          'Location: https://maps.google.com/?q=${position.latitude},${position.longitude} '
          'Lat: ${position.latitude}, Long: ${position.longitude}';
      
      // Use SMS service to send message
      await MMSService.sendEmergencySMS(
        message: message,
        recipients: recipients,
      );

      print('Emergency triggered by shake for ${first.name} (SMS to ${recipients.length} contacts)');
    } catch (e) {
      print('Error triggering emergency from shake: $e');
    }
  }
  
  @override
  void dispose() {
    _shakeDetector?.stopListening();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

Future<void> _initializeNotifications() async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      try {
        print('=== NOTIFICATION RESPONSE RECEIVED ===');
        print('Payload: ${response.payload}');
        print('Action ID: ${response.actionId}');
        print('Notification ID: ${response.id}');
        print('Response type: ${response.notificationResponseType}');
        
        if (response.payload == 'sos') {
          print('SOS notification tapped (foreground)');
          await OverlayService.triggerEmergency();
        } else if (response.actionId == 'yes_action' || response.actionId == 'no_action') {
          // Handle safety checkpoint notification actions
          print('Safety checkpoint notification action: ${response.actionId}');
          if (response.actionId == 'yes_action') {
             // User is safe - cancel the safety check
             print('User confirmed safety from notification');
             // Cancel the safety check notification
             await flutterLocalNotificationsPlugin.cancel(SafetyCheckpointService.SAFETY_CHECK_NOTIFICATION_ID);
             print('Safety check notification cancelled');
           } else if (response.actionId == 'no_action') {
             // User needs help - trigger emergency immediately
             print('User needs help from notification - triggering emergency');
             print('Calling OverlayService.triggerEmergency()...');
             await OverlayService.triggerEmergency();
             print('Emergency triggered successfully');
             // Cancel the safety check notification
             await flutterLocalNotificationsPlugin.cancel(SafetyCheckpointService.SAFETY_CHECK_NOTIFICATION_ID);
             print('Safety check notification cancelled');
           }
        } else {
          print('Unknown notification response - payload: ${response.payload}, actionId: ${response.actionId}');
        }
        print('=== NOTIFICATION RESPONSE HANDLED ===');
      } catch (e, stackTrace) {
        print('Error handling notification tap: $e');
        print('Stack trace: $stackTrace');
      }
    },
    onDidReceiveBackgroundNotificationResponse: (NotificationResponse response) async {
      try {
        print('=== BACKGROUND NOTIFICATION RESPONSE RECEIVED ===');
        print('Payload: ${response.payload}');
        print('Action ID: ${response.actionId}');
        print('Notification ID: ${response.id}');
        print('Response type: ${response.notificationResponseType}');
        
        if (response.payload == 'sos') {
          print('SOS notification tapped (background)');
          // Ensure Flutter binding for background isolate
          WidgetsFlutterBinding.ensureInitialized();
          await OverlayService.triggerEmergency();
        } else if (response.actionId == 'yes_action' || response.actionId == 'no_action') {
          // Handle safety checkpoint notification actions in background
          print('Safety checkpoint notification action (background): ${response.actionId}');
          // Ensure Flutter binding for background isolate
          WidgetsFlutterBinding.ensureInitialized();
          if (response.actionId == 'no_action') {
            // User needs help - trigger emergency immediately
            print('User needs help from background notification - triggering emergency');
            print('Calling OverlayService.triggerEmergency() from background...');
            await OverlayService.triggerEmergency();
            print('Emergency triggered successfully from background');
          } else if (response.actionId == 'yes_action') {
            print('User confirmed safety from background notification');
          }
          // Cancel the safety check notification
           await flutterLocalNotificationsPlugin.cancel(SafetyCheckpointService.SAFETY_CHECK_NOTIFICATION_ID);
           print('Safety check notification cancelled from background');
        } else {
          print('Unknown background notification response - payload: ${response.payload}, actionId: ${response.actionId}');
        }
        print('=== BACKGROUND NOTIFICATION RESPONSE HANDLED ===');
      } catch (e, stackTrace) {
        print('Error handling background notification response: $e');
        print('Stack trace: $stackTrace');
      }
    },
  );
  
  // Create notification channel for background service
  const AndroidNotificationChannel serviceChannel = AndroidNotificationChannel(
    'emergency_alert_channel', // id
    'Emergency Alert Service', // title
    description: 'Notification channel for emergency alert background service',
    importance: Importance.low,
  );
  
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(serviceChannel);
  
  // Create notification channel for app status
  const AndroidNotificationChannel statusChannel = AndroidNotificationChannel(
    'app_status_channel', // id
    'App Status', // title
    description: 'Notification channel for app status notifications',
    importance: Importance.low,
  );
  
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(statusChannel);

  // Create notification channel for persistent SOS notification
  const AndroidNotificationChannel sosChannel = AndroidNotificationChannel(
    'sos_notification_channel',
    'SOS Notification',
    description: 'Channel for persistent SOS notification',
    importance: Importance.max,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(sosChannel);
}

class MyApp extends StatefulWidget {
  final bool hasSeenPermissions;
  
  const MyApp({super.key, required this.hasSeenPermissions});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Only initialize services if permissions have been granted
    if (widget.hasSeenPermissions) {
      _initializeAppServices();
    }
  }
  
  Future<void> _initializeAppServices() async {
    try {
      // Initialize notification channels for background service
      await _initializeNotifications();
      
      // Initialize background service
      await initializeBackgroundService();
    } catch (e) {
      print('Error initializing app services: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShakeDetectorHandler(
      child: MaterialApp(
        title: 'Emergency Alert App',
        theme: ThemeData(
          primarySwatch: Colors.red,
          useMaterial3: true,
        ),
        home: widget.hasSeenPermissions ? const HomeScreen() : const PermissionRequestScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}



// Permission Request Screen
class PermissionRequestScreen extends StatefulWidget {
  const PermissionRequestScreen({super.key});

  @override
  State<PermissionRequestScreen> createState() => _PermissionRequestScreenState();
}

class _PermissionRequestScreenState extends State<PermissionRequestScreen> {
  bool _isRequestingPermissions = false;
  
  @override
  void initState() {
    super.initState();
    
    // Check if Bluetooth is enabled before requesting permissions
    _checkBluetoothStatus();
    
    // Automatically request permissions when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestAllPermissions();
    });
  }
  
  Future<void> _checkBluetoothStatus() async {
    try {
      // Check if device supports Bluetooth
      final hasBluetooth = await Permission.bluetooth.status.isGranted || 
                           await Permission.bluetooth.status.isDenied;
      
      print('=== Bluetooth Status Check ===');
      print('Device appears to have Bluetooth support: $hasBluetooth');
      
      // Check individual Bluetooth permissions
      final bluetoothStatus = await Permission.bluetooth.status;
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;
      
      print('Bluetooth permission status: $bluetoothStatus');
      print('Bluetooth scan status: $scanStatus');
      print('Bluetooth connect status: $connectStatus');
    } catch (e) {
      print('Error checking Bluetooth status: $e');
    }
  }
  
  Future<void> _requestAllPermissions() async {
    if (_isRequestingPermissions) return;
    
    setState(() {
      _isRequestingPermissions = true;
    });
    
    try {
      // Request non-Bluetooth permissions first
      final basicPermissions = [
        Permission.microphone,
        Permission.location,
        Permission.phone,
        Permission.sms,
        Permission.notification,
        Permission.contacts,
        Permission.camera,
        Permission.ignoreBatteryOptimizations,
      ];
      
      // Request basic permissions one by one
      final Map<Permission, PermissionStatus> statuses = {};
      
      for (final permission in basicPermissions) {
        print('Requesting basic permission: $permission');
        final status = await permission.request();
        statuses[permission] = status;
        print('Basic permission $permission status: $status');
        
        // Small delay between requests to ensure dialogs are properly shown
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // Request Bluetooth permissions separately
      final bluetoothPermissions = [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ];
      
      print('=== Requesting Bluetooth permissions ===');
      for (final permission in bluetoothPermissions) {
        print('Requesting Bluetooth permission: $permission');
        
        // Check current status before requesting
        final currentStatus = await permission.status;
        print('Current status for $permission: $currentStatus');
        
        if (currentStatus.isPermanentlyDenied) {
          print('Permission $permission is permanently denied, skipping request');
          statuses[permission] = currentStatus;
          continue;
        }
        
        final status = await permission.request();
        statuses[permission] = status;
        print('Bluetooth permission $permission status: $status');
        
        // Small delay between requests
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Check if critical permissions are granted
      final criticalPermissions = [
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
      ];
      
      // Debug: Print all permission statuses
      print('=== Permission Statuses ===');
      for (final permission in criticalPermissions) {
        final status = statuses[permission];
        print('${permission.toString()}: ${status?.toString() ?? "not found"}');
      }
      
      final allCriticalGranted = criticalPermissions.every(
        (permission) => statuses[permission]?.isGranted ?? false
      );
      
      print('All critical permissions granted: $allCriticalGranted');
      
      if (allCriticalGranted) {
        // Mark that user has seen permissions
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('hasSeenPermissions', true);
        
        // Initialize app services after permissions are granted
        try {
          await _initializeNotifications();
          await initializeBackgroundService();
        } catch (e) {
          print('Error initializing services after permissions: $e');
        }
        
        // Navigate to home screen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } else {
        // Show which permissions are missing
        final missingPermissions = criticalPermissions
            .where((permission) => !(statuses[permission]?.isGranted ?? false))
            .map((permission) => _getPermissionName(permission))
            .join(', ');
            
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Required permissions missing: $missingPermissions'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error requesting permissions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingPermissions = false;
        });
      }
    }
  }
  
  String _getPermissionName(Permission permission) {
    if (permission == Permission.microphone) return 'Microphone';
    if (permission == Permission.location) return 'Location';
    if (permission == Permission.phone) return 'Phone';
    if (permission == Permission.sms) return 'SMS';
    if (permission == Permission.notification) return 'Notification';
    if (permission == Permission.contacts) return 'Contacts';
    if (permission == Permission.camera) return 'Camera';
    if (permission == Permission.bluetooth) return 'Bluetooth';
    if (permission == Permission.bluetoothScan) return 'Bluetooth Scan';
    if (permission == Permission.bluetoothConnect) return 'Bluetooth Connect';
    if (permission == Permission.ignoreBatteryOptimizations) return 'Battery Optimization';
    return 'Unknown';
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.emergency,
                size: 80,
                color: Colors.red,
              ),
              const SizedBox(height: 32),
              const Text(
                'Welcome to HerShield',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Your safety is our priority. To provide emergency features, we need the following permissions:',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildPermissionItem(
                icon: Icons.mic,
                title: 'Microphone',
                description: 'For voice commands and emergency detection',
              ),
              _buildPermissionItem(
                icon: Icons.location_on,
                title: 'Location',
                description: 'To share your location during emergencies',
              ),
              _buildPermissionItem(
                icon: Icons.phone,
                title: 'Phone',
                description: 'To make emergency calls',
              ),
              _buildPermissionItem(
                icon: Icons.sms,
                title: 'SMS',
                description: 'To send emergency messages',
              ),
              _buildPermissionItem(
                icon: Icons.notifications,
                title: 'Notifications',
                description: 'To alert you of important updates',
              ),
              _buildPermissionItem(
                icon: Icons.contacts,
                title: 'Contacts',
                description: 'To select emergency contacts',
              ),
              _buildPermissionItem(
                icon: Icons.camera_alt,
                title: 'Camera',
                description: 'To capture emergency photos from both cameras',
              ),
              _buildPermissionItem(
                icon: Icons.bluetooth,
                title: 'Bluetooth',
                description: 'To connect with smartwatches and BLE devices',
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isRequestingPermissions ? null : _requestAllPermissions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isRequestingPermissions
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Grant Permissions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isRequestingPermissions
                    ? null
                    : () async {
                        // Allow user to skip but remind them about permissions
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('hasSeenPermissions', true);
                        
                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => const HomeScreen()),
                          );
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('You can grant permissions later from app settings'),
                              backgroundColor: Colors.orange,
                              duration: Duration(seconds: 5),
                            ),
                          );
                        }
                      },
                child: const Text(
                  'Skip for now',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.red, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
