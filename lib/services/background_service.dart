import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:send_message/send_message.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shake/shake.dart';
import 'contacts_service.dart';
import 'connectivity_service.dart';

import 'mms_service.dart';

import 'dart:io' show Platform;

final speechToText = stt.SpeechToText();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
final ConnectivityService _connectivityService = ConnectivityService();


Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  /// IMPORTANT: Foreground service notification required for Android 12+
  /// This defines what users see while the service runs
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'emergency_alert_channel',
      initialNotificationTitle: 'Emergency Alert Service',
      initialNotificationContent: 'Monitoring for emergency phrases',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    (service).setAsForegroundService();
    
    // Show service started notification immediately
    print('Showing startup notification for Android service');
    try {
      await flutterLocalNotificationsPlugin.show(
        1000, // different ID for startup notification
        '🟢 Emergency Service Started',
        'Background monitoring is active',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'emergency_alert_channel',
            'Emergency Alert Service',
            channelDescription: 'Notification channel for emergency alert background service',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
      print('Startup notification shown successfully');
    } catch (e) {
      print('Error showing startup notification: $e');
    }
  }

  // Initialize speech to text
  await speechToText.initialize();

  // Get emergency contact and settings
  final prefs = await SharedPreferences.getInstance();
  final contacts = await ContactsService.getContacts();
  final firstContact = contacts.isNotEmpty ? contacts.first : null;
  final isServiceEnabled = prefs.getBool('service_enabled') ?? false;

  print('Background service started. Service enabled: $isServiceEnabled, Contacts: ${contacts.length}, First: ${firstContact?.name ?? "none"}');

  // Show initial status notification
  await _showAppStatusNotification(isServiceEnabled, firstContact?.name ?? 'No contacts');

  service.on('stopService').listen((event) {
    _updateAppStatusNotification(false, firstContact?.name ?? 'No contacts'); // Show inactive status
    service.stopSelf();
  });

  if (!isServiceEnabled || contacts.isEmpty) {
    // Update notification to show inactive status
    await _updateAppStatusNotification(false, firstContact?.name ?? 'No contacts');
    return;
  }

  // Start listening for voice commands
  _startVoiceMonitoring(service);
  
  // Start shake detection
  _startShakeDetection(service);
}

void _startVoiceMonitoring(ServiceInstance service) async {
  // Check microphone permission status (don't request in background)
  final micStatus = await Permission.microphone.status;
  if (!micStatus.isGranted) {
    print('Microphone permission not granted. Cannot start voice monitoring.');
    return;
  }

  // Listen to microphone continuously
  while (true) {
    try {
      if (await speechToText.initialize()) {
        speechToText.listen(
          onResult: (result) async {
            String recognizedText = result.recognizedWords.toLowerCase();

            // Check for emergency keywords
            if (_isEmergencyPhrase(recognizedText)) {
              await _triggerEmergency();
              speechToText.stop();
              // Restart listening after 2 seconds
              Future.delayed(const Duration(seconds: 2), () {
                _startVoiceMonitoring(service);
              });
            }
          },
          listenMode: stt.ListenMode.dictation,
        );

        // Listen for 30 seconds then restart
        await Future.delayed(const Duration(seconds: 30));
        speechToText.stop();
      }
    } catch (e) {
      print('Voice monitoring error: $e');
    }

    // Small delay before restarting
    await Future.delayed(const Duration(seconds: 1));
  }
}

bool _isEmergencyPhrase(String text) {
  final keywords = ['help', 'emergency', 'sos', 'danger', 'alert'];
  return keywords.any((keyword) => text.contains(keyword));
}

