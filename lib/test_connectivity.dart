import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'services/connectivity_service.dart';

void main() {
  runApp(const ConnectivityTestApp());
}

class ConnectivityTestApp extends StatelessWidget {
  const ConnectivityTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connectivity Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const ConnectivityTestScreen(),
    );
  }
}

class ConnectivityTestScreen extends StatefulWidget {
  const ConnectivityTestScreen({super.key});

  @override
  State<ConnectivityTestScreen> createState() => _ConnectivityTestScreenState();
}

class _ConnectivityTestScreenState extends State<ConnectivityTestScreen> {
  final ConnectivityService _connectivityService = ConnectivityService();
  bool _hasConnection = true;
  String _statusMessage = 'Checking connectivity...';

  @override
  void initState() {
    super.initState();
    _initializeConnectivity();
  }

  void _initializeConnectivity() async {
    // Check initial connectivity
    final hasConnection = await _connectivityService.checkConnectivity();
    setState(() {
      _hasConnection = hasConnection;
      _statusMessage = hasConnection 
          ? 'Network connection available' 
          : 'No network connection detected';
    });

    // Listen for connectivity changes
    _connectivityService.onConnectivityChanged.listen((hasConnection) {
      if (mounted) {
        setState(() {
          _hasConnection = hasConnection;
          _statusMessage = hasConnection 
              ? 'Network connection restored' 
              : 'Network connection lost';
        });
      }
    });
  }

  void _testEmergencyCall() async {
    try {
      // Test emergency call with fallback
      await _connectivityService.makeEmergencyCall('1234567890');
      setState(() {
        _statusMessage = 'Emergency call initiated (test mode)';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Emergency call test failed: $e';
      });
    }
  }

  @override
  void dispose() {
    _connectivityService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connectivity Test'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _hasConnection ? Icons.wifi : Icons.wifi_off,
              size: 64,
              color: _hasConnection ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 16),
            Text(
              _hasConnection ? 'Connected' : 'No Connection',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _hasConnection ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _testEmergencyCall,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text(
                'Test Emergency Call',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    'Emergency Fallback Info:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• With network: Calls go to primary contact\n'
                    '• Without network:'
                    '• Police: 100\n'
                    '• Ambulance: 108\n'
                    '• Fire: 101',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}