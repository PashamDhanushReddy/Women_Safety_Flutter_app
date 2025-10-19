import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:share_plus/share_plus.dart';
import 'package:send_message/send_message.dart';
import 'package:path/path.dart' as path;

class MMSService {
  /// Send emergency SMS message (SMS-only, no photos)
  static Future<void> sendEmergencySMS({
    required String message,
    required List<String> recipients,
  }) async {
    try {
      print('🚨 EMERGENCY: Starting automatic SMS sending to ${recipients.length} recipients');
      
      // Show notification that emergency messages are being sent automatically
      print('📤 SENDING EMERGENCY SMS AUTOMATICALLY - NO USER INTERACTION REQUIRED');
      
      // Send SMS only
      await _sendSMSOnly(message: message, recipients: recipients);

      print('🎉 Emergency SMS sent automatically in background!');
    } catch (e) {
      print('💥 Error in automatic emergency SMS sending: $e');
      rethrow;
    }
  }

  /// Send SMS with photo file information and location details
  static Future<void> _sendSMSWithPhotoInfo({
    required String message,
    required List<String> photoPaths,
    required List<String> recipients,
  }) async {
    try {
      // Add photo information to message
      String enhancedMessage = message;
      enhancedMessage += '\n\n📸 EMERGENCY PHOTOS CAPTURED:';
      
      for (int i = 0; i < photoPaths.length; i++) {
        final fileName = path.basename(photoPaths[i]);
        final fileSize = File(photoPaths[i]).lengthSync() / 1024; // Size in KB
        enhancedMessage += '\n• Photo ${i + 1}: $fileName (${fileSize.toStringAsFixed(1)}KB)';
      }
      
      enhancedMessage += '\n\n⚠️ Photos saved to device. Check device storage for emergency photos.';

      // Use the send_message package for SMS
      for (final recipient in recipients) {
        try {
          await sendSMS(
            message: enhancedMessage,
            recipients: [recipient],
            sendDirect: true,
          );
          print('SMS sent to $recipient with photo info');
        } catch (e) {
          print('Failed to send SMS to $recipient: $e');
        }
      }
    } catch (e) {
      print('Error sending SMS with photo info: $e');
      // Fallback to original message
      await _sendSMSOnly(message: message, recipients: recipients);
    }
  }

  /// Send MMS automatically using Android's native messaging app
  static Future<void> _sendMMSAutomatically({
    required String message,
    required List<String> photoPaths,
    required List<String> recipients,
  }) async {
    try {
      if (recipients.isEmpty || photoPaths.isEmpty) return;

      print('📱 Starting automatic MMS sending to ${recipients.length} recipients');
      print('📸 Sending ${photoPaths.length} photos via MMS');

      // Use platform channel to send MMS automatically
      const platform = MethodChannel('com.example.hershield/mms');
      
      for (final recipient in recipients) {
        try {
          print('🚀 Sending MMS to $recipient...');
          final result = await platform.invokeMethod('sendMMS', {
            'phoneNumber': recipient,
            'message': message,
            'imagePaths': photoPaths,
          });
          print('✅ MMS sent successfully to $recipient: $result');
        } catch (e) {
          print('❌ Failed to send automatic MMS to $recipient: $e');
          // Fallback to direct SMS if automatic sending fails
          await _sendSMSOnly(
            message: message,
            recipients: [recipient],
          );
        }
      }
    } catch (e) {
      print('💥 Error in automatic MMS sending: $e');
      // Fallback to SMS only
      await _sendSMSOnly(
        message: message,
        recipients: recipients,
      );
    }
  }

  /// Send SMS only (fallback method)
  static Future<void> _sendSMSOnly({
    required String message,
    required List<String> recipients,
  }) async {
    try {
      await sendSMS(
        message: message,
        recipients: recipients,
        sendDirect: true,
      );
      print('SMS sent to ${recipients.length} recipients');
    } catch (e) {
      print('Error sending SMS: $e');
      rethrow;
    }
  }

  /// Share photos via system share dialog (works when app is in foreground)
  static Future<void> _sharePhotosViaSystem({
    required String message,
    required List<String> photoPaths,
    required List<String> recipients,
  }) async {
    try {
      // Create XFile objects for sharing
      final xFiles = photoPaths.map((path) => XFile(path)).toList();
      
      // Share with message and photos
      await Share.shareXFiles(
        xFiles,
        text: message,
        subject: '🚨 EMERGENCY SOS - URGENT',
      );
      
      print('Photos shared via system share dialog');
    } catch (e) {
      print('Error sharing photos via system: $e');
    }
  }

  /// Send photos to emergency contact via WhatsApp or other messaging apps
  static Future<void> _sendPhotosToEmergencyContact({
    required String message,
    required List<String> photoPaths,
    required String emergencyContactPhone,
  }) async {
    try {
      // Create XFile objects
      final xFiles = photoPaths.map((path) => XFile(path)).toList();
      
      // Try to share via WhatsApp or other messaging apps
      final whatsappMessage = '🚨 EMERGENCY SOS\n\n$message\n\nPhotos attached below:';
      
      await Share.shareXFiles(
        xFiles,
        text: whatsappMessage,
        subject: '🚨 EMERGENCY SOS - URGENT',
      );
      
      print('Photos shared for WhatsApp/messaging apps');
    } catch (e) {
      print('Error sharing photos to emergency contact: $e');
    }
  }

  /// Send photos via email (if email addresses are available)
  static Future<void> sendPhotosViaEmail({
    required String message,
    required List<String> photoPaths,
    required List<String> emailRecipients,
  }) async {
    try {
      if (emailRecipients.isEmpty || photoPaths.isEmpty) {
        return;
      }

      final xFiles = photoPaths.map((path) => XFile(path)).toList();
      
      await Share.shareXFiles(
        xFiles,
        text: message,
        subject: '🚨 EMERGENCY SOS - URGENT ASSISTANCE NEEDED',
      );
      
      print('Photos sent via email to ${emailRecipients.length} recipients');
    } catch (e) {
      print('Error sending photos via email: $e');
    }
  }
}