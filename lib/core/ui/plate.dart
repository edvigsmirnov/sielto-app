import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// A closable note at the top of the Dashboard. With [onTap] it opens
/// something; [action] is a button beside the close one.
class Plate extends StatelessWidget {
  const Plate({
    required this.icon,
    required this.text,
    required this.onClose,
    this.onTap,
    this.action,
    this.closeTooltip,
    this.warning = false,
    super.key,
  });

  final IconData icon;
  final String text;
  final VoidCallback onClose;
  final VoidCallback? onTap;
  final Widget? action;
  final String? closeTooltip;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final Widget content = Container(
      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
      padding: const EdgeInsetsDirectional.fromSTEB(
        SageSpace.md,
        SageSpace.sm,
        SageSpace.xs,
        SageSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: warning ? sage.warning : sage.accent),
          const SizedBox(width: SageSpace.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: sage.inkLabel),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SageSpace.gutter,
        0,
        SageSpace.gutter,
        SageSpace.sm,
      ),
      child: Material(
        color: warning ? sage.warningTint : sage.accentTint,
        borderRadius: BorderRadius.circular(SageRadius.card),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: <Widget>[
            Expanded(
              child: onTap == null
                  ? Semantics(container: true, child: content)
                  : Semantics(
                      container: true,
                      button: true,
                      child: InkWell(onTap: onTap, child: content),
                    ),
            ),
            ?action,
            IconButton(
              tooltip: closeTooltip ?? tr('common.close'),
              icon: Icon(Icons.close, size: 18, color: sage.inkLabel),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
