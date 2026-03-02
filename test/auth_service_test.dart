import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:namer_app/models/user_profile.dart';
import 'package:namer_app/services/auth_service.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// Helpers ---------------------------------------------------------------

UserProfile _makeProfile({String email = 'user@example.com'}) => UserProfile(
      name: 'Test User',
      email: email,
      gender: 'Male',
      city: 'São Paulo',
      birthDate: DateTime(1990, 1, 15),
      phone: '+55 11 99999-9999',
    );

void _stubSecureStorageDefaults(MockFlutterSecureStorage storage) {
  when(() => storage.read(key: any(named: 'key')))
      .thenAnswer((_) async => null);
  when(
    () => storage.write(
      key: any(named: 'key'),
      value: any(named: 'value'),
    ),
  ).thenAnswer((_) async {});
}

Future<(AuthService, MockFlutterSecureStorage)> _makeService() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = MockFlutterSecureStorage();
  _stubSecureStorageDefaults(storage);
  return (AuthService(secureStorage: storage, prefs: prefs), storage);
}

// Tests -----------------------------------------------------------------

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('AuthService.isValidPhone', () {
    test('accepts +55 11 99999-9999', () {
      expect(AuthService.isValidPhone('+55 11 99999-9999'), isTrue);
    });

    test('accepts +55 (11) 99999-9999', () {
      expect(AuthService.isValidPhone('+55 (11) 99999-9999'), isTrue);
    });

    test('accepts +1 650 555-1234', () {
      expect(AuthService.isValidPhone('+1 650 555-1234'), isTrue);
    });

    test('rejects empty string', () {
      expect(AuthService.isValidPhone(''), isFalse);
    });

    test('rejects number without country code', () {
      expect(AuthService.isValidPhone('11 99999-9999'), isFalse);
    });
  });

  group('AuthService.register', () {
    test('writes hash and salt to secure storage', () async {
      final (service, storage) = await _makeService();

      await service.register(_makeProfile(), 'password123');

      verify(
        () => storage.write(
          key: 'auth_password_hash_user@example.com',
          value: any(named: 'value'),
        ),
      ).called(1);
      verify(
        () => storage.write(
          key: 'auth_salt_user@example.com',
          value: any(named: 'value'),
        ),
      ).called(1);
    });

    test('writes profile JSON to SharedPreferences (without password)', () async {
      final (service, _) = await _makeService();
      final prefs = await SharedPreferences.getInstance();

      await service.register(_makeProfile(), 'password123');

      final stored = prefs.getString('user_profile_user@example.com');
      expect(stored, isNotNull);
      final json = jsonDecode(stored!) as Map<String, dynamic>;
      expect(json['email'], 'user@example.com');
      expect(json.containsKey('password'), isFalse);
      expect(json.containsKey('password_hash'), isFalse);
    });

    test('sets current_logged_in_email to the registered email', () async {
      final (service, _) = await _makeService();
      final prefs = await SharedPreferences.getInstance();

      await service.register(_makeProfile(), 'password123');

      expect(prefs.getString('current_logged_in_email'), 'user@example.com');
    });

    test('throws emailAlreadyRegistered if a profile already exists', () async {
      final (service, _) = await _makeService();

      await service.register(_makeProfile(), 'password123');

      expect(
        () => service.register(_makeProfile(), 'other'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.reason,
            'reason',
            AuthFailureReason.emailAlreadyRegistered,
          ),
        ),
      );
    });

    test('throws invalidPhone if phone fails validation', () async {
      final (service, _) = await _makeService();
      final badProfile = UserProfile(
        name: 'Test',
        email: 'a@b.com',
        gender: 'Male',
        city: 'City',
        birthDate: DateTime(1990),
        phone: '99999-9999', // missing country code
      );

      expect(
        () => service.register(badProfile, 'password123'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.reason,
            'reason',
            AuthFailureReason.invalidPhone,
          ),
        ),
      );
    });
  });

  group('AuthService.login', () {
    test('returns UserProfile on correct password', () async {
      final (service, storage) = await _makeService();

      await service.register(_makeProfile(), 'secret');

      // Capture what was written to secure storage during register
      final saltCapture = verify(
        () => storage.write(
          key: 'auth_salt_user@example.com',
          value: captureAny(named: 'value'),
        ),
      ).captured;
      final hashCapture = verify(
        () => storage.write(
          key: 'auth_password_hash_user@example.com',
          value: captureAny(named: 'value'),
        ),
      ).captured;

      // Stub reads to return the captured values
      when(() => storage.read(key: 'auth_salt_user@example.com'))
          .thenAnswer((_) async => saltCapture.first as String);
      when(() => storage.read(key: 'auth_password_hash_user@example.com'))
          .thenAnswer((_) async => hashCapture.first as String);

      final profile = await service.login('user@example.com', 'secret');

      expect(profile.email, 'user@example.com');
    });

    test('throws userNotFound if no profile is stored', () async {
      final (service, _) = await _makeService();

      expect(
        () => service.login('nobody@example.com', 'pass'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.reason,
            'reason',
            AuthFailureReason.userNotFound,
          ),
        ),
      );
    });

    test('throws userNotFound if email does not match stored profile', () async {
      final (service, _) = await _makeService();

      await service.register(_makeProfile(), 'secret');

      // Attempting to log in with a different email finds no profile for that
      // email (keys are per-email), so it throws userNotFound directly.
      expect(
        () => service.login('different@example.com', 'secret'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.reason,
            'reason',
            AuthFailureReason.userNotFound,
          ),
        ),
      );
    });

    test('throws wrongPassword if hash does not match', () async {
      final (service, storage) = await _makeService();

      await service.register(_makeProfile(), 'correct');

      final saltCapture = verify(
        () => storage.write(
          key: 'auth_salt_user@example.com',
          value: captureAny(named: 'value'),
        ),
      ).captured;
      final hashCapture = verify(
        () => storage.write(
          key: 'auth_password_hash_user@example.com',
          value: captureAny(named: 'value'),
        ),
      ).captured;

      when(() => storage.read(key: 'auth_salt_user@example.com'))
          .thenAnswer((_) async => saltCapture.first as String);
      when(() => storage.read(key: 'auth_password_hash_user@example.com'))
          .thenAnswer((_) async => hashCapture.first as String);

      expect(
        () => service.login('user@example.com', 'wrong'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.reason,
            'reason',
            AuthFailureReason.wrongPassword,
          ),
        ),
      );
    });
  });

  group('AuthService.logout', () {
    test('clears current_logged_in_email without deleting profile', () async {
      final (service, _) = await _makeService();
      final prefs = await SharedPreferences.getInstance();

      await service.register(_makeProfile(), 'pass');
      await service.logout();

      expect(prefs.getString('current_logged_in_email'), isNull);
      expect(prefs.getString('user_profile_user@example.com'), isNotNull);
    });
  });

  group('AuthService.loadSession', () {
    test('returns null when no session exists', () async {
      final (service, _) = await _makeService();

      final result = await service.loadSession();

      expect(result, isNull);
    });

    test('returns UserProfile when session is active', () async {
      final (service, _) = await _makeService();

      await service.register(_makeProfile(), 'pass');

      final result = await service.loadSession();

      expect(result, isNotNull);
      expect(result!.email, 'user@example.com');
    });

    test('returns null when session email is set but profile is missing', () async {
      SharedPreferences.setMockInitialValues({
        'current_logged_in_email': 'ghost@example.com',
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = MockFlutterSecureStorage();
      _stubSecureStorageDefaults(storage);
      final service = AuthService(secureStorage: storage, prefs: prefs);

      final result = await service.loadSession();

      expect(result, isNull);
    });
  });
}
