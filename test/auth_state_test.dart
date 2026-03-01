import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:namer_app/models/user_profile.dart';
import 'package:namer_app/services/auth_service.dart';
import 'package:namer_app/state/auth_state.dart';

class MockAuthService extends Mock implements AuthService {}

// Helpers ---------------------------------------------------------------

UserProfile _makeProfile() => UserProfile(
      name: 'Test User',
      email: 'user@example.com',
      gender: 'Male',
      city: 'São Paulo',
      birthDate: DateTime(1990, 1, 15),
      phone: '+55 11 99999-9999',
    );

// Tests -----------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(UserProfile(
      name: '',
      email: '',
      gender: '',
      city: '',
      birthDate: DateTime(2000),
      phone: '',
    ));
  });

  late MockAuthService mockService;

  setUp(() => mockService = MockAuthService());

  group('AuthState', () {
    test('isLoading starts true before checkSession is called', () {
      final state = AuthState(authService: mockService);
      expect(state.isLoading, isTrue);
      expect(state.isLoggedIn, isFalse);
    });

    test('checkSession sets isLoggedIn=true and isLoading=false when session exists',
        () async {
      final profile = _makeProfile();
      when(() => mockService.loadSession()).thenAnswer((_) async => profile);

      final state = AuthState(authService: mockService);
      await state.checkSession();

      expect(state.isLoading, isFalse);
      expect(state.isLoggedIn, isTrue);
      expect(state.currentUser, equals(profile));
    });

    test('checkSession sets isLoggedIn=false when no session exists', () async {
      when(() => mockService.loadSession()).thenAnswer((_) async => null);

      final state = AuthState(authService: mockService);
      await state.checkSession();

      expect(state.isLoading, isFalse);
      expect(state.isLoggedIn, isFalse);
      expect(state.currentUser, isNull);
    });

    test('login success sets isLoggedIn=true and currentUser', () async {
      final profile = _makeProfile();
      when(() => mockService.login(any(), any()))
          .thenAnswer((_) async => profile);

      final state = AuthState(authService: mockService);
      await state.login('user@example.com', 'secret');

      expect(state.isLoggedIn, isTrue);
      expect(state.currentUser, equals(profile));
      expect(state.errorMessage, isNull);
      expect(state.isLoading, isFalse);
    });

    test('login failure sets errorMessage and keeps isLoggedIn=false', () async {
      when(() => mockService.login(any(), any()))
          .thenThrow(const AuthException(AuthFailureReason.wrongPassword));

      final state = AuthState(authService: mockService);
      await state.login('user@example.com', 'wrong');

      expect(state.isLoggedIn, isFalse);
      expect(state.errorMessage, isNotNull);
      expect(state.isLoading, isFalse);
    });

    test('register success sets isLoggedIn=true', () async {
      when(() => mockService.register(any(), any()))
          .thenAnswer((_) async {});

      final state = AuthState(authService: mockService);
      await state.register(_makeProfile(), 'password123');

      expect(state.isLoggedIn, isTrue);
      expect(state.errorMessage, isNull);
    });

    test('register failure sets errorMessage', () async {
      when(() => mockService.register(any(), any())).thenThrow(
        const AuthException(AuthFailureReason.emailAlreadyRegistered),
      );

      final state = AuthState(authService: mockService);
      await state.register(_makeProfile(), 'password123');

      expect(state.isLoggedIn, isFalse);
      expect(state.errorMessage, isNotNull);
    });

    test('logout resets isLoggedIn and currentUser', () async {
      final profile = _makeProfile();
      when(() => mockService.login(any(), any()))
          .thenAnswer((_) async => profile);
      when(() => mockService.logout()).thenAnswer((_) async {});

      final state = AuthState(authService: mockService);
      await state.login('user@example.com', 'secret');
      await state.logout();

      expect(state.isLoggedIn, isFalse);
      expect(state.currentUser, isNull);
    });

    test('checkSession sets isLoading=false and isLoggedIn=false when loadSession throws',
        () async {
      when(() => mockService.loadSession()).thenThrow(Exception('storage error'));

      final state = AuthState(authService: mockService);
      await state.checkSession();

      expect(state.isLoading, isFalse);
      expect(state.isLoggedIn, isFalse);
      expect(state.currentUser, isNull);
    });

    test('clearError sets errorMessage to null', () async {
      when(() => mockService.login(any(), any()))
          .thenThrow(const AuthException(AuthFailureReason.wrongPassword));

      final state = AuthState(authService: mockService);
      await state.login('user@example.com', 'wrong');
      expect(state.errorMessage, isNotNull);

      state.clearError();
      expect(state.errorMessage, isNull);
    });
  });
}
