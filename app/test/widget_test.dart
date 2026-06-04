import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phm_app/main.dart';

void main() {
  testWidgets('Profile settings shows controls and back button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileSettingsPage(plants: ['Plant A'], selectedPlant: null),
      ),
    );

    expect(find.text('Profile Settings'), findsOneWidget);
    expect(find.text('Plant'), findsOneWidget);
    expect(find.text('Humidity'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Soil Moisture'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Save Settings'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.byIcon(Icons.save), findsOneWidget);
  });
}
