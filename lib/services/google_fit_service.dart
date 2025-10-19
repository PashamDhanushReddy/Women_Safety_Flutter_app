import 'dart:async';
import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'background_service.dart' as bg_service;
import 'package:flutter/foundation.dart';
import 'google_signin_service.dart';

// Google Fit integration using the health package
// This provides access to health data from Google Fit and Apple Health

class GoogleFitService {
  static final GoogleFitService _instance = GoogleFitService._internal();
  factory GoogleFitService() => _instance;
  GoogleFitService._internal();

  final Health _health = Health();
  final GoogleSignInService _googleSignInService = GoogleSignInService();
  Timer? _monitoringTimer;
  int _currentHeartRate = 0;
  double _currentStress = 0.0;
  bool _isMonitoring = false;
  bool _sosTriggeredForHighHR = false;
  bool _isAuthenticated = false;
  
  // Heart rate threshold for SOS (120 BPM)
  static const int HEART_RATE_SOS_THRESHOLD = 120;
  static const Duration HEART_RATE_CHECK_INTERVAL = Duration(seconds: 30);

  // Stream controllers
  final StreamController<int> _heartRateController = StreamController<int>.broadcast();
  final StreamController<double> _stressController = StreamController<double>.broadcast();

  // Streams
  Stream<int> get heartRateStream => _heartRateController.stream;
  Stream<double> get stressStream => _stressController.stream;
  
  int get currentHeartRate => _currentHeartRate;
  double get currentStress => _currentStress;
  bool get isMonitoring => _isMonitoring;
  bool get isAuthenticated => _isAuthenticated;
  String? get userEmail => _googleSignInService.userEmail;
  String? get userDisplayName => _googleSignInService.userDisplayName;

  // Request permissions for Google Fit
  Future<bool> requestPermissions() async {
    try {
      // First check if user is authenticated with Google
      if (!_googleSignInService.isSignedIn) {
        debugPrint('❌ User not authenticated with Google');
        return false;
      }

      // Define the types of data we want to access
      final types = [
        HealthDataType.HEART_RATE,
      ];

      // Request permissions
      bool requested = await _health.requestAuthorization(types);
      debugPrint('🩺 Google Fit permissions requested: $requested');
      return requested;
    } catch (e) {
      debugPrint('❌ Error requesting Google Fit permissions: $e');
      return false;
    }
  }

  // Auto-request permissions on first launch
  Future<bool> autoRequestPermissions() async {
    try {
      bool hasPerms = await hasPermissions();
      if (!hasPerms) {
        debugPrint('🩺 Auto-requesting Google Fit permissions...');
        return await requestPermissions();
      }
      return true;
    } catch (e) {
      debugPrint('❌ Error auto-requesting Google Fit permissions: $e');
      return false;
    }
  }

  // Check if we have permissions
  Future<bool> hasPermissions() async {
    try {
      final types = [
        HealthDataType.HEART_RATE,
      ];

      bool? hasPermissions = await _health.hasPermissions(types);
      debugPrint('🩺 Google Fit permissions status: $hasPermissions');
      return hasPermissions ?? false;
    } catch (e) {
      debugPrint('❌ Error checking Google Fit permissions: $e');
      return false;
    }
  }

