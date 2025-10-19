import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayFloatingAssistant extends StatefulWidget {
  const OverlayFloatingAssistant({super.key});

  @override
  State<OverlayFloatingAssistant> createState() => _OverlayFloatingAssistantState();
}

class _OverlayFloatingAssistantState extends State<OverlayFloatingAssistant> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    print('OverlayFloatingAssistant building - isExpanded: $_isExpanded');
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {
          print('Overlay bubble tapped');
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _isExpanded ? 120 : 60,
          height: _isExpanded ? 120 : 60,
          decoration: BoxDecoration(
            color: Colors.redAccent,  // Brighter red for better visibility
            shape: _isExpanded ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: _isExpanded ? BorderRadius.circular(12) : null,
            border: Border.all(
              color: Colors.white,
              width: 4,  // Thicker border for visibility
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.7),
                blurRadius: 15,  // Larger shadow
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _isExpanded
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        // Trigger emergency call
                        await FlutterOverlayWindow.shareData('trigger_emergency');
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.phone,
                          color: Colors.red,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'SOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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
    );
  }
}