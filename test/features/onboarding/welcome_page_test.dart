import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/features/onboarding/welcome_page.dart';

/// The intro holds the way in until it has played, and a tap skips it.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('a tap skips the intro to a working button', (
    WidgetTester tester,
  ) async {
    int started = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SageTheme.light,
        home: WelcomePage(onStart: (Offset _) => started++),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    FilledButton button() => tester.widget(find.byType(FilledButton));
    expect(button().onPressed, isNull);

    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.tap(find.byType(FilledButton));
    expect(started, 1);
  });
}
