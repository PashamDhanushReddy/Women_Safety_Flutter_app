import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:send_message/send_message.dart';
import 'contacts_service.dart';

import 'mms_service.dart';
import '../widgets/overlay_floating_assistant.dart';

// Overlay entry point
@pragma("vm:entry-point")
void overlayMain() {
  print('Overlay main function called - starting overlay app');
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayFloatingAssistant(),
  ));
  print('Overlay app started successfully');
}

class OverlayService {
  static bool _isOverlayActive = false;

  static Future<void> initialize() async {
    try {
      // Set up data listener for overlay communication
      FlutterOverlayWindow.overlayListener.listen((data) {
        print('Overlay data received: $data');
        if (data == 'trigger_emergency') {
          triggerEmergency();
        }
      });
      
      // Check if overlay permission is granted
      bool hasPermission = await FlutterOverlayWindow.isPermissionGranted();
      print('Overlay permission status: $hasPermission');
      
      if (!hasPermission) {
        print('Requesting overlay permission...');
        await FlutterOverlayWindow.requestPermission();
        
        // Check again after requesting
        hasPermission = await FlutterOverlayWindow.isPermissionGranted();
        print('Overlay permission status after request: $hasPermission');
      }
      
      if (hasPermission) {
        print('Overlay permission granted - service initialized');
      } else {
        print('Overlay permission denied - service not fully initialized');
      }
    } catch (e) {
      print('Error initializing overlay service: $e');
      rethrow;
    }
  }

  static Future<void> showFloatingAssistant() async {
    print('showFloatingAssistant called - current state: $_isOverlayActive');
    if (_isOverlayActive) {
      print('Overlay already active, returning');
      return;
    }

    try {
      print('Checking overlay permission...');
      // Check if overlay permission is granted
      bool hasPermission = await FlutterOverlayWindow.isPermissionGranted();
      print('Overlay permission status: $hasPermission');
      
      if (!hasPermission) {
        print('Requesting overlay permission...');
        // Request permission - this will open system settings
        bool? permissionGranted = await FlutterOverlayWindow.requestPermission();
        print('Permission request result: $permissionGranted');
        if (permissionGranted != true) {
          print('Overlay permission denied by user');
          throw Exception('Overlay permission required to show floating assistant');
        }
      }

      print('Showing overlay with configuration...');
      // Show the overlay with proper configuration
      print('Calling FlutterOverlayWindow.showOverlay...');
      await FlutterOverlayWindow.showOverlay(
        height: 150,  // Increased size for better visibility
        width: 150,   // Increased size for better visibility
        alignment: OverlayAlignment.topRight,  // More visible position
        positionGravity: PositionGravity.right,  // Stick to right side
        enableDrag: true,
        flag: OverlayFlag.defaultFlag,  // Use default flag only
        overlayTitle: 'Emergency Assistant',
        overlayContent: 'Tap to expand emergency options',
      );
      print('FlutterOverlayWindow.showOverlay completed');
      _isOverlayActive = true;
      print('Floating assistant overlay shown successfully - state: $_isOverlayActive');
    } catch (e) {
      print('Error showing overlay: $e');
      _isOverlayActive = false;
      rethrow; // Re-throw to let the caller handle the error
    }
  }

  static Future<void> hideFloatingAssistant() async {
    print('hideFloatingAssistant called - current state: $_isOverlayActive');
    if (!_isOverlayActive) {
      print('Overlay not active, returning');
      return;
    }

    try {
      print('Closing overlay...');
      await FlutterOverlayWindow.closeOverlay();
      _isOverlayActive = false;
      print('Overlay closed successfully');
    } catch (e) {
      print('Error hiding overlay: $e');
    }
  }

  static Future<void> triggerEmergency() async {
    print('=== OVERLAY TRIGGER EMERGENCY STARTED ===');
    try {
      print('Getting emergency contacts...');
      final first = await ContactsService.getFirstContact();
      final recipients = await ContactsService.getRecipientPhones();
      print('First contact: ${first?.name} (${first?.phone})');
      print('Recipients count: ${recipients.length}');

      if (first == null || first.phone.isEmpty) {
        print('ERROR: No emergency contact set');
        return;
      }

      print('Getting current location...');
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
      print('Location obtained: ${position.latitude}, ${position.longitude}');

      // Make emergency call
      print('Attempting emergency call to ${first.phone}...');
      try {
        await FlutterPhoneDirectCaller.callNumber(first.phone);
        print('SUCCESS: Emergency call initiated to ${first.name}');
      } catch (e) {
        print('ERROR: Call failed: $e');
        print('Call failed, but continuing with SMS...');
      }

      // Send emergency SMS message (no photos)
      print('Preparing emergency SMS...');
      String message = '🚨 EMERGENCY SOS from Emergency App! '
          'Location: https://maps.google.com/?q=${position.latitude},${position.longitude} '
          'Lat: ${position.latitude}, Long: ${position.longitude}';
      
      print('Sending SMS to ${recipients.length} recipients...');
      await MMSService.sendEmergencySMS(
        message: message,
        recipients: recipients,
      );
      print('SUCCESS: SMS sent to all recipients');

      print('=== EMERGENCY TRIGGER COMPLETED SUCCESSFULLY ===');
      print('Emergency triggered via notification for ${first.name} (SMS to ${recipients.length} contacts)');
    } catch (e, stackTrace) {
      print('ERROR: Error triggering emergency from overlay: $e');
      print('Stack trace: $stackTrace');
    }
  }

  static bool get isOverlayActive => _isOverlayActive;

  static Future<Map<String, dynamic>> getOverlayStatus() async {
    try {
      bool hasPermission = await FlutterOverlayWindow.isPermissionGranted();
      return {
        'permissionGranted': hasPermission,
        'isOverlayActive': _isOverlayActive,
        'serviceRunning': true,
      };
    } catch (e) {
      return {
        'permissionGranted': false,
        'isOverlayActive': false,
        'serviceRunning': false,
        'error': e.toString(),
      };
    }
  }
}