Future<void> _triggerEmergency() async {
  try {
    // Get contacts
    final firstContact = await ContactsService.getFirstContact();
    final allPhones = await ContactsService.getRecipientPhones();
    
    if (firstContact == null || allPhones.isEmpty) {
      print('No emergency contacts found');
      return;
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

    // Make emergency call with connectivity checking and fallback to 100/108
    try {
      // Use connectivity service to handle emergency calling with fallback logic
      final callSuccess = await _connectivityService.makeEmergencyCall(contactNumber: firstContact.phone);
      
      if (!callSuccess) {
        print('Emergency call failed - will still send SMS as fallback');
      }
    } catch (e) {
      print('Emergency call error: $e');
      // Even if call fails, continue with SMS
    }

    // Send emergency SMS message (no photos)
    String message = '🚨 EMERGENCY ALERT from Emergency App! '
        'Location: https://maps.google.com/?q=${position.latitude},${position.longitude} '
        'Lat: ${position.latitude}, Long: ${position.longitude}';
    
    await MMSService.sendEmergencySMS(
      message: message,
      recipients: allPhones,
    );

    print('Emergency triggered for ${firstContact.name} at ${firstContact.phone}');
  } catch (e) {
    print('Error triggering emergency: $e');
  }
}

Future<void> _showAppStatusNotification(bool isActive, String emergencyContactName) async {
  print('Showing app status notification: isActive=$isActive, contact=$emergencyContactName');
  
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'app_status_channel', // channel id
    'App Status', // channel name
    channelDescription: 'Shows whether the emergency alert app is active',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: false,
    ongoing: true,
    autoCancel: false,
    icon: '@mipmap/ic_launcher',
    playSound: false,
    enableVibration: false,
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  final String title = isActive ? '🟢 Emergency Alert Active' : '🔴 Emergency Alert Inactive';
  final String body = isActive 
      ? 'Listening for emergency keywords • Contact: $emergencyContactName'
      : 'Emergency monitoring is disabled';

  try {
    await flutterLocalNotificationsPlugin.show(
      999, // notification id
      title,
      body,
      platformChannelSpecifics,
    );
    print('App status notification shown successfully');
  } catch (e) {
    print('Error showing notification: $e');
  }
}

Future<void> _updateAppStatusNotification(bool isActive, String emergencyContactName) async {
  await _showAppStatusNotification(isActive, emergencyContactName);
}

void _startShakeDetection(ServiceInstance service) async {
  // Initialize shake detector for background service
  final shakeDetector = ShakeDetector.autoStart(
    onPhoneShake: (ShakeEvent event) async {
      await _triggerEmergencyFromShake();
    },
    minimumShakeCount: 3, // Require 3 shakes to trigger (more deliberate)
    shakeSlopTimeMS: 800, // Longer time between shakes
    shakeCountResetTime: 4000, // Reset after 4 seconds
    shakeThresholdGravity: 2.8, // Slightly higher threshold for background
  );
  
  print('Background shake detection started');
}

/// Show a persistent SOS notification that stays in the notification shade.
/// Tapping the notification triggers immediate call and SMS via app handlers.
Future<void> showPersistentSOSNotification() async {
  print('Showing persistent SOS notification');
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'sos_notification_channel',
    'SOS Notification',
    channelDescription: 'Persistent notification for immediate SOS actions',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: false,
    ongoing: true,
    autoCancel: false,
    icon: '@mipmap/ic_launcher',
    playSound: false,
    enableVibration: false,
  );

  const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

  try {
    await flutterLocalNotificationsPlugin.show(
      777, // SOS notification ID
      'Emergency SOS',
      'Tap here to call and send your location',
      platformDetails,
      payload: 'sos',
    );
    print('Persistent SOS notification shown');
  } catch (e) {
    print('Error showing persistent SOS notification: $e');
  }
}

/// Hide the persistent SOS notification.
Future<void> hidePersistentSOSNotification() async {
  print('Hiding persistent SOS notification');
  try {
    await flutterLocalNotificationsPlugin.cancel(777);
    print('Persistent SOS notification cancelled');
  } catch (e) {
    print('Error cancelling persistent SOS notification: $e');
  }
}

/// Public method to trigger emergency from SafetyCheckpointService
Future<void> triggerEmergencyFromCheckpoint() async {
  print('Emergency triggered from safety checkpoint');
  await _triggerEmergency();
}

Future<void> _triggerEmergencyFromShake() async {
  try {
    // Get contacts
    final firstContact = await ContactsService.getFirstContact();
    final allPhones = await ContactsService.getRecipientPhones();
    
    if (firstContact == null || allPhones.isEmpty) {
      print('No emergency contacts found for shake trigger');
      return;
    }
    
    print('Emergency shake detected for ${firstContact.name}');
    
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



    // Make emergency call with connectivity checking and fallback to 100/108
    try {
      final callSuccess = await _connectivityService.makeEmergencyCall(contactNumber: firstContact.phone);
      
      if (callSuccess) {
        print('Emergency call initiated to ${firstContact.phone} or emergency number');
      } else {
        print('Emergency call failed - no signal or permission issues');
      }
    } catch (e) {
      print('Emergency call error in background: $e');
      // Even if call fails, continue with SMS
    }

    // Send SMS with location to all contacts
    String message = '🚨 EMERGENCY SOS from Emergency App! '
        'Location: https://maps.google.com/?q=${position.latitude},${position.longitude} '
        'Lat: ${position.latitude}, Long: ${position.longitude}';

    await sendSMS(
      message: message,
      recipients: allPhones,
      sendDirect: true,
    );

    print('Emergency triggered by shake for ${firstContact.name} at ${firstContact.phone} - SMS sent to all contacts');
  } catch (e) {
    print('Error triggering emergency from shake: $e');
  }
}
