import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Visible shell tab. Kept-alive tabs listen to it to close what they had open.
class ShellTabController extends Notifier<int> {
  static const int dashboard = 0;

  @override
  int build() => dashboard;

  void show(int index) => state = index;
}

final NotifierProvider<ShellTabController, int> shellTabProvider =
    NotifierProvider<ShellTabController, int>(ShellTabController.new);
