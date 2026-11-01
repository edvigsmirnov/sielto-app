import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// The loader while [result] is null, [builder] once it is done, else the
/// failure with a retry for a network one.
class CloudBody extends StatelessWidget {
  const CloudBody({
    required this.result,
    required this.onRetry,
    required this.builder,
    super.key,
  });

  final CloudResult? result;
  final VoidCallback onRetry;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => switch (result) {
    null => const Center(child: LeafLoader()),
    CloudResult.done => builder(context),
    final CloudResult result => EmptyState(
      message: tr('storage.${result.name}'),
      action: result == CloudResult.noNetwork
          ? FilledButton(
              onPressed: onRetry,
              child: Text(tr('devices.tryAgain')),
            )
          : null,
    ),
  };
}
