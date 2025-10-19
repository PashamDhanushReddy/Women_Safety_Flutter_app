import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:send_message/send_message.dart';

class FloatingAssistant extends StatefulWidget {
  const FloatingAssistant({super.key});

  @override
  State<FloatingAssistant> createState() => _FloatingAssistantState();
}

class _FloatingAssistantState extends State<FloatingAssistant> {
  bool _isExpanded = false;
  Offset _position = const Offset(50, 100); // Initial position
  String? emergencyPhone;
  String? emergencyName;

  @override
  void initState() {
    super.initState();
    _loadEmergencyContact();
  }

  Future<void> _loadEmergencyContact() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      emergencyPhone = prefs.getString('emergency_phone');
      emergencyName = prefs.getString('emergency_name');
    });
  }

  Future<void> _triggerEmergency() async {
    if (emergencyPhone == null || emergencyPhone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add an emergency contact first')),
      );
      return;
    }

    try {
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

      // Make emergency call
      try {
        await FlutterPhoneDirectCaller.callNumber(emergencyPhone!);
      } catch (e) {
        print('Call failed: $e');
      }

      // Send SMS with location
      String message = '🚨 EMERGENCY SOS from Emergency App! '
          'Location: https://maps.google.com/?q=${position.latitude},${position.longitude} '
          'Lat: ${position.latitude}, Long: ${position.longitude}';

      await sendSMS(
        message: message,
        recipients: [emergencyPhone!],
        sendDirect: true,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Emergency call and SMS sent to $emergencyName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending emergency: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main floating button
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _position += details.delta;
              });
            },
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isExpanded ? 200 : 60,
              height: _isExpanded ? 120 : 60,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(_isExpanded ? 16 : 30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _isExpanded
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.emergency,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _triggerEmergency,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'CALL',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Center(
                      child: Icon(
                        Icons.emergency,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}