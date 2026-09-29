import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shell tab on screen. Tabs are kept alive, so one that is left can
/// listen here to tidy up what it had open.
class ShellTabController extends Notifier<int> {
  static const int dashboard = 0;

  @override
  int build() => dashboard;

  void show(int index) => state = index;
}

final NotifierProvider<ShellTabController, int> shellTabProvider =
    NotifierProvider<ShellTabController, int>(ShellTabController.new);
