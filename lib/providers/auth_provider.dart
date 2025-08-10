import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    _initializeAuthListener();
  }

  void _initializeAuthListener() {
    _authService.authStateChanges.listen((User? user) async {
      _currentUser = user;
      
      if (user != null) {
        // Load user data from Firestore when user signs in
        await _loadUserData();
      } else {
        // Clear user data when user signs out
        _userData = null;
      }
      
      notifyListeners();
    });
  }

  // Load user data from Firestore
  Future<void> _loadUserData() async {
    if (_currentUser == null) return;
    
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _userData = await _authService.getUserData(_currentUser!.uid);
    } catch (e) {
      _error = 'Failed to load user data: $e';
      print('Error loading user data: $e');
    } finally {
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

  // Get user's first name for UI display
  String get userFirstName {
    if (_userData?['firstName'] != null && _userData!['firstName'].isNotEmpty) {
      return _userData!['firstName'];
    }
    return _currentUser?.displayName?.split(' ').first ?? 'User';
  }

  // Get user's role
  String get userRole {
    return _userData?['role'] ?? 'caregiver';
  }
}
