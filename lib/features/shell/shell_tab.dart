import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Icon, selected icon and name key of each tab, in order.
const List<(IconData, IconData, String)> shellTabs =
    <(IconData, IconData, String)>[
      (Icons.donut_small_outlined, Icons.donut_small, 'nav.dashboard'),
      (Icons.list_alt_outlined, Icons.list_alt, 'nav.feed'),
      (Icons.calendar_month_outlined, Icons.calendar_month, 'nav.calendar'),
    ];

/// Visible shell tab. Kept-alive tabs listen to it to close what they had open.
class ShellTabController extends Notifier<int> {
  static const int dashboard = 0;
  static const int feed = 1;
  static const int calendar = 2;

  @override
  int build() => dashboard;

  void show(int index) => state = index;
}

final NotifierProvider<ShellTabController, int> shellTabProvider =
    NotifierProvider<ShellTabController, int>(ShellTabController.new);
