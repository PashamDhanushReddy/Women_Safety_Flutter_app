import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';

class GoogleSignInService {
  static final GoogleSignInService _instance = GoogleSignInService._internal();
  factory GoogleSignInService() => _instance;
  GoogleSignInService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/fitness.activity.read',
      'https://www.googleapis.com/auth/fitness.body.read',
      'https://www.googleapis.com/auth/fitness.heart_rate.read',
    ],
    // For development/testing - allows sign-in without OAuth configuration
    clientId: null, // Will use google-services.json when available
  );

  GoogleSignInAccount? _currentUser;
  bool _isSignedIn = false;

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _isSignedIn;
  String? get userEmail => _currentUser?.email;
  String? get userDisplayName => _currentUser?.displayName;
  String? get userPhotoUrl => _currentUser?.photoUrl;

  // Initialize and check if user is already signed in
  Future<void> initialize() async {
    try {
      _currentUser = _googleSignIn.currentUser;
      _isSignedIn = _currentUser != null;
      debugPrint('🔐 Google Sign-In initialized. Signed in: $_isSignedIn');
      if (_isSignedIn) {
        debugPrint('🔐 User: ${userDisplayName} (${userEmail})');
      }
    } catch (error) {
      debugPrint('❌ Error initializing Google Sign-In: $error');
    }
  }

  // Sign in with Google
  Future<bool> signIn() async {
    try {
      // Check if Google Play Services are available
      if (!await _googleSignIn.isSignedIn()) {
        debugPrint('🔐 Attempting Google Sign-In...');
      }
      
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser != null) {
        _currentUser = googleUser;
        _isSignedIn = true;
        debugPrint('🔐 Google Sign-In successful: ${userDisplayName} (${userEmail})');
        return true;
      } else {
        debugPrint('🔐 Google Sign-In cancelled by user');
        return false;
      }
    } catch (error) {
      debugPrint('❌ Google Sign-In error: $error');
      debugPrint('💡 This usually means the OAuth configuration is missing or incorrect.');
      debugPrint('💡 Please ensure google-services.json is properly configured in Google Cloud Console.');
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      _isSignedIn = false;
      debugPrint('🔐 Google Sign-Out successful');
    } catch (error) {
      debugPrint('❌ Google Sign-Out error: $error');
    }
  }

  // Disconnect (revoke access)
  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
      _currentUser = null;
      _isSignedIn = false;
      debugPrint('🔐 Google Sign-In disconnected');
    } catch (error) {
      debugPrint('❌ Google Sign-In disconnect error: $error');
    }
  }

  // Show sign-in dialog
  Future<bool> showSignInDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Google Sign-In Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.login, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'To access Google Fit data and sync your health information, you need to sign in with your Google account.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'This will allow the app to:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• Access your heart rate data'),
              const Text('• Sync fitness information'),
              const Text('• Provide personalized health insights'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop(true);
                final success = await signIn();
                if (!success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sign-in failed. Please try again.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.login),
              label: const Text('Sign In with Google'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    ) ?? false;
  }

  // Show sign-out confirmation
  Future<bool> showSignOutDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sign Out'),
          content: Text(
            'Are you sure you want to sign out?\n\nCurrent user: ${userDisplayName} (${userEmail})',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sign Out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    ) ?? false;
  }
}