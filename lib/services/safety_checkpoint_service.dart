import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'location_service.dart';
import 'background_service.dart';
import 'connectivity_service.dart';

class SafetyCheckpointService {
  static final SafetyCheckpointService _instance = SafetyCheckpointService._internal();
  factory SafetyCheckpointService() => _instance;
  SafetyCheckpointService._internal();

  final LocationService _locationService = LocationService();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final ConnectivityService _connectivityService = ConnectivityService();
  
  Timer? _checkpointTimer;
  Timer? _safetyCheckTimer;
  DateTime? _checkpointStartTime;
  Duration? _timeLimit;
  bool _isActive = false;
  bool _safetyCheckPending = false;

  // Constants
  static const double CHECKPOINT_RADIUS_METERS = 100.0;
  static const Duration SAFETY_CHECK_TIMEOUT = Duration(minutes: 3);
  static const String SAFETY_CHECK_CHANNEL_ID = 'safety_check_channel';
  static const String SAFETY_CHECK_CHANNEL_NAME = 'Safety Check Notifications';
  static const int SAFETY_CHECK_NOTIFICATION_ID = 1001;

  // Initialize notifications
  Future<void> initializeNotifications() async {
    // Create notification channel only - notification handling is done in main.dart
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      SAFETY_CHECK_CHANNEL_ID,
      SAFETY_CHECK_CHANNEL_NAME,
      description: 'Notifications for safety check prompts',
      importance: Importance.high,
    );

