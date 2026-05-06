import 'package:flutter/material.dart';

enum AppSection {
  home('\u9996\u9875', Icons.home_rounded),
  calendar('\u65e5\u5386', Icons.calendar_month_rounded),
  campusMap('\u6821\u56ed\u5730\u56fe', Icons.map_rounded),
  reading('阅读', Icons.menu_book_rounded),
  analysis('\u5468\u5206\u6790', Icons.auto_awesome_rounded),
  persons('\u4eba\u7269\u5173\u7cfb', Icons.hub_rounded),
  history('\u5386\u53f2', Icons.library_books_rounded),
  settings('\u8bbe\u7f6e', Icons.settings_rounded);

  const AppSection(this.label, this.icon);

  final String label;
  final IconData icon;
}
