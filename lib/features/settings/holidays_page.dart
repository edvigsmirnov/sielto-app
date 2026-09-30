import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/holidays/countries.dart';
import 'package:sielto/core/holidays/holiday_source.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/periods/holiday_service.dart';

/// Settings → Weekends and holidays: the country's public holidays, read-only,
/// and the user's own days.
class HolidaysPage extends ConsumerWidget {
  const HolidaysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? country = ref.watch(defaultCountryProvider);
    final bool offline = ref.watch(offlineModeProvider);
    final bool? consent = ref.watch(holidayConsentProvider);
    final DateLabels dates = DateLabels(context.locale.toString());

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(title: Text(tr('holidays.title'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: SageSpace.xl),
        children: <Widget>[
          SectionLabel(tr('holidays.country')),
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(
              _countryLabel(ref, country, context.locale.languageCode),
            ),
            subtitle: Text(tr('holidays.countryHint')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickCountry(context, ref),
          ),
          if (country != null) _RegionTile(country: country),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.cloud_download_outlined),
            title: Text(tr('holidays.download')),
            subtitle: Text(
              offline ? tr('holidays.blockedByOffline') : tr('holidays.source'),
            ),
            value: !offline && (consent ?? false),
            // Inactive while offline mode is on.
            onChanged: offline
                ? null
                : (bool value) => ref
                      .read(holidayConsentProvider.notifier)
                      .set(allowed: value),
          ),

          const SizedBox(height: SageSpace.md),
          SectionLabel(tr('holidays.publicTitle')),
          _PublicHolidays(country: country, dates: dates),

          const SizedBox(height: SageSpace.md),
          SectionLabel(tr('holidays.customTitle')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
            child: Text(
              tr('holidays.customWarning'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: SageSpace.sm),
          const _CustomDays(),
          Padding(
            padding: const EdgeInsets.all(SageSpace.gutter),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 20),
              label: Text(tr('holidays.addDay')),
              onPressed: () => markNonWorkingDay(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  String _countryLabel(WidgetRef ref, String? code, String language) {
    if (code == null) return tr('holidays.noCountry');
    final List<HolidayCountry> all =
        ref.watch(holidayCountriesProvider(language)).value ??
        const <HolidayCountry>[];
    for (final HolidayCountry c in all) {
      if (c.code == code) return '${c.name} ($code)';
    }
    return code;
  }

  Future<void> _pickCountry(BuildContext context, WidgetRef ref) async {
    final String? previous = ref.read(defaultCountryProvider);
    final _CountryResult? picked = await showModalBottomSheet<_CountryResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => const _CountryPicker(),
    );
    if (picked == null) return;

    await ref.read(defaultCountryProvider.notifier).set(picked.code);
    // The first country choice asks for download consent.
    if (picked.code != null &&
        previous == null &&
        ref.read(holidayConsentProvider) == null &&
        context.mounted) {
      await askHolidayConsent(context, ref);
    }
  }
}

/// Asked once, when a country is first chosen.
Future<void> askHolidayConsent(BuildContext context, WidgetRef ref) async {
  final bool allowed = await confirmDialog(
    context,
    title: tr('holidays.consentTitle'),
    body: tr('holidays.consentBody'),
    confirmLabel: tr('holidays.consentAllow'),
  );
  await ref.read(holidayConsentProvider.notifier).set(allowed: allowed);
}

/// Adds a non-working day: a date, then an optional name. Shared with the Feed
/// and Calendar menus.
Future<void> markNonWorkingDay(
  BuildContext context,
  WidgetRef ref, {
  CalendarDate? initial,
  bool askDate = true,
}) async {
  final CalendarDate today = ref.read(spaceClockProvider).today();
  CalendarDate date = initial ?? today;

  if (askDate) {
    final CalendarDate? picked = await pickDate(context, date);
    if (picked == null || !context.mounted) return;
    date = picked;
  }

  final String? title = await _askDayTitle(context);
  if (title == null) return;

  await ref
      .read(repositoriesProvider)
      .customDays
      .add(
        date: date,
        title: title.isEmpty ? null : title,
        // Same country as the resolved calendar.
        countryCode:
            ref.read(currentSpaceProvider)?.countryCode ??
            ref.read(defaultCountryProvider),
      );
  ref.invalidate(periodRefreshProvider);
}

/// Empty string: no name. Null: cancelled.
Future<String?> _askDayTitle(BuildContext context) => showDialog<String>(
  context: context,
  builder: (BuildContext context) => const _DayTitleDialog(),
);

/// Owns its controller: the dialog outlives the future during its exit.
class _DayTitleDialog extends StatefulWidget {
  const _DayTitleDialog();

  @override
  State<_DayTitleDialog> createState() => _DayTitleDialogState();
}

class _DayTitleDialogState extends State<_DayTitleDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.sage.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SageRadius.card),
    ),
    title: Text(
      tr('holidays.dayTitle'),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 200,
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(hintText: tr('holidays.dayTitleHint')),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('common.cancel')),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: Text(tr('common.save')),
      ),
    ],
  );
}

