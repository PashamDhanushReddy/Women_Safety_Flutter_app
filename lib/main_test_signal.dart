import 'package:flutter/material.dart';
import 'test_signal_strength.dart';

void main() {
  runApp(const SignalTestApp());
}

class SignalTestApp extends StatelessWidget {
  const SignalTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signal Strength Test',
      theme: ThemeData(
        primarySwatch: Colors.purple,
        useMaterial3: true,
      ),
      home: const TestSignalStrength(),
    );
  }
}