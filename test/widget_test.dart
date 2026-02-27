import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:namer_app/main.dart';

void main() {
  testWidgets('MyApp renders NavigationRail and GeneratorPage smoke test',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(GeneratorPage), findsOneWidget);
  });
}
