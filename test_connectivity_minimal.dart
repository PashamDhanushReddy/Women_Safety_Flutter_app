import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() {
  runApp(const MinimalConnectivityTestApp());
}

class MinimalConnectivityTestApp extends StatelessWidget {
  const MinimalConnectivityTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minimal Connectivity Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MinimalConnectivityTestScreen(),
    );
  }
}

class MinimalConnectivityTestScreen extends StatefulWidget {
  const MinimalConnectivityTestScreen({super.key});

  @override
  State<MinimalConnectivityTestScreen> createState() => _MinimalConnectivityTestScreenState();
}

class _MinimalConnectivityTestScreenState extends State<MinimalConnectivityTestScreen> {
  final Connectivity _connectivity = Connectivity();
  bool _hasConnection = true;
  String _statusMessage = 'Checking connectivity...';

  @override
  void initState() {
    super.initState();
    _initializeConnectivity();
  }

  void _initializeConnectivity() async {
    // Check initial connectivity
    final results = await _connectivity.checkConnectivity();
    final hasConnection = results.isNotEmpty && !results.contains(ConnectivityResult.none);
    
    setState(() {
      _hasConnection = hasConnection;
      _statusMessage = hasConnection 
          ? 'Network connection available' 
          : 'No network connection detected';
    });

    // Listen for connectivity changes
    _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection = results.isNotEmpty && !results.contains(ConnectivityResult.none);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minimal Connectivity Test'),
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