typedef _YearHolidays = ({
  List<CalendarDate>? days,
  Map<CalendarDate, List<String>> names,
});

/// Names are bundled; fetched years have none. Reruns after a fetch.
final _yearHolidaysProvider = FutureProvider.autoDispose
    .family<_YearHolidays, ({String country, int year})>((
      Ref ref,
      ({String country, int year}) key,
    ) async {
      ref.watch(resolvedCalendarProvider);
      return (
        days: await ref
            .read(repositoriesProvider)
            .holidays
            .cached(
              cacheKey(key.country, ref.watch(holidayRegionProvider)),
              key.year,
            ),
        names: await const HolidayBundle().namesFor(key.country),
      );
    });

/// Shown only for a country with regional holidays.
class _RegionTile extends ConsumerWidget {
  const _RegionTile({required this.country});

  final String country;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<HolidayCountry> regions =
        ref
            .watch(
              holidayRegionsProvider((
                country: country,
                language: context.locale.languageCode,
              )),
            )
            .value ??
        const <HolidayCountry>[];
    if (regions.isEmpty) return const SizedBox.shrink();

    final String? region = ref.watch(holidayRegionProvider);
    final String label = region == null
        ? tr('holidays.wholeCountry')
        : regions
                  .where((HolidayCountry r) => r.code == region)
                  .firstOrNull
                  ?.name ??
              region;

    return ListTile(
      leading: const Icon(Icons.map_outlined),
      title: Text(label),
      subtitle: Text(tr('holidays.region')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final _CountryResult? picked =
            await showModalBottomSheet<_CountryResult>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (BuildContext sheet) => SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(sheet).height * 0.6,
                  child: ListView(
                    children: <Widget>[
                      ListTile(
                        title: Text(tr('holidays.wholeCountry')),
                        selected: region == null,
                        onTap: () =>
                            Navigator.of(sheet).pop(const _CountryResult(null)),
                      ),
                      const Hairline(),
                      for (final HolidayCountry r in regions)
                        ListTile(
                          title: Text(r.name),
                          selected: r.code == region,
                          onTap: () =>
                              Navigator.of(sheet).pop(_CountryResult(r.code)),
                        ),
                    ],
                  ),
                ),
              ),
            );
        if (picked == null) return;
        await ref.read(holidayRegionProvider.notifier).set(picked.code);
      },
    );
  }
}

/// This year's public holidays for the default country.
class _PublicHolidays extends ConsumerWidget {
  const _PublicHolidays({required this.country, required this.dates});

  final String? country;
  final DateLabels dates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (country == null) {
      return _Note(tr('holidays.noCountryBody'));
    }

    final int year = ref.watch(spaceClockProvider).today().year;
    final AsyncValue<ResolvedCalendar> refresh = ref.watch(
      resolvedCalendarProvider,
    );

    final AsyncValue<_YearHolidays> loaded = ref.watch(
      _yearHolidaysProvider((country: country!, year: year)),
    );
    if (refresh.isLoading || !loaded.hasValue) return const _Note('…');

