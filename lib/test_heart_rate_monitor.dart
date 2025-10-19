import 'package:flutter/material.dart';
import 'services/ble_service.dart';

class HeartRateMonitorTest extends StatefulWidget {
  const HeartRateMonitorTest({Key? key}) : super(key: key);

  @override
  State<HeartRateMonitorTest> createState() => _HeartRateMonitorTestState();
}

class _HeartRateMonitorTestState extends State<HeartRateMonitorTest> {
  final BLEService _bleService = BLEService();
  int _currentHeartRate = 0;
  bool _isMonitoring = false;
  String _status = 'Not started';

  @override
  void initState() {
    super.initState();
    _setupHeartRateListener();
  }

  void _setupHeartRateListener() {
    _bleService.deviceData.listen((data) {
      if (data['heart_rate'] != null) {
        setState(() {
          _currentHeartRate = data['heart_rate']['current_hr'];
          _status = 'Monitoring: $_currentHeartRate BPM';
        });

        // Check if heart rate is high
        if (_currentHeartRate > 120) {
          setState(() {
            _status =
                '⚠️ HIGH HEART RATE: $_currentHeartRate BPM - SOS will trigger!';
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heart Rate Monitor Test'),
        backgroundColor: Colors.red,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
            Text(
              _status,
              style: TextStyle(
                fontSize: 16,
                color: _currentHeartRate > 120 ? Colors.red : Colors.grey,
              ),
            ),
            const SizedBox(height: 30),
            if (_currentHeartRate > 120)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
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
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/ble');
              },
              icon: const Icon(Icons.bluetooth),
              label: const Text('Connect to Fastrack Watch'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Connect your Fastrack Reflex 8601 watch to test heart rate monitoring',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
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