    await _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  }

  // Handle notification response
  void _handleNotificationResponse(NotificationResponse response) {
    if (response.actionId == 'yes_action') {
      // User is safe - cancel the safety check
      _handleSafetyResponse(true);
    } else if (response.actionId == 'no_action') {
      // User needs help - trigger SOS immediately
      _handleSafetyResponse(false);
    }
  }

  // Handle background notification response
  @pragma('vm:entry-point')
  static void _handleBackgroundNotificationResponse(NotificationResponse response) {
    try {
      print('Background notification response received: ${response.actionId}');
      
      if (response.actionId == 'yes_action') {
        // User is safe - cancel the safety check
        SafetyCheckpointService()._handleSafetyResponseFromBackground(true);
      } else if (response.actionId == 'no_action') {
        // User needs help - trigger SOS immediately
        SafetyCheckpointService()._handleSafetyResponseFromBackground(false);
      }
    } catch (e) {
      print('Error handling background notification response: $e');
    }
  }

  // Handle safety response from background
  void _handleSafetyResponseFromBackground(bool isSafe) async {
    try {
      print('Handling safety response from background: isSafe=$isSafe');
      
      if (!isSafe) {
        // User needs help - trigger emergency directly
        print('Triggering emergency from background notification');
        await triggerEmergencyFromCheckpoint();
      }
      
      // Cancel notification
      _notifications.cancel(SAFETY_CHECK_NOTIFICATION_ID);
      print('Background safety response handled successfully');
    } catch (e) {
      print('Error handling background safety response: $e');
    }
  }

  // Start safety checkpoint
  Future<bool> startCheckpoint(Duration timeLimit) async {
    try {
      // Check location permissions
      if (!await _locationService.checkLocationPermission()) {
        throw Exception('Location permission not granted');
      }

      // Get current location and set as checkpoint
      final currentLocation = await _locationService.getCurrentLocation();
      if (currentLocation == null) {
        throw Exception('Could not get current location');
      }

      await _locationService.setCheckpoint();
      
      // Store checkpoint data
      _timeLimit = timeLimit;
      _checkpointStartTime = DateTime.now();
      _isActive = true;
      _safetyCheckPending = false;

      // Start location monitoring
      if (!_locationService.isMonitoring) {
        await _locationService.startLocationMonitoring();
      }

      // Start connectivity monitoring
      _connectivityService.startConnectivityMonitoring((hasConnection) {
        debugPrint('Connectivity changed during checkpoint: hasConnection=$hasConnection');
        // Log connectivity changes for emergency scenarios
        if (!hasConnection) {
          debugPrint('WARNING: Network connection lost during safety checkpoint');
        }
      });

      // Set up timer for checkpoint expiration
      _setupCheckpointTimer();

      debugPrint('Safety checkpoint started for ${timeLimit.inMinutes} minutes');
      return true;
    } catch (e) {
      debugPrint('Error starting safety checkpoint: $e');
      return false;
    }
  }

  // Set up checkpoint timer
  void _setupCheckpointTimer() {
    _checkpointTimer?.cancel();
    
    if (_timeLimit != null && _checkpointStartTime != null) {
      final timeRemaining = _timeLimit! - DateTime.now().difference(_checkpointStartTime!);
      
      if (timeRemaining.isNegative) {
        // Time already expired - check location immediately
        _checkLocationAndNotify();
        return;
      }

      _checkpointTimer = Timer(timeRemaining, () {
        _checkLocationAndNotify();
      });
    }
  }

  // Check location and send safety notification if needed
  void _checkLocationAndNotify() async {
    if (!_isActive) return;

    // Always send safety check notification when checkpoint expires
    // This ensures user gets notified regardless of location
    _sendSafetyCheckNotification();
    
    // Log location info for debugging
    final distance = _locationService.getDistanceFromCheckpoint();
    if (distance != null) {
      debugPrint('Safety check triggered - Distance from checkpoint: ${distance.toStringAsFixed(0)} meters');
      if (distance > CHECKPOINT_RADIUS_METERS) {
        debugPrint('User is outside checkpoint radius');
      } else {
        debugPrint('User is within checkpoint radius');
      }
    }
  }

  // Send safety check notification
  Future<void> _sendSafetyCheckNotification() async {
    if (_safetyCheckPending) return;

    _safetyCheckPending = true;

    print('=== SENDING SAFETY CHECK NOTIFICATION ===');
    print('Creating notification with actions: yes_action, no_action');

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      SAFETY_CHECK_CHANNEL_ID,
      SAFETY_CHECK_CHANNEL_NAME,
      channelDescription: 'Safety check notification',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'ticker',
      actions: [
        AndroidNotificationAction('yes_action', 'Yes, I\'m Safe'),
        AndroidNotificationAction('no_action', 'I Need Help'),
      ],
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    print('Showing notification with ID: $SAFETY_CHECK_NOTIFICATION_ID');
    await _notifications.show(
      SAFETY_CHECK_NOTIFICATION_ID,
      'Safety Check',
      'Are you safe? You have been away from your checkpoint. Tap to respond.',
      platformChannelSpecifics,
      payload: 'safety_check',
    );
    print('Notification sent successfully');

    // Set up timeout for safety check response
    _safetyCheckTimer = Timer(SAFETY_CHECK_TIMEOUT, () {
      if (_safetyCheckPending) {
        // No response received - trigger SOS
        _triggerSOS();
      }
    });

    debugPrint('Safety check notification sent');
  }

  // Handle safety response from notification
  void _handleSafetyResponse(bool isSafe) {
    _safetyCheckTimer?.cancel();
    _safetyCheckPending = false;

    if (isSafe) {
      // User is safe - acknowledge response and continue checkpoint normally
      debugPrint('User confirmed safety - checkpoint continues normally');
    } else {
      // User needs help - trigger SOS immediately
      _triggerSOS();
    }

    // Cancel notification
    _notifications.cancel(SAFETY_CHECK_NOTIFICATION_ID);
  }

  // Extend checkpoint time
  void _extendCheckpointTime(Duration extension) {
    if (_checkpointStartTime != null) {
      _checkpointStartTime = DateTime.now().subtract(_timeLimit! - extension);
      _timeLimit = extension;
      _setupCheckpointTimer();
      debugPrint('Checkpoint time extended by ${extension.inMinutes} minutes');
    }
  }

  /// Trigger SOS when user doesn't respond to safety check
  void _triggerSOS() async {
    print('User did not respond to safety check - triggering SOS');
    
    // Check connectivity status before triggering emergency
    final connectivityStatus = await _connectivityService.checkEmergencyCallingStatus();
    print('Emergency connectivity status: $connectivityStatus');
    
    if (!connectivityStatus['hasNetworkConnection']) {
      print('WARNING: No network connection detected - will attempt emergency numbers 100/108');
    }
    
    // Trigger emergency through BackgroundService (which will handle connectivity fallback)
    await triggerEmergencyFromCheckpoint();
    
    // Stop monitoring and cleanup
    stopCheckpoint();
  }

  // Stop safety checkpoint
  void stopCheckpoint() {
    _checkpointTimer?.cancel();
    _safetyCheckTimer?.cancel();
    _checkpointStartTime = null;
    _timeLimit = null;
    _isActive = false;
    _safetyCheckPending = false;
    
    _locationService.clearCheckpoint();
    _notifications.cancel(SAFETY_CHECK_NOTIFICATION_ID);
    _connectivityService.stopConnectivityMonitoring();

    debugPrint('Safety checkpoint stopped');
  }

  // Check if checkpoint is active
  bool get isActive => _isActive;

  // Get remaining time
  Duration? getRemainingTime() {
    if (_checkpointStartTime == null || _timeLimit == null || !_isActive) {
      return null;
    }

    final elapsed = DateTime.now().difference(_checkpointStartTime!);
    final remaining = _timeLimit! - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // Get checkpoint status
  Map<String, dynamic> getCheckpointStatus() {
    final remainingTime = getRemainingTime();
    final distance = _locationService.getDistanceFromCheckpoint();
    
    return {
      'isActive': _isActive,
      'remainingTime': remainingTime?.inMinutes,
      'distanceFromCheckpoint': distance,
      'safetyCheckPending': _safetyCheckPending,
      'checkpointPosition': _locationService.checkpointPosition != null 
          ? {
              'latitude': _locationService.checkpointPosition!.latitude,
              'longitude': _locationService.checkpointPosition!.longitude,
            }
          : null,
    };
  }

  // Dispose resources
  void dispose() {
    stopCheckpoint();
    _locationService.dispose();
  }
}