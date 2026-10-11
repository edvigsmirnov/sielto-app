import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/space/period_ledger.dart';

class _Open extends Notifier<Space> {
  _Open(this.initial);

  final Space initial;

  @override
  Space build() => initial;

  void set(Space space) => state = space;
}

class _OpenId extends CurrentSpaceIdController {
  @override
  String? build() => null;
}

void main() {
  setUpAll(SpaceClock.initialize);

  test(
    'a sync rewriting the open Space keeps the chosen period and day',
    () async {
      final AppDatabase db = inMemoryDatabase();
      addTearDown(db.close);
      final Space space =
          await SpaceRepository(
            db: db,
            clock: SpaceClock(timezone: 'UTC'),
          ).create(
            title: 'Home',
            spaceType: SpaceType.personal,
            budgetMode: BudgetMode.incomeDriven,
            ownerId: 'me',
            timezone: 'Europe/Berlin',
            currencyCode: 'EUR',
            storageMode: StorageMode.cloud,
          );

      final NotifierProvider<_Open, Space> open =
          NotifierProvider<_Open, Space>(() => _Open(space));
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          currentSpaceIdProvider.overrideWith(_OpenId.new),
          resolvedSpaceProvider.overrideWith(
            (Ref ref) => AsyncData<Space?>(ref.watch(open)),
          ),
        ],
      );
      addTearDown(c.dispose);

      c.listen<String?>(selectedPeriodIdProvider, (String? _, String? _) {});
      c.listen<CalendarDate>(
        selectedDateProvider,
        (CalendarDate? _, CalendarDate _) {},
      );
      c.read(selectedPeriodIdProvider.notifier).select('august');
      c
          .read(selectedDateProvider.notifier)
          .select(const CalendarDate(2026, 8, 3));

      c
          .read(open.notifier)
          .set(space.copyWith(syncedUntil: Value<DateTime?>(DateTime.now())));

      expect(c.read(selectedPeriodIdProvider), 'august');
      expect(c.read(selectedDateProvider), const CalendarDate(2026, 8, 3));
    },
  );
}
