import 'dart:async';

import 'package:sielto/core/format/device_region.dart';

/// Formats follow the app language in tests, whatever the host's locale.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  DeviceRegion.locale = null;
  await testMain();
}
