import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/format/context_format.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// Start and end, each from the full date picker. Null when dismissed.
Future<(CalendarDate, CalendarDate)?> askDateRange(
  BuildContext context, {
  required CalendarDate from,
  required CalendarDate to,
}) => showDialog<(CalendarDate, CalendarDate)>(
  context: context,
  builder: (BuildContext _) => _RangeDialog(from: from, to: to),
);

class _RangeDialog extends StatefulWidget {
  const _RangeDialog({required this.from, required this.to});

  final CalendarDate from;
  final CalendarDate to;

  @override
  State<_RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<_RangeDialog> {
  late CalendarDate _from = widget.from;
  late CalendarDate _to = widget.to;

  /// The end never comes before the start.
  Future<void> _pick({required bool start}) async {
    final CalendarDate? picked = await pickDate(context, start ? _from : _to);
    if (picked == null) return;
    setState(() {
      if (start) {
        _from = picked;
        if (_to.isBefore(picked)) _to = picked;
      } else {
        _to = picked;
        if (picked.isBefore(_from)) _from = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DateLabels dates = context.dates;

    return SageDialog(
      title: tr('analytics.dates.title'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FieldLabel(tr('analytics.dates.from')),
          DateField(label: dates.full(_from), onTap: () => _pick(start: true)),
          const SizedBox(height: SageSpace.md),
          FieldLabel(tr('analytics.dates.to')),
          DateField(label: dates.full(_to), onTap: () => _pick(start: false)),
        ],
      ),
      actions: ChoiceGrid(
        choices: <(String, VoidCallback)>[
          (tr('common.cancel'), () => Navigator.of(context).pop()),
          (tr('common.show'), () => Navigator.of(context).pop((_from, _to))),
        ],
        primaryLast: true,
      ),
    );
  }
}
