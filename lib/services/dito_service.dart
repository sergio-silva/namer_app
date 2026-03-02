import 'package:dito_sdk/dito_sdk.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';

class DitoService {
  DitoService({DitoSdk? sdk}) : _sdk = sdk ?? DitoSdk();

  final DitoSdk _sdk;
  String? _currentToken;

  Future<void> initialize({
    required String appKey,
    required String appSecret,
  }) async {
    await _sdk.initialize(appKey: appKey, appSecret: appSecret);

    // Handle notification that opened the app from terminated state.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      await _handleNotificationClick(initial.data);
    }

    // Forward background-to-foreground notification taps to Dito.
    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      await _handleNotificationClick(message.data);
    });

    // Register current FCM token and keep it up to date.
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await registerToken(token);
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await registerToken(newToken);
    });

    // Listen for in-app notification click events from Dito.
    DitoSdk.onNotificationClick.listen(
      (event) {
        if (event.deeplink.isEmpty) return;
        if (kDebugMode) {
          debugPrint('DitoService: notification click deeplink=${event.deeplink}');
        }
        // TODO: wire up deeplink navigation (e.g. GoRouter) when needed.
      },
      onError: (Object e) {
        if (kDebugMode) debugPrint('DitoService.onNotificationClick error: $e');
      },
    );
  }

  Future<void> identifyUser(UserProfile user) async {
    try {
      await _sdk.identify(
        id: user.email,
        name: user.name,
        email: user.email,
        customData: {
          'gender': user.gender,
          'city': user.city,
          'birth_date': user.birthDate.toIso8601String(),
          'phone': user.phone,
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('DitoService.identifyUser error: $e');
    }
  }

  Future<void> track(String action, {Map<String, dynamic>? data}) async {
    try {
      await _sdk.track(action: action, data: data);
    } catch (e) {
      if (kDebugMode) debugPrint('DitoService.track error: $e');
    }
  }

  Future<void> registerToken(String token) async {
    try {
      _currentToken = token;
      await _sdk.registerDeviceToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('DitoService.registerToken error: $e');
    }
  }

  /// Unregisters the last known FCM token. Call on logout.
  Future<void> unregisterCurrentToken() async {
    if (_currentToken == null) return;
    try {
      await _sdk.unregisterDeviceToken(_currentToken!);
      _currentToken = null;
    } catch (e) {
      if (kDebugMode) debugPrint('DitoService.unregisterToken error: $e');
    }
  }

  Future<void> _handleNotificationClick(Map<String, dynamic> data) async {
    try {
      await _sdk.handleNotificationClick(data);
    } catch (e) {
      if (kDebugMode) debugPrint('DitoService.handleNotificationClick error: $e');
    }
  }
}
