import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dito_sdk/dito_sdk.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';

class DitoService {
  DitoService({DitoSdk? sdk}) : _sdk = sdk ?? DitoSdk();

  final DitoSdk _sdk;
  String? _currentToken;
  bool _userIdentified = false;

  Future<void> initialize({
    required String appKey,
    required String appSecret,
  }) async {
    await _sdk.initialize(appKey: appKey, appSecret: appSecret);
    await _sdk.setDebugMode(enabled: kDebugMode);

    // Handle notification that opened the app from terminated state.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      await _handleNotificationClick(initial.data);
    }

    // Forward background-to-foreground notification taps to Dito.
    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      await _handleNotificationClick(message.data);
    });

    // Fetch and cache the FCM token. Registration is deferred until after
    // identifyUser() because Dito requires the user to be identified first.
    final token = await FirebaseMessaging.instance.getToken();
    if (kDebugMode) debugPrint('DitoService: FCM token fetched → $token');
    _currentToken = token;
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) debugPrint('DitoService: FCM token refreshed → $newToken');
      _currentToken = newToken;
      if (_userIdentified) await registerToken(newToken);
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

  static String _sha1(String value) =>
      sha1.convert(utf8.encode(value)).toString();

  Future<void> identifyUser(UserProfile user) async {
    final id = _sha1(user.email);
    if (kDebugMode) {
      debugPrint('DitoService.identifyUser → id=$id email=${user.email}');
    }
    try {
      await _sdk.identify(
        id: id,
        name: user.name,
        email: user.email,
        customData: {
          'gender': user.gender,
          'city': user.city,
          'birth_date': user.birthDate.toIso8601String(),
          'phone': user.phone,
        },
      );
      if (kDebugMode) debugPrint('DitoService.identifyUser ✓ success');
      _userIdentified = true;
      if (_currentToken != null) await registerToken(_currentToken!);
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
    if (kDebugMode) debugPrint('DitoService.registerToken → $token');
    try {
      _currentToken = token;
      await _sdk.registerDeviceToken(token);
      if (kDebugMode) debugPrint('DitoService.registerToken ✓ success');
    } catch (e) {
      if (kDebugMode) debugPrint('DitoService.registerToken error: $e');
    }
  }

  /// Unregisters the last known FCM token. Call on logout.
  Future<void> unregisterCurrentToken() async {
    _userIdentified = false;
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
