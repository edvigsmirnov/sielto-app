import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/l10n/app_locales.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/dashboard/period_selector.dart';
import 'package:sielto/features/space/period_ledger.dart';

/// The selector as a bottom bar, where the Feed puts it: it has to take its own
/// height, not the screen's.
class _FileAssetLoader extends AssetLoader {
  const _FileAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final File file = File('$path/${locale.languageCode}.json');
    return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
    await initializeDateFormatting();
  });

  testWidgets('as a bottom bar it stays short and leaves the body its room', (
    WidgetTester tester,
  ) async {
    final BudgetPeriod period = BudgetPeriod(
      id: 'p1',
      spaceId: 's1',
      periodType: PeriodType.incomeDriven,
      startDate: const CalendarDate(2026, 9, 5),
      endDate: const CalendarDate(2026, 10, 4),
      holidayDataIncomplete: false,
      deadlineIsHard: false,
      isDeleted: false,
      syncStatus: SyncStatus.values.first,
      clientEditedAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomePeriodsProvider.overrideWithValue(<BudgetPeriod>[period]),
          selectedPeriodProvider.overrideWithValue(period),
          spaceClockProviderForLabel.overrideWithValue(
            const CalendarDate(2026, 9, 22),
          ),
        ],
        child: EasyLocalization(
          supportedLocales: AppLocales.supported,
          path: AppLocales.path,
          fallbackLocale: AppLocales.fallback,
          startLocale: AppLocales.en,
          saveLocale: false,
          assetLoader: const _FileAssetLoader(),
          child: Builder(
            builder: (BuildContext context) => MaterialApp(
              theme: SageTheme.light,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: const Scaffold(
                body: SizedBox.expand(key: ValueKey<String>('body')),
                bottomNavigationBar: SafeArea(
                  top: false,
                  child: PeriodSelector(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Next period'), findsOneWidget);

    final double screen = tester.getSize(find.byType(Scaffold)).height;
    expect(tester.getSize(find.byType(PeriodSelector)).height, lessThan(100));
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('body'))).height,
      greaterThan(screen / 2),
    );
  });
}
