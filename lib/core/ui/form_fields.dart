import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// The one span every record date picker offers. Null when dismissed.
Future<CalendarDate?> pickDate(
  BuildContext context,
  CalendarDate initial,
) async {
  final DateTime? picked = await showDatePicker(
    context: context,
    initialDate: initial.toUtcMidnight(),
    firstDate: DateTime.utc(initial.year - 10),
    lastDate: DateTime.utc(initial.year + 15),
  );
  return picked == null ? null : CalendarDate.fromDateTime(picked);
}

/// Digits, separators and spaces; parsing happens on save.
class MoneyField extends StatelessWidget {
  const MoneyField({
    required this.controller,
    required this.symbol,
    this.enabled = true,
    this.autofocus = false,
    this.hintText,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String symbol;
  final bool enabled;
  final bool autofocus;
  final String? hintText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    autofocus: autofocus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r'[\d.,\s]')),
    ],
    decoration: InputDecoration(suffixText: symbol, hintText: hintText),
    onSubmitted: onSubmitted,
  );
}

/// Tappable date field.
class DateField extends StatelessWidget {
  const DateField({
    required this.label,
    required this.onTap,
    this.warn = false,
    super.key,
  });

  final String label;

  /// Null when the period is frozen.
  final VoidCallback? onTap;

  final bool warn;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SageRadius.input),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: sage.card,
          borderRadius: BorderRadius.circular(SageRadius.input),
          border: Border.all(color: warn ? sage.warning : sage.border),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
            Icon(Icons.calendar_today_outlined, size: 18, color: sage.inkLabel),
          ],
        ),
      ),
    );
  }
}

/// Existing note and a field that appends to it.
class AppendNoteField extends StatelessWidget {
  const AppendNoteField({
    required this.existing,
    required this.controller,
    required this.notesLabel,
    super.key,
  });

  final String? existing;
  final TextEditingController controller;
  final String notesLabel;

  @override
  Widget build(BuildContext context) {
    final String? note = existing?.trim().isEmpty ?? true ? null : existing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (note != null) ...<Widget>[
          LabelledField(
            label: notesLabel,
            child: SageCard(
              child: Text(note, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
          const SizedBox(height: SageSpace.lg),
        ],
        LabelledField(
          label: tr('freeze.addNote'),
          child: TextField(
            controller: controller,
            maxLines: 3,
            maxLength: 5000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: tr('freeze.addNoteHint')),
          ),
        ),
      ],
    );
  }
}

/// Obscured text with a show/hide toggle.
class SecretField extends StatefulWidget {
  const SecretField({
    required this.controller,
    this.autofocus = false,
    this.errorText,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final bool autofocus;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    autofocus: widget.autofocus,
    obscureText: _hidden,
    autocorrect: false,
    enableSuggestions: false,
    onSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      errorText: widget.errorText,
      suffixIcon: IconButton(
        tooltip: tr(_hidden ? 'common.show' : 'common.hide'),
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}
