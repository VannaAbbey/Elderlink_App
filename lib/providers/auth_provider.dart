import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  
  User? _currentUser;
  Map<String, dynamic>? _userData;
  bool _isLoading = false;
  String? _error;

  // Getters
  User? get currentUser => _currentUser;
  Map<String, dynamic>? get userData => _userData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;

  // Initialize the provider and listen to auth state changes
  AuthProvider() {
    print('DEBUG: AuthProvider initializing...');
    _initializeAuthListener();
  }

  void _initializeAuthListener() {
    print('DEBUG: Setting up auth state listener...');
    _authService.authStateChanges.listen((User? user) async {
      print('DEBUG: Auth state changed - User: ${user?.email ?? 'null'}');
      _currentUser = user;
      
      if (user != null) {
        // Load user data from Firestore when user signs in
        print('DEBUG: Loading user data for ${user.email}');
        await _loadUserData();
      } else {
        // Clear user data when user signs out
        print('DEBUG: User signed out, clearing data');
        _userData = null;
      }
      
      print('DEBUG: Notifying listeners...');
      notifyListeners();
    });
  }

  // Load user data from Firestore
  Future<void> _loadUserData() async {
    if (_currentUser == null) return;
    
    try {
      print('DEBUG: Loading user data for ${_currentUser!.email}...');
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Add timeout to prevent infinite loading
      _userData = await _authService.getUserData(_currentUser!.uid).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('DEBUG: Loading user data timed out');
          throw Exception('Loading user data timed out after 10 seconds');
        },
      );
      
      print('DEBUG: User data loaded successfully. Role: ${_userData?['user_type'] ?? _userData?['role'] ?? 'unknown'}');
    } catch (e) {
      _error = 'Failed to load user data: $e';
      print('DEBUG: Error loading user data: $e');
      
      // Set empty user data to prevent infinite loading
      _userData = {};
    } finally {
      print('DEBUG: Finished loading, setting isLoading to false');
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign in with email and password
  Future<bool> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final result = await _authService.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return result != null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Register with email and password
  Future<bool> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String role,
    required Map<String, dynamic> userData,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final result = await _authService.registerWithEmailAndPassword(
        email: email,
        password: password,
        role: role,
        userData: userData,
      );

      return result != null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final result = await _authService.signInWithGoogle();
      return result != null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign in with Facebook
  Future<bool> signInWithFacebook() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final result = await _authService.signInWithFacebook();
      return result != null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign in with Apple
  Future<bool> signInWithApple() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final result = await _authService.signInWithApple();
      return result != null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _authService.signOut();
      _userData = null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Reset password
  Future<bool> resetPassword({required String email}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _authService.resetPassword(email: email);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Manually refresh user data
  Future<void> refreshUserData() async {
    if (_currentUser != null) {
      await _loadUserData();
    }
  }

  // Get user's first name for UI display (backward compatible)
  String get userFirstName {
    try {
      // Check new field name first
      if (_userData?['user_fname'] != null && _userData!['user_fname'].toString().isNotEmpty) {
        return _userData!['user_fname'].toString();
      }
      // Fall back to old field name for existing users
      if (_userData?['firstName'] != null && _userData!['firstName'].toString().isNotEmpty) {
        return _userData!['firstName'].toString();
      }
      // Fall back to Firebase display name
      final displayName = _currentUser?.displayName?.split(' ').first;
      if (displayName != null && displayName.isNotEmpty) {
        return displayName;
      }
      return 'User';
    } catch (e) {
      print('DEBUG: Error getting user first name: $e');
      return 'User';
    }
  }

  // Get user's role (backward compatible)
  String get userRole {
    try {
      // Check new field name first
      if (_userData?['user_type'] != null) {
        return _userData!['user_type'].toString();
      }
      // Fall back to old field name for existing users
      if (_userData?['role'] != null) {
        return _userData!['role'].toString();
      }
      // Final fallback to caregiver
      print('DEBUG: No role found, defaulting to caregiver');
      return 'caregiver';
    } catch (e) {
      print('DEBUG: Error getting user role: $e, defaulting to caregiver');
      return 'caregiver';
    }
  }

  // Get user's custom ID
  String get userId {
    return _userData?['user_id'] ?? '';
  }

  // Get user's last name (backward compatible)
  String get userLastName {
    // Check new field name first
    if (_userData?['user_lname'] != null && _userData!['user_lname'].toString().isNotEmpty) {
      return _userData!['user_lname'];
    }
    // Fall back to old field name for existing users
    return _userData?['lastName'] ?? '';
  }

  // Get user's email (backward compatible)
  String get userEmail {
    // Check new field name first
    if (_userData?['user_email'] != null) {
      return _userData!['user_email'];
    }
    // Fall back to old field name for existing users
    return _userData?['email'] ?? _currentUser?.email ?? '';
  }

  // Get user's birthday (backward compatible) - returns DateTime or null  
  DateTime? get userBirthday {
    try {
      // Check new field name first (Timestamp)
      if (_userData?['user_bday'] != null) {
        final birthday = _userData!['user_bday'];
        if (birthday is Timestamp) {
          return birthday.toDate();
        }
      }
      // Fall back to old field name for existing users (String)
      final oldBirthday = _userData?['birthday'];
      if (oldBirthday != null && oldBirthday.toString().isNotEmpty) {
        try {
          return DateTime.parse(oldBirthday);
        } catch (e) {
          print('Error parsing old birthday format: $e');
        }
      }
      return null;
    } catch (e) {
      print('Error in userBirthday getter: $e');
      return null;
    }
  }

  // Get user's birthday as formatted string (for UI display)
  String get userBirthdayString {
    final birthday = userBirthday;
    if (birthday != null) {
      return '${birthday.year}-${birthday.month.toString().padLeft(2, '0')}-${birthday.day.toString().padLeft(2, '0')}';
    }
    return '';
  }

  // Get user's contact number (backward compatible) - returns formatted string with leading zeros
  String get userContactNum {
    try {
      // Check new field name first (int)
      if (_userData?['user_contactNum'] != null) {
        final contactNum = _userData!['user_contactNum'];
        if (contactNum is int) {
          // Convert int back to string, ensuring leading zeros for Philippine numbers
          String numStr = contactNum.toString();
          // Add leading zero if it looks like a Philippine mobile number
          if (numStr.length == 10 && numStr.startsWith('9')) {
            numStr = '0$numStr';
          }
          return numStr;
        } else if (contactNum is String) {
          return contactNum;
        }
      }
      // Fall back to old field name for existing users (String)
      return _userData?['phone'] ?? '';
    } catch (e) {
      print('Error in userContactNum getter: $e');
      return '';
    }
  }

  // Get user's contact number as integer (for database operations)
  int? get userContactNumInt {
    if (_userData?['user_contactNum'] != null) {
      final contactNum = _userData!['user_contactNum'];
      if (contactNum is int) {
        return contactNum;
      } else if (contactNum is String) {
        return int.tryParse(contactNum.replaceAll(RegExp(r'[^\d]'), ''));
      }
    }
    // Fall back to old field name
    final oldPhone = _userData?['phone'];
    if (oldPhone != null) {
      return int.tryParse(oldPhone.toString().replaceAll(RegExp(r'[^\d]'), ''));
    }
    return null;
  }

  // Get user's activation status (backward compatible) - returns boolean
  bool get userActivationStatus {
    try {
      // Check new field name first (boolean)
      if (_userData?['user_activationStatus'] != null) {
        final status = _userData!['user_activationStatus'];
        if (status is bool) {
          return status;
        } else if (status is String) {
          // Convert old string format to boolean
          return status.toLowerCase() == 'active';
        }
      }
      // Default to true (active) for new accounts
      return true;
    } catch (e) {
      print('Error in userActivationStatus getter: $e');
      return true; // Default to active if error occurs
    }
  }

  // Get user's activation status as string (for UI display)
  String get userActivationStatusString {
    return userActivationStatus ? 'Active' : 'Inactive';
  }

  // Get user's profile picture
  String get userProfilePic {
    return _userData?['user_profilePic'] ?? '';
  }
}
