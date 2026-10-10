import 'dart:io';

import 'package:flutter/services.dart';

/// The model on Android, the computer name on desktop; null if unknown.
Future<String?> deviceName() async {
  try {
    final String? name = Platform.isAndroid
        ? await const MethodChannel('sielto/window')
              .invokeMethod<String>('deviceName')
        : Platform.localHostname;
    final String? trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed;
  } on Exception {
    return null;
  }
}