    final List<CalendarDate>? days = loaded.value!.days;
    final Map<CalendarDate, List<String>> names = loaded.value!.names;
    if (days == null || days.isEmpty) {
      // Empty: a year beyond the bundle, not downloaded.
      final ResolvedCalendar? resolved = refresh.value;
      final bool blocked =
          resolved != null &&
          resolved.missingYears.contains(year) &&
          !(ref.watch(holidayConsentProvider) ?? false);
      return _Note(
        tr(blocked ? 'holidays.needsDownload' : 'holidays.notLoaded'),
      );
    }
    return Column(
      children: <Widget>[
        for (final CalendarDate day in days)
          ListTile(
            dense: true,
            leading: Icon(
              Icons.event_busy_outlined,
              size: 20,
              color: context.sage.inkLabel,
            ),
            // English name, then the local one where different.
            title: Text(names[day]?.firstOrNull ?? tr('calendar.holiday')),
            subtitle: Text(
              <String>[
                ...?names[day]?.skip(1),
                '${dates.short(day)} · ${dates.weekday(day)}',
              ].join('\n'),
            ),
          ),
      ],
    );
  }
}

/// User-marked days, each with a delete.
class _CustomDays extends ConsumerWidget {
  const _CustomDays();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<CustomNonWorkingDay> days =
        ref.watch(customNonWorkingDaysProvider).value ??
        const <CustomNonWorkingDay>[];
    if (days.isEmpty) return _Note(tr('holidays.noCustomDays'));

    final DateLabels dates = DateLabels(context.locale.toString());
    return Column(
      children: <Widget>[
        for (final CustomNonWorkingDay day in days)
          ListTile(
            dense: true,
            leading: Icon(
              Icons.event_busy,
              size: 20,
              color: context.sage.accentStrong,
            ),
            title: Text(day.title ?? dates.short(day.date)),
            subtitle: Text(
              day.title == null
                  ? dates.weekday(day.date)
                  : '${dates.short(day.date)} · ${dates.weekday(day.date)}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: tr('common.delete'),
              onPressed: () async {
                await ref.read(repositoriesProvider).customDays.remove(day.id);
                ref.invalidate(periodRefreshProvider);
              },
            ),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: SageSpace.gutter,
      vertical: SageSpace.sm,
    ),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

/// Null code is the "no country" choice.
@immutable
class _CountryResult {
  const _CountryResult(this.code);

  final String? code;
}

class _CountryPicker extends ConsumerStatefulWidget {
  const _CountryPicker();

  @override
  ConsumerState<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends ConsumerState<_CountryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final List<HolidayCountry> all =
        ref
            .watch(holidayCountriesProvider(context.locale.languageCode))
            .value ??
        const <HolidayCountry>[];
    final String query = _query.trim().toLowerCase();
    final List<HolidayCountry> shown = query.isEmpty
        ? all
        : all
              .where(
                (HolidayCountry c) =>
                    c.name.toLowerCase().contains(query) ||
                    c.code.toLowerCase().contains(query),
              )
              .toList();

    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SageSpace.gutter,
          0,
          SageSpace.gutter,
          SageSpace.md + keyboard,
        ),
        child: SizedBox(
          height: (MediaQuery.sizeOf(context).height - keyboard) * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                tr('holidays.country'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: SageSpace.md),
              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: tr('holidays.searchCountry'),
                  isDense: true,
                ),
                onChanged: (String value) => setState(() => _query = value),
              ),
              const SizedBox(height: SageSpace.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('holidays.noCountry')),
                subtitle: Text(tr('holidays.noCountryBody')),
                onTap: () =>
                    Navigator.of(context).pop(const _CountryResult(null)),
              ),
              const Hairline(),
              Expanded(
                child: ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int index) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(shown[index].name),
                    trailing: Text(
                      shown[index].code,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    onTap: () =>
                        Navigator.of(context)
                            .pop(_CountryResult(shown[index].code)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
