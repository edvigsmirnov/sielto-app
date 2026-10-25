import 'package:meta/meta.dart';
import 'package:sielto/domain/value/calendar_date.dart';

enum FreezeState {
  open,

  /// Freezes within [FreezeEvaluator.warningDays] days.
  closingSoon,

  /// Amount, date, paid status, type and deletion are read-only. Category and
  /// appended notes stay editable.
  frozen,
}

/// Computes the freeze state on demand; it is never stored. "Today" is in the
/// Space's timezone.
@immutable
class FreezeEvaluator {
  const FreezeEvaluator({this.freezeAfterDays = 14, this.warningDays = 2});

  /// Days after a period ends until it freezes.
  final int freezeAfterDays;

  /// Days of warning before that.
  final int warningDays;

  /// Null [endDate] never freezes. [unfrozenUntil] reopens the period until then.
  FreezeState evaluate({
    required CalendarDate? endDate,
    required CalendarDate today,
    required DateTime nowUtc,
    DateTime? unfrozenUntil,
  }) {
    if (endDate == null) return FreezeState.open;

    if (unfrozenUntil != null && nowUtc.isBefore(unfrozenUntil)) {
      return FreezeState.open;
    }

    final CalendarDate freezesOn = endDate.addDays(freezeAfterDays);
    if (freezesOn.isBefore(today)) return FreezeState.frozen;

    if (!freezesOn.addDays(-warningDays).isAfter(today)) {
      return FreezeState.closingSoon;
    }
    return FreezeState.open;
  }

  DateTime unfreezeExpiry(DateTime nowUtc) =>
      nowUtc.add(const Duration(hours: 48));

  /// Appends without changing the existing text, cut to [noteLimit].
  static String appendNote(String? existing, String addition, CalendarDate on) {
    if (existing != null && existing.length >= noteLimit) return existing;
    final String stamped = '[added ${on.toIso()}]: $addition';
    final String whole = existing == null || existing.trim().isEmpty
        ? stamped
        : '$existing\n---\n$stamped';
    if (whole.length <= noteLimit) return whole;
    final int end =
        noteLimit - (_isLead(whole.codeUnitAt(noteLimit - 1)) ? 1 : 0);
    return whole.substring(0, end);
  }

  static bool _isLead(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}

/// The longest note, in UTF-16 units; the server counts characters, never more.
const int noteLimit = 5000;