  // Start monitoring heart rate and stress
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    try {
      // Check permissions first
      bool hasPerms = await hasPermissions();
      if (!hasPerms) {
        hasPerms = await requestPermissions();
        if (!hasPerms) {
          print('❌ Google Fit permissions denied');
          return;
        }
      }

      _isMonitoring = true;
      debugPrint('🩺 Starting Google Fit monitoring...');

      // Start periodic monitoring
      _startHeartRateMonitoring();
      
      // Get initial readings
      await _fetchCurrentData();

    } catch (e) {
      print('❌ Error starting Google Fit monitoring: $e');
      _isMonitoring = false;
    }
  }

  // Stop monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    debugPrint('🩺 Stopped Google Fit monitoring');
  }

  // Start heart rate monitoring timer
  void _startHeartRateMonitoring() {
    _monitoringTimer = Timer.periodic(HEART_RATE_CHECK_INTERVAL, (timer) async {
      if (!_isMonitoring) {
        timer.cancel();
        return;
      }
      
      await _fetchCurrentData();
      _checkHeartRateForSOS();
    });
  }

  // Fetch current heart rate and stress data
  Future<void> _fetchCurrentData() async {
    try {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));

      // Get heart rate data
      List<HealthDataPoint> heartRateData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: yesterday,
        endTime: now,
      );

      if (heartRateData.isNotEmpty) {
        // Get the most recent heart rate reading
        heartRateData.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
        final latestHeartRate = heartRateData.first;
        // Parse the numeric value from HealthValue
        final heartRateValue = _parseNumericValue(latestHeartRate.value);
        if (heartRateValue != null) {
          _currentHeartRate = heartRateValue.toInt();
          _heartRateController.add(_currentHeartRate);
          debugPrint('❤️ Current heart rate: $_currentHeartRate BPM');
        }
      }

      // Note: STRESS data type is not available in the health package
      // We'll skip stress monitoring for now
      debugPrint('ℹ️ Stress monitoring not available in current health package version');

    } catch (e) {
      debugPrint('❌ Error fetching Google Fit data: $e');
    }
  }

  // Check heart rate for SOS trigger
  void _checkHeartRateForSOS() {
    if (_currentHeartRate > HEART_RATE_SOS_THRESHOLD && !_sosTriggeredForHighHR) {
      debugPrint('🚨 High heart rate detected: $_currentHeartRate BPM');
      _triggerSOSForHighHeartRate();
      _sosTriggeredForHighHR = true;
    } else if (_currentHeartRate <= HEART_RATE_SOS_THRESHOLD) {
      // Reset the flag when heart rate returns to normal
      _sosTriggeredForHighHR = false;
    }
  }

  // Trigger SOS for high heart rate
  Future<void> _triggerSOSForHighHeartRate() async {
    try {
      debugPrint('🚨 Triggering SOS for high heart rate: $_currentHeartRate BPM');
      await bg_service.triggerEmergencyFromCheckpoint();
    } catch (e) {
      debugPrint('❌ Error triggering SOS for high heart rate: $e');
    }
  }

  // Get methods for current values
  int getHeartRate() => _currentHeartRate;
  double getStress() => _currentStress;
  
  // Google Sign-In authentication methods
  Future<bool> signInWithGoogle(BuildContext context) async {
    try {
      final success = await _googleSignInService.signIn();
      if (success) {
        _isAuthenticated = true;
        debugPrint('🔐 Google Sign-In successful: ${userDisplayName} (${userEmail})');
        return true;
      } else {
        debugPrint('🔐 Google Sign-In failed or cancelled');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Google Sign-In error: $e');
      return false;
    }
  }

  Future<void> signOutFromGoogle() async {
    try {
      await _googleSignInService.signOut();
      _isAuthenticated = false;
      stopMonitoring();
      debugPrint('🔐 Google Sign-Out successful');
    } catch (e) {
      debugPrint('❌ Google Sign-Out error: $e');
    }
  }

  Future<bool> showSignInDialog(BuildContext context) async {
    return await _googleSignInService.showSignInDialog(context);
  }

  Future<bool> showSignOutDialog(BuildContext context) async {
    return await _googleSignInService.showSignOutDialog(context);
  }

  // Initialize Google Fit service with authentication
  Future<void> initialize() async {
    await _googleSignInService.initialize();
    _isAuthenticated = _googleSignInService.isSignedIn;
    debugPrint('🩺 Google Fit service initialized. Authenticated: $_isAuthenticated');
  }

  // Update heart rate threshold
  void updateHeartRateThreshold(int newThreshold) {
    // This would require changing from constant to variable
    debugPrint('🩺 Heart rate threshold update requested: $newThreshold');
  }

  // Helper method to parse numeric value from HealthValue
  double? _parseNumericValue(HealthValue value) {
    try {
      if (value is NumericHealthValue) {
        return value.numericValue.toDouble();
      }
      // Try to parse as string if it's a string representation
      return double.tryParse(value.toString());
    } catch (e) {
      debugPrint('❌ Error parsing health value: $e');
      return null;
    }
  }

  // Dispose
  void dispose() {
    stopMonitoring();
    _heartRateController.close();
    _stressController.close();
  }
}