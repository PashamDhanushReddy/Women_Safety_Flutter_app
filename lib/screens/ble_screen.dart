import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import '../services/ble_service.dart';
import '../test_heart_rate_monitor.dart';

class BLEScreen extends StatefulWidget {
  const BLEScreen({Key? key}) : super(key: key);

  @override
  State<BLEScreen> createState() => _BLEScreenState();
}

class _BLEScreenState extends State<BLEScreen> {
  final BLEService _bleService = BLEService();
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isBluetoothEnabled = false;
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  Map<String, dynamic> _deviceData = {};
  
  // Stream subscriptions
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothDevice?>? _connectionSubscription;
  StreamSubscription<Map<String, dynamic>>? _dataSubscription;

  @override
  void initState() {
    super.initState();
    _initializeBLE();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  // Initialize BLE service and set up listeners
  Future<void> _initializeBLE() async {
    try {
      print('🔧 Initializing BLE...');
      
      // Initialize BLE service
      bool initialized = await _bleService.initialize();
      if (!initialized) {
        setState(() {
          _isBluetoothEnabled = false;
        });
        _showError('Failed to initialize Bluetooth. Please check permissions and ensure Bluetooth is enabled.');
        return;
      }

      setState(() {
        _isBluetoothEnabled = true;
      });

      // Set up stream listeners
      _setupStreamListeners();
      
      // Start scanning automatically
      _startScan();
      
    } catch (e) {
      print('❌ Error initializing BLE: $e');
      setState(() {
        _isBluetoothEnabled = false;
      });
      _showError('Error initializing Bluetooth: $e');
    }
  }

  // Set up stream listeners for BLE events
  void _setupStreamListeners() {
    // Listen for scan results
    _scanSubscription = _bleService.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results;
        });
      }
    });

    // Listen for device connection changes
    _connectionSubscription = _bleService.deviceConnection.listen((device) {
      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _isConnecting = false;
        });
      }
    });

    // Listen for device data updates
    _dataSubscription = _bleService.deviceData.listen((data) {
      if (mounted) {
        setState(() {
          _deviceData = data;
        });
      }
    });
  }

  // Start scanning for devices
  Future<void> _startScan() async {
    try {
      setState(() {
        _isScanning = true;
        _scanResults.clear();
      });

      bool started = await _bleService.startScanning();
      if (!started) {
        setState(() {
          _isScanning = false;
        });
        _showError('Failed to start scanning');
      }

      // Auto-stop scan after 30 seconds
      Future.delayed(const Duration(seconds: 30), () {
        if (_isScanning) {
          _stopScan();
        }
      });

    } catch (e) {
      print('❌ Error starting scan: $e');
      setState(() {
        _isScanning = false;
      });
      _showError('Error starting scan: $e');
    }
  }

  // Stop scanning
  Future<void> _stopScan() async {
    try {
      await _bleService.stopScanning();
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    } catch (e) {
      print('❌ Error stopping scan: $e');
    }
  }

  // Connect to device
  Future<void> _connectToDevice(ScanResult result) async {
    try {
      setState(() {
        _isConnecting = true;
      });

      bool connected = await _bleService.connectToDevice(result.device);
      if (!connected) {
        setState(() {
          _isConnecting = false;
        });
        _showError('Failed to connect to device');
      }
    } catch (e) {
      print('❌ Error connecting to device: $e');
      setState(() {
        _isConnecting = false;
      });
      _showError('Error connecting: $e');
    }
  }

  // Disconnect from device
  Future<void> _disconnect() async {
    try {
      await _bleService.disconnect();
      setState(() {
        _connectedDevice = null;
        _deviceData.clear();
      });
    } catch (e) {
      print('❌ Error disconnecting: $e');
      _showError('Error disconnecting: $e');
    }
  }

  // Show error message
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Open Bluetooth settings
  Future<void> _openBluetoothSettings() async {
    try {
      const MethodChannel('flutter_bluetooth_plus').invokeMethod('enableBluetooth');
    } catch (e) {
      print('Could not open Bluetooth settings: $e');
      // Fallback: show message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable Bluetooth in your device settings'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Get device name for display
  String _getDeviceName(ScanResult result) {
    final device = result.device;
    final name = device.platformName ?? 'Unknown Device';
    final id = device.remoteId.str.substring(device.remoteId.str.length - 5);
    return '$name ($id)';
  }

  // Check if device is Fastrack
  bool _isFastrackDevice(ScanResult result) {
    final name = result.device.platformName?.toLowerCase() ?? '';
    return name.contains('fastrack') || name.contains('reflex');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smartwatch Connection'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (_isScanning)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopScan,
              tooltip: 'Stop Scanning',
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
              tooltip: 'Start Scanning',
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection status header
          Container(
            padding: const EdgeInsets.all(16),
            color: _connectedDevice != null ? Colors.green.shade50 : Colors.orange.shade50,
            child: Row(
              children: [
                Icon(
                  _connectedDevice != null ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                  color: _connectedDevice != null ? Colors.green : Colors.orange,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _connectedDevice != null ? 'Connected' : 'Scanning for devices...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _connectedDevice != null ? Colors.green.shade700 : Colors.orange.shade700,
                        ),
                      ),
                      if (_connectedDevice != null)
                        Text(
                          _connectedDevice!.platformName ?? 'Unknown Device',
                          style: TextStyle(
                            color: Colors.green.shade600,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_connectedDevice != null)
                  ElevatedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          ),

          // Device data section
          if (_deviceData.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device Data',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_deviceData['battery'] != null)
                    Row(
                      children: [
                        Icon(Icons.battery_std, color: Colors.green.shade600),
                        const SizedBox(width: 8),
                        Text('Battery: ${_deviceData['battery']}%'),
                      ],
                    ),
                  if (_deviceData['heart_rate'] != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.favorite, color: Colors.red.shade600),
                            const SizedBox(width: 8),
                            Text('Heart Rate: ${_deviceData['heart_rate']['current_hr']} bpm'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange.shade600, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'SOS Alert: ${int.parse(_deviceData['heart_rate']['current_hr'].toString()) > 120 ? 'ACTIVE' : 'Normal'}',
                              style: TextStyle(
                                color: int.parse(_deviceData['heart_rate']['current_hr'].toString()) > 120 
                                    ? Colors.red.shade700 
                                    : Colors.green.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HeartRateMonitorTest(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.monitor_heart),
                          label: const Text('Test Heart Rate Monitor'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  if (_deviceData['device_info'] != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_deviceData['device_info']['manufacturer'] != null)
                          Text('Manufacturer: ${_deviceData['device_info']['manufacturer']}'),
                        if (_deviceData['device_info']['model'] != null)
                          Text('Model: ${_deviceData['device_info']['model']}'),
                      ],
                    ),
                ],
              ),
            ),

          // Devices list
          Expanded(
            child: !_isBluetoothEnabled
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bluetooth_disabled,
                          size: 64,
                          color: Colors.red.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Bluetooth is not enabled',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please enable Bluetooth in your device settings',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _initializeBLE,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _openBluetoothSettings,
                          icon: const Icon(Icons.settings),
                          label: const Text('Open Bluetooth Settings'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  )
                : _scanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isScanning)
                          const CircularProgressIndicator()
                        else
                          Icon(
                            Icons.bluetooth_disabled,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning
                              ? 'Scanning for devices...'
                              : 'No devices found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (!_isScanning)
                          TextButton(
                            onPressed: _startScan,
                            child: const Text('Tap to scan'),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];
                      final deviceName = _getDeviceName(result);
                      final isFastrack = _isFastrackDevice(result);
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: Icon(
                            isFastrack ? Icons.watch : Icons.bluetooth,
                            color: isFastrack ? Colors.blue : Colors.grey,
                            size: 32,
                          ),
                          title: Text(
                            deviceName,
                            style: TextStyle(
                              fontWeight: isFastrack ? FontWeight.bold : FontWeight.normal,
                              color: isFastrack ? Colors.blue.shade700 : Colors.black87,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('RSSI: ${result.rssi} dBm'),
                              if (isFastrack)
                                Text(
                                  'Fastrack Device Detected',
                                  style: TextStyle(
                                    color: Colors.green.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                          trailing: _connectedDevice?.remoteId == result.device.remoteId
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : ElevatedButton(
                                  onPressed: _isConnecting
                                      ? null
                                      : () => _connectToDevice(result),
                                  child: _isConnecting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Connect'),
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? _stopScan : _startScan,
        backgroundColor: _isScanning ? Colors.red : Colors.blue,
        child: Icon(_isScanning ? Icons.stop : Icons.search),
        tooltip: _isScanning ? 'Stop Scanning' : 'Start Scanning',
      ),
    );
  }
}