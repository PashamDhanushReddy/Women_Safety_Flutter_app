import 'package:flutter/material.dart';
import 'test_no_signal.dart';

void main() {
  runApp(const NoSignalTestApp());
}

class NoSignalTestApp extends StatelessWidget {
  const NoSignalTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'No Signal Test',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      home: const TestNoSignal(),
    );
  }
}