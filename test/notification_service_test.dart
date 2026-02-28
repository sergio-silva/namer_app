import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:namer_app/services/notification_service.dart';

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class MockFlutterLocalNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

class FakeInitializationSettings extends Fake
    implements InitializationSettings {}

class FakeNotificationDetails extends Fake implements NotificationDetails {}

// Helpers ---------------------------------------------------------------

NotificationSettings _makeSettings(AuthorizationStatus status) =>
    NotificationSettings(
      authorizationStatus: status,
      alert: AppleNotificationSetting.enabled,
      announcement: AppleNotificationSetting.notSupported,
      badge: AppleNotificationSetting.enabled,
      carPlay: AppleNotificationSetting.notSupported,
      criticalAlert: AppleNotificationSetting.notSupported,
      lockScreen: AppleNotificationSetting.enabled,
      notificationCenter: AppleNotificationSetting.enabled,
      showPreviews: AppleShowPreviewSetting.always,
      timeSensitive: AppleNotificationSetting.notSupported,
      sound: AppleNotificationSetting.enabled,
      providesAppNotificationSettings: AppleNotificationSetting.notSupported,
    );

RemoteMessage _makeMessage({RemoteNotification? notification}) =>
    RemoteMessage(
      messageId: 'test-id',
      notification: notification,
    );

// No-op background handler registration — avoids the static Firebase platform
// channel call that has no native implementation in the test environment.
void _noopRegisterBackground(BackgroundMessageHandler _) {}

// Shared stub setup -----------------------------------------------------

void _stubDefaults(
  MockFirebaseMessaging messaging,
  MockFlutterLocalNotificationsPlugin plugin, {
  NotificationSettings? settings,
  String? token,
}) {
  final resolvedSettings =
      settings ?? _makeSettings(AuthorizationStatus.authorized);

  when(
    () => messaging.requestPermission(
      alert: any(named: 'alert'),
      badge: any(named: 'badge'),
      sound: any(named: 'sound'),
    ),
  ).thenAnswer((_) async => resolvedSettings);

  when(() => messaging.getToken()).thenAnswer((_) async => token ?? 'tok-123');
  when(() => messaging.getInitialMessage()).thenAnswer((_) async => null);
  when(() => messaging.onTokenRefresh)
      .thenAnswer((_) => const Stream.empty());

  when(
    () => plugin.initialize(
      any(),
      onDidReceiveNotificationResponse:
          any(named: 'onDidReceiveNotificationResponse'),
    ),
  ).thenAnswer((_) async => true);
  when(
    () => plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>(),
  ).thenReturn(null);
  when(() => plugin.show(any(), any(), any(), any()))
      .thenAnswer((_) async {});
}

// Tests -----------------------------------------------------------------

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(FakeInitializationSettings());
    registerFallbackValue(FakeNotificationDetails());
  });

  late MockFirebaseMessaging mockMessaging;
  late MockFlutterLocalNotificationsPlugin mockPlugin;

  setUp(() {
    mockMessaging = MockFirebaseMessaging();
    mockPlugin = MockFlutterLocalNotificationsPlugin();
  });

  group('NotificationService', () {
    test('can be instantiated with injected mocks', () {
      final service = NotificationService(
        messaging: mockMessaging,
        localNotifications: mockPlugin,
        registerBackgroundHandler: _noopRegisterBackground,
      );
      expect(service, isNotNull);
    });

    test('dispose() cancels all stream subscriptions without throwing',
        () async {
      final messageController = StreamController<RemoteMessage>.broadcast();
      final openedController = StreamController<RemoteMessage>.broadcast();

      _stubDefaults(mockMessaging, mockPlugin);

      final service = NotificationService(
        messaging: mockMessaging,
        localNotifications: mockPlugin,
        onMessageStream: messageController.stream,
        onMessageOpenedAppStream: openedController.stream,
        registerBackgroundHandler: _noopRegisterBackground,
      );

      await service.initialize();

      await expectLater(service.dispose(), completes);

      await messageController.close();
      await openedController.close();
    });

    test('initialize() handles denied permission status gracefully', () async {
      _stubDefaults(
        mockMessaging,
        mockPlugin,
        settings: _makeSettings(AuthorizationStatus.denied),
      );

      final service = NotificationService(
        messaging: mockMessaging,
        localNotifications: mockPlugin,
        onMessageStream: const Stream.empty(),
        onMessageOpenedAppStream: const Stream.empty(),
        registerBackgroundHandler: _noopRegisterBackground,
      );

      // Should not throw even when permission is denied
      await expectLater(service.initialize(), completes);
    });

    test('foreground message with null notification does not call show()',
        () async {
      final controller = StreamController<RemoteMessage>();

      _stubDefaults(mockMessaging, mockPlugin);

      final service = NotificationService(
        messaging: mockMessaging,
        localNotifications: mockPlugin,
        onMessageStream: controller.stream,
        onMessageOpenedAppStream: const Stream.empty(),
        registerBackgroundHandler: _noopRegisterBackground,
      );

      await service.initialize();

      controller.add(_makeMessage(notification: null));
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => mockPlugin.show(any(), any(), any(), any()));

      await service.dispose();
      await controller.close();
    });

    test(
        'foreground message with valid notification calls show() '
        'with incrementing ID counter', () async {
      final controller = StreamController<RemoteMessage>();

      _stubDefaults(mockMessaging, mockPlugin);

      final service = NotificationService(
        messaging: mockMessaging,
        localNotifications: mockPlugin,
        onMessageStream: controller.stream,
        onMessageOpenedAppStream: const Stream.empty(),
        registerBackgroundHandler: _noopRegisterBackground,
      );

      await service.initialize();

      const notification =
          RemoteNotification(title: 'Hello', body: 'World');

      controller.add(_makeMessage(notification: notification));
      controller.add(_makeMessage(notification: notification));
      await Future<void>.delayed(Duration.zero);

      final captured = verify(
        () => mockPlugin.show(captureAny(), any(), any(), any()),
      ).captured;

      expect(captured.length, 2);
      // IDs start at 0 per instance and increment by 1
      expect(captured[0] as int, 0);
      expect(captured[1] as int, 1);

      await service.dispose();
      await controller.close();
    });
  });
}
