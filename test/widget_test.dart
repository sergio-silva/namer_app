import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:namer_app/main.dart';
import 'package:namer_app/services/auth_service.dart';

void main() {
  testWidgets('MyApp shows loading indicator on cold start', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final authService = AuthService(prefs: prefs);

    await tester.pumpWidget(MyApp(authService: authService));

    // While checkSession() is in flight, isLoading=true → spinner is shown.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
