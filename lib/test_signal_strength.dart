import 'package:flutter/material.dart';
import 'package:hershield/services/connectivity_service.dart';

class TestSignalStrength extends StatefulWidget {
  const TestSignalStrength({super.key});

  @override
  State<TestSignalStrength> createState() => _TestSignalStrengthState();
}

class _TestSignalStrengthState extends State<TestSignalStrength> {
  final ConnectivityService _connectivityService = ConnectivityService();
  int _signalBars = 0;
  Map<String, dynamic> _signalInfo = {};
  bool _isLoading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _checkSignalStrength();
  }

  Future<void> _checkSignalStrength() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final signalBars = await _connectivityService.getMobileSignalStrength();
      final signalInfo = await _connectivityService.getMobileSignalInfo();
      
      setState(() {
        _signalBars = signalBars;
        _signalInfo = signalInfo;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Widget _buildSignalBars(int bars) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        return Container(
          width: 8,
          height: 20 + (index * 5),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: index < bars ? Colors.green : Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Signal Strength Test'),
        backgroundColor: Colors.purple,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Mobile Signal Strength',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_error.isNotEmpty)
              Text(
                _error,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              )
            else ...[
              if (_signalBars == -1) ...[
                const Icon(
                  Icons.signal_wifi_off,
                  size: 60,
                  color: Colors.red,
                ),
                const SizedBox(height: 10),
                const Text(
                  'No Signal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ] else ...[
                _buildSignalBars(_signalBars),
                const SizedBox(height: 10),
                Text(
                  '$_signalBars/4 bars',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 20),
              
              if (_signalInfo.isNotEmpty) ...[
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Network Type: ${_signalInfo['networkType'] ?? 'Unknown'}'),
                        const SizedBox(height: 8),
                        Text('Signal Strength: ${_signalInfo['signalStrength'] ?? 'N/A'} dBm'),
                        const SizedBox(height: 8),
                        Text('Roaming: ${_signalInfo['isRoaming'] ?? false ? 'Yes' : 'No'}'),
                        if (_signalInfo['error'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Error: ${_signalInfo['error']}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
            
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _checkSignalStrength,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              child: const Text(
                'Refresh Signal',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
            
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Note: This shows your mobile cellular signal strength, not WiFi signal. '
                'Signal bars: 4=Excellent, 3=Good, 2=Fair, 1=Poor, 0=Very Poor, No Signal=Mobile data off',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}