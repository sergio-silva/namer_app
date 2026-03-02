import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/dito_service.dart';

class AuthState extends ChangeNotifier {
  AuthState({required AuthService authService, DitoService? ditoService})
      : _authService = authService,
        _ditoService = ditoService;

  final AuthService _authService;
  final DitoService? _ditoService;

  bool _isLoading = true;
  bool _isLoggedIn = false;
  UserProfile? _currentUser;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  UserProfile? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;

  /// Checks for an existing session. Called once at startup via cascade in
  /// ChangeNotifierProvider.create.
  Future<void> checkSession() async {
    try {
      final profile = await _authService.loadSession();
      _isLoggedIn = profile != null;
      _currentUser = profile;
    } catch (e) {
      if (kDebugMode) debugPrint('AuthState.checkSession error: $e');
      _isLoggedIn = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.login(email, password);
      _isLoggedIn = true;
      if (_currentUser != null) await _ditoService?.identifyUser(_currentUser!);
    } on AuthException catch (e) {
      _errorMessage = _messageFor(e.reason);
    } catch (e) {
      if (kDebugMode) debugPrint('AuthState.login unexpected error: $e');
      _errorMessage = 'An unexpected error occurred. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register(UserProfile profile, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.register(profile, password);
      _currentUser = profile;
      _isLoggedIn = true;
      await _ditoService?.identifyUser(profile);
    } on AuthException catch (e) {
      _errorMessage = _messageFor(e.reason);
    } catch (e) {
      if (kDebugMode) debugPrint('AuthState.register unexpected error: $e');
      _errorMessage = 'An unexpected error occurred. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      unawaited(_ditoService?.unregisterCurrentToken());
      await _authService.logout();
      _isLoggedIn = false;
      _currentUser = null;
    } catch (e) {
      if (kDebugMode) debugPrint('AuthState.logout unexpected error: $e');
      _errorMessage = 'Logout failed. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  String _messageFor(AuthFailureReason reason) => switch (reason) {
        AuthFailureReason.userNotFound => 'No account found with this email.',
        AuthFailureReason.wrongPassword => 'Incorrect password.',
        AuthFailureReason.emailAlreadyRegistered =>
          'An account already exists. Please log in.',
        AuthFailureReason.invalidPhone =>
          'Invalid phone number. Use international format: +55 11 99999-9999',
      };
}
