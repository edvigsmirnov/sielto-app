import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// Asks when an income arrived, prefilled with the expected date. Null when
/// dismissed.
Future<CalendarDate?> askReceiptDate(
  BuildContext context, {
  required CalendarDate expected,
}) => showDialog<CalendarDate>(
  context: context,
  builder: (BuildContext context) => _ReceiptDialog(expected: expected),
);

class _ReceiptDialog extends StatefulWidget {
  const _ReceiptDialog({required this.expected});

  final CalendarDate expected;

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  late CalendarDate _actual = widget.expected;

  Future<void> _pick() async {
    final CalendarDate? picked = await pickDate(context, _actual);
    if (picked != null) setState(() => _actual = picked);
  }

  @override
  Widget build(BuildContext context) {
    final DateLabels dates = DateLabels(context.locale.toString());

    return SageDialog(
      title: tr('income.markReceived'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FieldLabel(tr('income.fieldActualDate')),
          DateField(label: dates.dayMonth(_actual), onTap: _pick),
          if (_actual != widget.expected) ...<Widget>[
            const SizedBox(height: SageSpace.sm),
            Text(
              tr('income.actualDateNote'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: ChoiceGrid(
        choices: <(String, VoidCallback)>[
          (tr('common.cancel'), () => Navigator.of(context).pop()),
          (tr('common.save'), () => Navigator.of(context).pop(_actual)),
        ],
        primaryLast: true,
      ),
    );
  }
}
