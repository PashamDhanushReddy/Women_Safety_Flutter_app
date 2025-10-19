import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;
  Position? _checkpointPosition;
  
  // Stream for location updates
  final StreamController<Position> _locationStreamController = StreamController<Position>.broadcast();
  Stream<Position> get locationStream => _locationStreamController.stream;

  // Check if location services are enabled and permissions granted
  Future<bool> checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    // Check location permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      if (!await checkLocationPermission()) {
        return null;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      _locationStreamController.add(_currentPosition!);
      return _currentPosition;
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }

  // Set checkpoint location
  Future<void> setCheckpoint() async {
    _checkpointPosition = await getCurrentLocation();
  }

  // Get checkpoint position
  Position? get checkpointPosition => _checkpointPosition;

  // Calculate distance between two positions in meters
  double calculateDistance(Position pos1, Position pos2) {
    const earthRadius = 6371000; // Earth radius in meters
    
    final lat1 = pos1.latitude * math.pi / 180;
    final lat2 = pos2.latitude * math.pi / 180;
    final deltaLat = (pos2.latitude - pos1.latitude) * math.pi / 180;
    final deltaLon = (pos2.longitude - pos1.longitude) * math.pi / 180;

    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
        math.sin(deltaLon / 2) * math.sin(deltaLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  // Check if current position is within specified radius of checkpoint
  bool isWithinCheckpointRadius(double radiusMeters) {
    if (_currentPosition == null || _checkpointPosition == null) {
      return false;
    }

    final distance = calculateDistance(_currentPosition!, _checkpointPosition!);
    return distance <= radiusMeters;
  }

  // Get current distance from checkpoint
  double? getDistanceFromCheckpoint() {
    if (_currentPosition == null || _checkpointPosition == null) {
      return null;
    }
    return calculateDistance(_currentPosition!, _checkpointPosition!);
  }

  // Start continuous location monitoring
  Future<void> startLocationMonitoring() async {
    if (!await checkLocationPermission()) {
      throw Exception('Location permission not granted');
    }

    if (_positionStreamSubscription != null) {
      await stopLocationMonitoring();
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update when device moves 10 meters
      timeLimit: Duration(seconds: 30), // Update every 30 seconds max
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _currentPosition = position;
      _locationStreamController.add(position);
    });
  }

  // Stop location monitoring
  Future<void> stopLocationMonitoring() async {
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }

  // Clear checkpoint
  void clearCheckpoint() {
    _checkpointPosition = null;
  }

  // Dispose resources
  void dispose() {
    _positionStreamSubscription?.cancel();
    _locationStreamController.close();
  }

  // Get current position (cached)
  Position? get currentPosition => _currentPosition;

  // Check if location monitoring is active
  bool get isMonitoring => _positionStreamSubscription != null;
}