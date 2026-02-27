import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';

// Top-level handler required by FCM for background/terminated messages.
// Must be top-level (not a method) to be used as a background isolate entry point.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) debugPrint('FCM background message: ${message.messageId}');
}

class NotificationService {
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final Stream<RemoteMessage> _onMessageStream;
  final Stream<RemoteMessage> _onMessageOpenedAppStream;
  final void Function(BackgroundMessageHandler)? _registerBackgroundHandler;

  int _notificationId = 0;

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
  );

  NotificationService({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    Stream<RemoteMessage>? onMessageStream,
    Stream<RemoteMessage>? onMessageOpenedAppStream,
    // Allows tests to replace the static FirebaseMessaging.onBackgroundMessage
    // call (which requires a native platform) with a no-op.
    void Function(BackgroundMessageHandler)? registerBackgroundHandler,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin(),
        _onMessageStream = onMessageStream ?? FirebaseMessaging.onMessage,
        _onMessageOpenedAppStream =
            onMessageOpenedAppStream ?? FirebaseMessaging.onMessageOpenedApp,
        _registerBackgroundHandler = registerBackgroundHandler;

  Future<void> initialize() async {
    // Register background message handler (use injected fn if provided, e.g. in tests)
    final registerBg =
        _registerBackgroundHandler ?? FirebaseMessaging.onBackgroundMessage;
    registerBg(_firebaseMessagingBackgroundHandler);

    // Set up local notifications plugin
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(initSettings);

    // Create the Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Request notification permissions (iOS + Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      if (kDebugMode) {
        debugPrint(
          'FCM permission denied: ${settings.authorizationStatus}',
        );
      }
    }

    // Get FCM device token (used by the server to target this device)
    final token = await _messaging.getToken();
    if (token != null) {
      if (kDebugMode) debugPrint('FCM Token: $token');
    }

    // Refresh token listener
    _onTokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
      if (kDebugMode) debugPrint('FCM Token refreshed: $newToken');
    });

    // Foreground message handler — show a local notification
    _onMessageSub = _onMessageStream.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;

      _localNotifications.show(
        _notificationId++,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    });

    // Background → app opened via notification tap
    _onMessageOpenedAppSub =
        _onMessageOpenedAppStream.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint(
          'FCM notification tapped (background): ${message.messageId}',
        );
      }
    });

    // Terminated → app opened via notification tap
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      if (kDebugMode) {
        debugPrint(
          'FCM notification tapped (terminated): ${initialMessage.messageId}',
        );
      }
    }
  }

  void dispose() {
    _onMessageSub?.cancel();
    _onMessageOpenedAppSub?.cancel();
    _onTokenRefreshSub?.cancel();
  }
}
