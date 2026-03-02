import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

enum AuthFailureReason {
  userNotFound,
  wrongPassword,
  emailAlreadyRegistered,
  invalidPhone,
}

class AuthException implements Exception {
  const AuthException(this.reason);
  final AuthFailureReason reason;
}

class AuthService {
  AuthService({
    FlutterSecureStorage? secureStorage,
    required SharedPreferences prefs,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _prefs = prefs;

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;

  // Tracks which user is currently logged in.
  static const _keyCurrentEmail = 'current_logged_in_email';

  // Per-user storage keys — namespaced by email so multiple accounts can
  // coexist on the same device without overwriting each other's data.
  static String _profileKey(String email) => 'user_profile_$email';
  static String _hashKey(String email) => 'auth_password_hash_$email';
  static String _saltKey(String email) => 'auth_salt_$email';

  static final _phoneRegex = RegExp(
    r'^\+\d{1,3}[\s\-]?\(?\d{1,4}\)?[\s\-]?\d{3,5}[\s\-]?\d{4}$',
  );

  static bool isValidPhone(String phone) => _phoneRegex.hasMatch(phone.trim());

  /// Registers a new user. Throws [AuthException] if the email is already
  /// registered or the phone number is invalid.
  Future<void> register(UserProfile profile, String password) async {
    if (!isValidPhone(profile.phone)) {
      throw const AuthException(AuthFailureReason.invalidPhone);
    }
    if (_prefs.getString(_profileKey(profile.email)) != null) {
      throw const AuthException(AuthFailureReason.emailAlreadyRegistered);
    }

    final salt = _generateSalt();
    final hash = _hashPassword(password, salt);

    await _secureStorage.write(key: _hashKey(profile.email), value: hash);
    await _secureStorage.write(key: _saltKey(profile.email), value: salt);
    await _prefs.setString(_profileKey(profile.email), jsonEncode(profile.toJson()));
    await _prefs.setString(_keyCurrentEmail, profile.email);
  }

  /// Logs in with [email] and [password]. Returns the stored [UserProfile] on
  /// success. Throws [AuthException] if no account exists or the password is wrong.
  Future<UserProfile> login(String email, String password) async {
    final profileJson = _prefs.getString(_profileKey(email));
    if (profileJson == null) {
      throw const AuthException(AuthFailureReason.userNotFound);
    }

    final salt = await _secureStorage.read(key: _saltKey(email));
    final storedHash = await _secureStorage.read(key: _hashKey(email));
    if (salt == null || storedHash == null) {
      throw const AuthException(AuthFailureReason.userNotFound);
    }

    if (_hashPassword(password, salt) != storedHash) {
      throw const AuthException(AuthFailureReason.wrongPassword);
    }

    final profile = UserProfile.fromJson(
      jsonDecode(profileJson) as Map<String, dynamic>,
    );

    await _prefs.setString(_keyCurrentEmail, email);
    return profile;
  }

  /// Clears the session without deleting the stored profile or credentials,
  /// so the user can log back in later.
  Future<void> logout() async {
    await _prefs.remove(_keyCurrentEmail);
  }

  /// Returns the active [UserProfile] if a valid session exists, or null otherwise.
  Future<UserProfile?> loadSession() async {
    final email = _prefs.getString(_keyCurrentEmail);
    if (email == null) return null;

    final profileJson = _prefs.getString(_profileKey(email));
    if (profileJson == null) return null;

    return UserProfile.fromJson(jsonDecode(profileJson) as Map<String, dynamic>);
  }

  String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    return sha256.convert(bytes).toString();
  }
}
