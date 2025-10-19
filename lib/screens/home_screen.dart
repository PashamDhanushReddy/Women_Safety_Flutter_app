import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:send_message/send_message.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../services/background_service.dart';
import '../services/contacts_service.dart';
import '../services/safety_checkpoint_service.dart';
import '../services/location_service.dart';
import '../services/google_fit_service.dart';
import '../services/connectivity_service.dart';
import 'google_fit_screen.dart';
import 'ble_screen.dart';

import '../services/mms_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isMonitoring = false;
  String? emergencyPhone;
  String? emergencyName;
  bool isServiceRunning = false;

  // Safety checkpoint state
  final SafetyCheckpointService _checkpointService = SafetyCheckpointService();
  bool _isCheckpointActive = false;
  Duration? _checkpointRemainingTime;
  Timer? _checkpointUpdateTimer;
  int _selectedTimeLimit = 30; // Default 30 minutes

  // Connectivity state
  final ConnectivityService _connectivityService = ConnectivityService();
  bool _hasNetworkConnection = true;
  bool _isEmergencyCallFallback = false;

  // Signal strength state
  int _signalBars = 0;
  String _signalQuality = 'Unknown';
  int _signalDbm = 0;
  String _networkType = 'Unknown';
  bool _isRoaming = false;
  Timer? _signalUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadEmergencyContact();
    _checkServiceStatus();
    _initializeCheckpointService();
    _initializeConnectivityMonitoring();
    _initializeSignalStrengthMonitoring();
  }

  @override
  void dispose() {
    _checkpointUpdateTimer?.cancel();
    _signalUpdateTimer?.cancel();
    _checkpointService.dispose();
    _connectivityService.dispose();
    super.dispose();
  }

  void _initializeCheckpointService() async {
    await _checkpointService.initializeNotifications();
    _startCheckpointTimer();
  }

  void _initializeConnectivityMonitoring() {
    // Listen for connectivity changes
    _connectivityService.startConnectivityMonitoring((hasConnection) {
      if (mounted) {
        setState(() {
          _hasNetworkConnection = hasConnection;
        });

        if (!hasConnection) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '⚠️ No network connection detected.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    });

    // Check initial connectivity
    _checkInitialConnectivity();
  }

  void _checkInitialConnectivity() async {
    final hasConnection = await _connectivityService.hasNetworkConnection();
    if (mounted) {
      setState(() {
        _hasNetworkConnection = hasConnection;
      });
    }
  }

  void _initializeSignalStrengthMonitoring() {
    // Update signal strength every 5 seconds
    _signalUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateSignalStrength();
    });

    // Get initial signal strength
    _updateSignalStrength();
  }

  void _updateSignalStrength() async {
    try {
      final signalInfo = await _connectivityService.getMobileSignalInfo();

      if (mounted) {
        setState(() {
          _signalBars = signalInfo['signalBars'] ?? 0;
          _signalQuality = signalInfo['signalQuality'] ?? 'Unknown';
          _signalDbm = signalInfo['signalDbm'] ?? 0;
          _networkType = signalInfo['networkType'] ?? 'Unknown';
          _isRoaming = signalInfo['isRoaming'] ?? false;
        });
      }
    } catch (e) {
      print('Error updating signal strength: $e');
      // Set to no signal on error
      if (mounted) {
        setState(() {
          _signalBars = -1;
          _signalQuality = 'No Signal';
          _signalDbm = 0;
          _networkType = 'Unknown';
          _isRoaming = false;
        });
      }
    }
  }

  void _startCheckpointTimer() {
    _checkpointUpdateTimer?.cancel();
    _checkpointUpdateTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _isCheckpointActive = _checkpointService.isActive;
          _checkpointRemainingTime = _checkpointService.getRemainingTime();
        });
      }
    });
  }

  Future<void> _loadEmergencyContact() async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await ContactsService.getContacts();

    setState(() {
      // Keep emergencyPhone and emergencyName for backward compatibility
      emergencyPhone = prefs.getString('emergency_phone');
      emergencyName = prefs.getString('emergency_name');

      // If we have contacts in the new system but not in the old one, migrate them
      if (contacts.isNotEmpty && emergencyPhone == null) {
        final firstContact = contacts.first;
        emergencyPhone = firstContact.phone;
        emergencyName = firstContact.name;
      }

      isMonitoring = prefs.getBool('service_enabled') ?? false;
    });
  }

  Future<void> _checkServiceStatus() async {
    final service = FlutterBackgroundService();
    isServiceRunning = await FlutterBackgroundService().isRunning();
    setState(() {});
  }

  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.microphone,
      Permission.location,
      Permission.phone,
      Permission.sms,
      Permission.notification,
      if (!isMonitoring) Permission.ignoreBatteryOptimizations,
    ];

    final statuses = await permissions.request();

    if (statuses[Permission.microphone]!.isGranted &&
        statuses[Permission.location]!.isGranted &&
        statuses[Permission.phone]!.isGranted &&
        statuses[Permission.sms]!.isGranted &&
        statuses[Permission.notification]!.isGranted) {
      return;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Some permissions were denied. Please grant all permissions for the app to work properly.')),
      );
    }
  }

  Future<void> _startMonitoring() async {
    final first = await ContactsService.getFirstContact();

    if (first == null || first.phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add an emergency contact first')),
      );
      return;
    }

    await _requestPermissions();

    final service = FlutterBackgroundService();
    bool isRunning = await FlutterBackgroundService().isRunning();

    if (!isRunning) {
      service.startService();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('service_enabled', true);

    setState(() {
      isMonitoring = true;
      isServiceRunning = true;
    });

    // Show persistent SOS notification when monitoring starts
    await showPersistentSOSNotification();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('Emergency monitoring started. Listening for keywords...')),
    );
  }

  Future<void> _stopMonitoring() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('service_enabled', false);

    setState(() {
      isMonitoring = false;
      isServiceRunning = false;
    });

    // Hide persistent SOS notification when monitoring stops
    await hidePersistentSOSNotification();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Emergency monitoring stopped')),
    );
  }

  Future<void> _startSafetyCheckpoint() async {
    // Use minutes for all time limits
    final duration = Duration(minutes: _selectedTimeLimit);

    final hasPermission = await _checkpointService.startCheckpoint(duration);

    if (hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ Safety checkpoint started for $_selectedTimeLimit minutes'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '❌ Failed to start checkpoint. Please check location permissions.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _stopSafetyCheckpoint() {
    _checkpointService.stopCheckpoint();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Safety checkpoint stopped'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0 min';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  double _getCheckpointProgress() {
    if (!_isCheckpointActive || _checkpointRemainingTime == null) return 0.0;
    final totalTime = Duration(minutes: _selectedTimeLimit);
    final progress =
        1.0 - (_checkpointRemainingTime!.inSeconds / totalTime.inSeconds);
    return progress.clamp(0.0, 1.0);
  }

  Future<void> _triggerSOS() async {
    final first = await ContactsService.getFirstContact();
    final recipients = await ContactsService.getRecipientPhones();

    if (first == null || first.phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add an emergency contact first'),
          backgroundColor: Colors.red,
        ),
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

      // Use connectivity service for emergency call with fallback
      await _connectivityService.makeEmergencyCall(contactNumber: first.phone);

      // Send automatic emergency SMS message to all contacts (no photos)
      String message = '🚨 EMERGENCY SOS from Emergency App! '
          'Location: https://maps.google.com/?q=${position.latitude},${position.longitude} '
          'Lat: ${position.latitude}, Long: ${position.longitude}';

      await MMSService.sendEmergencySMS(
        message: message,
        recipients: recipients,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '🚨 Emergency call to ${first.name} and AUTOMATIC message sent to ${recipients.length} contacts'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending SOS: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _addEmergencyContact() async {
    // Request contacts permission first
    final contactsPermission = await Permission.contacts.request();
    if (!contactsPermission.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contacts permission is required to select contacts'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Get all contacts first
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
      );

      if (contacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No contacts found on device'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Show contact selection dialog with search
      final selectedContact = await showDialog<Contact>(
        context: context,
        builder: (BuildContext context) {
          return _ContactSelectionDialog(contacts: contacts);
        },
      );

      if (selectedContact == null) {
        // User cancelled the selection
        return;
      }

      // Extract phone number from the selected contact
      final phoneNumber = selectedContact.phones.first.number;

      if (phoneNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected contact has no phone number'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Clean up the phone number (remove spaces, dashes, etc.)
      final cleanedPhoneNumber =
          phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');

      // Add contact using ContactsService
      await ContactsService.addContact(
        selectedContact.displayName,
        cleanedPhoneNumber,
      );

      // Update UI state
      setState(() {
        // Keep emergencyPhone and emergencyName for backward compatibility
        emergencyPhone = cleanedPhoneNumber;
        emergencyName = selectedContact.displayName;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Emergency contact ${selectedContact.displayName} added successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting contact: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _viewAllContacts() async {
    final contacts = await ContactsService.getContacts();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency Contacts'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (contacts.isEmpty)
                const Text('No emergency contacts added yet.')
              else
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      final isPrimary = index == 0;
                      return ListTile(
                        title: Row(
                          children: [
                            Expanded(child: Text(contact.name)),
                            if (isPrimary)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'PRIMARY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(contact.phone),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await ContactsService.removeContactByPhone(
                                contact.phone);
                            Navigator.pop(context);
                            _loadEmergencyContact(); // Refresh the contact list
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Contact removed successfully')),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _addEmergencyContact();
                },
                child: const Text('Add New Contact'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Alert App'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.watch),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BLEScreen(),
                ),
              );
            },
            tooltip: 'Smartwatch Connection',
          ),
          IconButton(
            icon: const Icon(Icons.monitor_heart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GoogleFitScreen(),
                ),
              );
            },
            tooltip: 'Health Monitoring',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [


                // Safety Checkpoint Section
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isCheckpointActive
                                  ? Icons.location_on
                                  : Icons.location_off,
                              color: _isCheckpointActive
                                  ? Colors.green
                                  : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Safety Checkpoint',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _isCheckpointActive
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                            const Spacer(),
                            if (_isCheckpointActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green[100],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_checkpointRemainingTime?.inMinutes ?? 0} min left',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (!_isCheckpointActive) ...[
                          const Text(
                            'Set a time limit and your current location will be saved as a checkpoint. If you don\'t return within the radius, we\'ll check if you\'re safe.',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Text('Time Limit:',
                                  style: TextStyle(fontSize: 16)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: _selectedTimeLimit,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                  items:
                                      [1, 30, 45, 60, 90, 120].map((int value) {
                                    return DropdownMenuItem<int>(
                                      value: value,
                                      child: Text(value == 1
                                          ? '1 minute (Test)'
                                          : '$value minutes'),
                                    );
                                  }).toList(),
                                  onChanged: (int? newValue) {
                                    setState(() {
                                      _selectedTimeLimit = newValue ?? 30;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _startSafetyCheckpoint,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.play_arrow, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'Start Safety Checkpoint',
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Checkpoint Active',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green[700],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Time remaining: ${_formatDuration(_checkpointRemainingTime)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _stopSafetyCheckpoint,
                                icon: const Icon(Icons.stop, color: Colors.red),
                                tooltip: 'Stop Checkpoint',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _getCheckpointProgress(),
                            backgroundColor: Colors.grey[200],
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.green),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // SOS Button - Made Even Bigger
                SizedBox(
                  width: double.infinity,
                  height: 220, // Increased height even more
                  child: ElevatedButton(
                    onPressed: _triggerSOS,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25), // More rounded
                      ),
                      elevation: 16, // Higher elevation for prominence
                      padding: const EdgeInsets.all(20), // More padding
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.emergency,
                          size: 80, // Much larger icon
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'EMERGENCY SOS',
                          style: const TextStyle(
                            fontSize: 32, // Much larger text
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap to send emergency alert',
                          style: TextStyle(
                            fontSize: 16, // Larger subtitle
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Emergency contacts display
                FutureBuilder<List<EmergencyContact>>(
                  future: ContactsService.getContacts(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                      final contacts = snapshot.data!;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Emergency Contacts',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...contacts.asMap().entries.map((entry) {
                                final index = entry.key;
                                final contact = entry.value;
                                final isPrimary = index == 0;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              contact.name,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: isPrimary
                                                    ? Colors.blue
                                                    : Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              contact.phone,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: isPrimary
                                                    ? Colors.blue[600]
                                                    : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isPrimary)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.blue[100],
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            'PRIMARY',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue[700],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              const SizedBox(height: 8),
                              Text(
                                '• Call goes to PRIMARY contact only\n• SMS goes to ALL contacts',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else if (snapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Error loading contacts: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  },
                ),
                const SizedBox(height: 16),
                // Contact management buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _addEmergencyContact,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Add Contact',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    if (emergencyName != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _viewAllContacts,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'View All',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                // Overlay assistant removed per request
                const SizedBox.shrink(),
                const SizedBox(height: 24),
                // SOS notification appears automatically when monitoring starts
                const SizedBox(height: 24),
                // Start/Stop button
                ElevatedButton(
                  onPressed: isMonitoring ? _stopMonitoring : _startMonitoring,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isMonitoring ? Colors.red : Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    isMonitoring ? 'Stop Monitoring' : 'Start Monitoring',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Information section
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How It Works',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '1. Add an emergency contact\n'
                          '2. Tap "Start Monitoring" for voice activation\n'
                          '3. Use the red SOS button for immediate emergency\n'
                          '4. The app will listen for keywords: "help", "emergency", "sos", "danger", "alert"\n'
                          '5. When triggered (voice or SOS button), the app will:\n'
                          '   • Make an emergency call\n'
                          '   • Send SMS with your location\n'
                          '6. Works even when phone is locked or app is in background',
                          style: TextStyle(fontSize: 13, height: 1.6),
                        ),
                      ],
                    ),
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

class _ContactSelectionDialog extends StatefulWidget {
  final List<dynamic> contacts;

  const _ContactSelectionDialog({required this.contacts});

  @override
  State<_ContactSelectionDialog> createState() =>
      _ContactSelectionDialogState();
}

class _ContactSelectionDialogState extends State<_ContactSelectionDialog> {
  String searchQuery = '';

  List<dynamic> get filteredContacts {
    if (searchQuery.isEmpty) {
      return widget.contacts;
    }
    return widget.contacts.where((contact) {
      final name = contact.displayName.toLowerCase();
      final phone = contact.phones.isNotEmpty
          ? contact.phones.first.number.replaceAll(RegExp(r'[\s\-\(\)]'), '')
          : '';
      final query = searchQuery.toLowerCase();

      return name.contains(query) || phone.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Emergency Contact'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            // Search field
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or phone number...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),
            // Contact list
            Expanded(
              child: filteredContacts.isEmpty
                  ? Center(
                      child: Text(
                        searchQuery.isEmpty
                            ? 'No contacts with phone numbers found'
                            : 'No contacts match your search',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredContacts.length,
                      itemBuilder: (context, index) {
                        final contact = filteredContacts[index];
                        final phoneNumber = contact.phones.isNotEmpty
                            ? contact.phones.first.number
                            : null;

                        return ListTile(
                          leading: contact.photo != null
                              ? CircleAvatar(
                                  backgroundImage: MemoryImage(contact.photo!),
                                )
                              : const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                          title: Text(contact.displayName),
                          subtitle: Text(phoneNumber ?? 'No phone number'),
                          enabled: phoneNumber != null,
                          onTap: phoneNumber != null
                              ? () => Navigator.pop(context, contact)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
