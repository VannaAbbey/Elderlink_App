import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';

// auth service for firebase authentication kineme
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Generate custom user_id (4 characters: U001, U002, etc.)
  // U001 is reserved for administrator
  Future<String> _generateCustomUserId() async {
    final querySnapshot = await _firestore.collection('users')
        .orderBy('user_id', descending: true)
        .limit(1)
        .get();
    
    int nextNumber = 2; // Start from 2 since U001 is reserved for administrator
    if (querySnapshot.docs.isNotEmpty) {
      final lastUserId = querySnapshot.docs.first.data()['user_id'] as String?;
      if (lastUserId != null && lastUserId.startsWith('U')) {
        final numberPart = lastUserId.substring(1);
        final lastNumber = int.tryParse(numberPart) ?? 1;
        nextNumber = lastNumber + 1;
      }
    }
    
    return 'U${nextNumber.toString().padLeft(3, '0')}';
  }

  // Check platform availability for social sign-in
  Future<bool> _isPlatformSupported(String provider) async {
    try {
      switch (provider) {
        case 'google':
          // Google sign in is supported on Android and iOS
          return true;
        case 'facebook':
          // Facebook sign in is supported on Android and iOS
          return true;
        case 'apple':
          // Apple sign in is only supported on iOS 13+ and macOS 10.15+ (baka iremove if di matest aka wala tayong iphone)
          return await SignInWithApple.isAvailable();
        default:
          return false;
      }
    } catch (e) {
      print('Error checking platform support for $provider: $e');
      return false;
    }
  }

  // Auth state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with email and password
  Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Register with email and password
  Future<UserCredential?> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String role, // caregiver or nurse
    required Map<String, dynamic> userData,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create user document in Firestore with new field names
      if (result.user != null) {
        final customUserId = await _generateCustomUserId();
        
        // Parse phone number to int, preserving leading zeros by storing as string first
        String phoneStr = userData['phone'] ?? '';
        int? phoneNum;
        if (phoneStr.isNotEmpty) {
          // Remove any non-digit characters except leading zeros
          phoneStr = phoneStr.replaceAll(RegExp(r'[^\d]'), '');
          phoneNum = int.tryParse(phoneStr);
        }
        
        // Parse birthday string to Timestamp
        Timestamp? birthdayTimestamp;
        if (userData['birthday'] != null && userData['birthday'].toString().isNotEmpty) {
          try {
            DateTime birthdayDate = DateTime.parse(userData['birthday']);
            // Set time to midnight to focus on date only
            birthdayDate = DateTime(birthdayDate.year, birthdayDate.month, birthdayDate.day);
            birthdayTimestamp = Timestamp.fromDate(birthdayDate);
          } catch (e) {
            print('Error parsing birthday: $e');
          }
        }
        
        await _firestore.collection('users').doc(result.user!.uid).set({
          'user_id': customUserId,
          'user_email': email,
          'user_type': role,
          'user_fname': userData['firstName'] ?? '',
          'user_lname': userData['lastName'] ?? '',
          'user_bday': birthdayTimestamp,
          'user_contactNum': phoneNum,
          'user_activationStatus': true, // Boolean: true for active
          'user_profilePic': '', // Empty for now, to be added later
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception('Error signing out: $e');
    }
  }

  // Clear all existing user records and reinitialize with admin account
  // WARNING: This will delete ALL user data - use only for development/testing
  Future<void> clearAndReinitializeDatabase() async {
    try {
      print('WARNING: Clearing all user data...');
      
      // Get all user documents
      final usersSnapshot = await _firestore.collection('users').get();
      
      // Delete all existing user documents
      for (QueryDocumentSnapshot doc in usersSnapshot.docs) {
        await doc.reference.delete();
      }
      
      print('All user records cleared');
      
      // Initialize admin account
      await initializeAdminAccount();
      
      print('Database reinitialized with administrator account');
    } catch (e) {
      print('Error clearing database: $e');
      throw Exception('Failed to clear and reinitialize database: $e');
    }
  }

  // Initialize administrator account (U001)
  // This method should be called once during app setup
  Future<void> initializeAdminAccount() async {
    try {
      // Check if admin account already exists
      final adminQuery = await _firestore.collection('users')
          .where('user_id', isEqualTo: 'U001')
          .limit(1)
          .get();
      
      if (adminQuery.docs.isEmpty) {
        // Create admin user in Firebase Auth
        UserCredential adminCredential = await _auth.createUserWithEmailAndPassword(
          email: 'admin@elderlink.com',
          password: 'AdminElderLink2024!', // Strong default password - should be changed
        );

        if (adminCredential.user != null) {
          // Create admin document in Firestore
          await _firestore.collection('users').doc(adminCredential.user!.uid).set({
            'user_id': 'U001',
            'user_email': 'admin@elderlink.com',
            'user_type': 'administrator',
            'user_fname': 'System',
            'user_lname': 'Administrator',
            'user_bday': null, // No birthday for system account
            'user_contactNum': null, // No phone for system account
            'user_activationStatus': true, // Always active
            'user_profilePic': '', // Empty for now
            'createdAt': FieldValue.serverTimestamp(),
          });
          
          print('Administrator account (U001) created successfully');
        }
      } else {
        print('Administrator account (U001) already exists');
      }
    } catch (e) {
      print('Error initializing admin account: $e');
      throw Exception('Failed to initialize administrator account: $e');
    }
  }

  // Reset password
  Future<void> resetPassword({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Get user data from Firestore
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      return doc.data() as Map<String, dynamic>?;
    } catch (e) {
      throw Exception('Error getting user data: $e');
    }
  }

  // Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'email-not-found'; // Special code for login.dart to handle
      case 'wrong-password':
        return 'invalid-password'; // Specific code for wrong password
      case 'invalid-credential':
        return 'invalid-credential'; // Could be either - let login.dart decide
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'account-disabled'; // Special code for login.dart
      case 'too-many-requests':
        return 'too-many-attempts'; // Special code for login.dart
      case 'network-request-failed':
        return 'network-error'; // Special code for login.dart
      case 'operation-not-allowed':
        return 'Signing in with Email and Password is not enabled.';
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }

  // Google Sign In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Check platform support
      if (!await _isPlatformSupported('google')) {
        throw Exception('Google Sign-In is not supported on this platform');
      }

      // Initialize Google Sign In
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );
      
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      if (googleUser == null) {
        return null; // User cancelled the sign-in
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      
      // Create or update user document in Firestore
      if (userCredential.user != null) {
        await _createSocialUserDocument(userCredential.user!, 'google');
      }

      return userCredential;
    } on PlatformException catch (e) {
      throw Exception('Google Sign-In platform error: ${e.message}');
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Error signing in with Google: $e');
    }
  }

  // Facebook Sign In
  Future<UserCredential?> signInWithFacebook() async {
    try {
      // Check platform support
      if (!await _isPlatformSupported('facebook')) {
        throw Exception('Facebook Sign-In is not supported on this platform');
      }

      // Trigger the sign-in flow
      final LoginResult loginResult = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      if (loginResult.status != LoginStatus.success) {
        if (loginResult.status == LoginStatus.cancelled) {
          return null; // User cancelled
        }
        throw Exception('Facebook login failed: ${loginResult.message}');
      }

      // Create a credential from the access token
      final OAuthCredential facebookAuthCredential = 
          FacebookAuthProvider.credential(loginResult.accessToken!.tokenString);

      // Sign in to Firebase with the Facebook credential
      final UserCredential userCredential = await _auth.signInWithCredential(facebookAuthCredential);
      
      // Create or update user document in Firestore
      if (userCredential.user != null) {
        await _createSocialUserDocument(userCredential.user!, 'facebook');
      }

      return userCredential;
    } on PlatformException catch (e) {
      throw Exception('Facebook Sign-In platform error: ${e.message}');
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Error signing in with Facebook: $e');
    }
  }

  // Apple Sign In
  Future<UserCredential?> signInWithApple() async {
    try {
      // Check if Apple Sign In is available
      if (!await SignInWithApple.isAvailable()) {
        throw Exception('Apple Sign In is not available on this device');
      }

      // Generate a random nonce
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      // Request credential for the currently signed in Apple account
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      // Create an OAuthCredential from the credential returned by Apple
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      // Sign in the user with Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(oauthCredential);
      
      // Create or update user document in Firestore with Apple-specific data
      if (userCredential.user != null) {
        await _createSocialUserDocument(
          userCredential.user!, 
          'apple',
          appleCredential: appleCredential,
        );
      }

      return userCredential;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return null; // User cancelled
      }
      throw Exception('Apple Sign-In authorization error: ${e.message}');
    } on PlatformException catch (e) {
      throw Exception('Apple Sign-In platform error: ${e.message}');
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Error signing in with Apple: $e');
    }
  }

  // Helper method to create user document for social sign-ins
  Future<void> _createSocialUserDocument(
    User user, 
    String provider, {
    AuthorizationCredentialAppleID? appleCredential,
  }) async {
    try {
      // Check if user document already exists
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      
      if (!userDoc.exists) {
        // Extract name information
        String firstName = '';
        String lastName = '';
        
        if (provider == 'apple' && appleCredential != null) {
          firstName = appleCredential.givenName ?? '';
          lastName = appleCredential.familyName ?? '';
        } else if (user.displayName != null) {
          final nameParts = user.displayName!.split(' ');
          firstName = nameParts.first;
          if (nameParts.length > 1) {
            lastName = nameParts.skip(1).join(' ');
          }
        }

        // Create new user document with new field names
        final customUserId = await _generateCustomUserId();
        
        await _firestore.collection('users').doc(user.uid).set({
          'user_id': customUserId,
          'user_email': user.email,
          'user_fname': firstName,
          'user_lname': lastName,
          'user_bday': null, // Null for social sign-ins (no birthday provided)
          'user_contactNum': null, // Null for social sign-ins (no phone provided)
          'user_type': 'caregiver', // Default role for social sign-ins
          'user_activationStatus': true, // Boolean: true for active
          'user_profilePic': '', // Empty for now, to be added later
          'provider': provider,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error creating social user document: $e');
    }
  }

  // Generate a cryptographically secure random nonce
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  // Generate SHA256 hash of input string
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
