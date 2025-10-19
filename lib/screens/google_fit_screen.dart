import 'package:flutter/material.dart';
import '../services/google_fit_service.dart';

class GoogleFitScreen extends StatefulWidget {
  const GoogleFitScreen({Key? key}) : super(key: key);

  @override
  State<GoogleFitScreen> createState() => _GoogleFitScreenState();
}

class _GoogleFitScreenState extends State<GoogleFitScreen> {
  final GoogleFitService _googleFitService = GoogleFitService();
  int _currentHeartRate = 0;
  bool _isMonitoring = false;
  String _status = 'Not connected';
  bool _hasPermissions = false;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _initializeGoogleFit();
  }

  Future<void> _initializeGoogleFit() async {
    await _googleFitService.initialize();
    await _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    setState(() {
      _isAuthenticated = _googleFitService.isAuthenticated;
    });
    if (_isAuthenticated) {
      await _checkPermissions();
    }
  }

  void _setupListeners() {
    // Listen for heart rate updates
    _googleFitService.heartRateStream.listen((heartRate) {
      if (mounted) {
        setState(() {
          _currentHeartRate = heartRate;
          _updateStatus();
        });
      }
    });
  }

  void _updateStatus() {
    if (_currentHeartRate > 120) {
      _status = '⚠️ HIGH HEART RATE: $_currentHeartRate BPM - SOS will trigger!';
    } else if (_isMonitoring) {
      _status = 'Monitoring: $_currentHeartRate BPM';
    } else {
      _status = 'Not connected';
    }
  }

  Future<void> _checkPermissions() async {
    bool hasPerms = await _googleFitService.hasPermissions();
    setState(() {
      _hasPermissions = hasPerms;
    });
  }

  Future<void> _signInWithGoogle() async {
    final success = await _googleFitService.signInWithGoogle(context);
    if (success) {
      setState(() {
        _isAuthenticated = true;
      });
      await _checkPermissions();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Signed in as ${_googleFitService.userDisplayName}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _signOutFromGoogle() async {
    final confirmed = await _googleFitService.showSignOutDialog(context);
    if (confirmed) {
      await _googleFitService.signOutFromGoogle();
      setState(() {
        _isAuthenticated = false;
        _hasPermissions = false;
        _isMonitoring = false;
        _currentHeartRate = 0;
        _status = 'Not connected';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signed out successfully'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _requestPermissions() async {
    bool granted = await _googleFitService.requestPermissions();
    setState(() {
      _hasPermissions = granted;
    });

    if (granted) {
      _startMonitoring();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google Fit permissions denied. Please grant access in settings.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startMonitoring() async {
    await _googleFitService.startMonitoring();
    setState(() {
      _isMonitoring = true;
      _updateStatus();
    });
  }

  void _stopMonitoring() {
    _googleFitService.stopMonitoring();
    setState(() {
      _isMonitoring = false;
      _status = 'Not connected';
    });
  }

  @override
  void dispose() {
    _googleFitService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Fit Heart Rate Monitor'),
        backgroundColor: Colors.blue,
        actions: [
          if (_isAuthenticated)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _signOutFromGoogle,
              tooltip: 'Sign Out',
            )
          else
            IconButton(
              icon: const Icon(Icons.login),
              onPressed: _signInWithGoogle,
              tooltip: 'Sign In with Google',
            ),
          if (_hasPermissions)
            IconButton(
              icon: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow),
              onPressed: _isMonitoring ? _stopMonitoring : _startMonitoring,
              tooltip: _isMonitoring ? 'Stop monitoring' : 'Start monitoring',
            ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Heart Rate Display
            Icon(
              Icons.favorite,
              size: 100,
              color: _currentHeartRate > 120 ? Colors.red : Colors.pink,
            ),
            const SizedBox(height: 20),
            Text(
              '$_currentHeartRate BPM',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: _currentHeartRate > 120 ? Colors.red : Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            


            // Status Text
            Text(
              _status,
              style: TextStyle(
                fontSize: 16,
                color: _currentHeartRate > 120 ? Colors.red : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 30),

            // SOS Alert Box
            if (_currentHeartRate > 120)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red, width: 2),
                ),
                child: const Text(
                  '🚨 SOS ALERT WILL TRIGGER!\nHeart rate exceeded 120 BPM threshold',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 30),

            // User Info (if authenticated)
            if (_isAuthenticated)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.person, size: 32, color: Colors.blue),
                      const SizedBox(height: 8),
                      Text(
                        _googleFitService.userDisplayName ?? 'Unknown User',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _googleFitService.userEmail ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Authentication/Permission/Action Buttons
            if (!_isAuthenticated)
              ElevatedButton.icon(
                onPressed: _signInWithGoogle,
                icon: const Icon(Icons.login),
                label: const Text('Sign In with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              )
            else if (!_hasPermissions)
              ElevatedButton.icon(
                onPressed: _requestPermissions,
                icon: const Icon(Icons.security),
                label: const Text('Grant Google Fit Permissions'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              )
            else if (!_isMonitoring)
              ElevatedButton.icon(
                onPressed: _startMonitoring,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Heart Rate Monitoring'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _stopMonitoring,
                icon: const Icon(Icons.stop),
                label: const Text('Stop Monitoring'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),

            const SizedBox(height: 20),

            // Info Text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _hasPermissions 
                    ? 'Connected to Google Fit. Monitoring your heart rate.'
                    : 'This app needs permission to access your Google Fit data to monitor heart rate.',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 10),

            // Threshold Info
            const Text(
              'SOS will trigger automatically when heart rate > 120 BPM',
              style: TextStyle(fontSize: 12, color: Colors.orange),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}