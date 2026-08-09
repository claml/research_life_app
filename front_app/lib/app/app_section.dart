import 'package:flutter/material.dart';

enum AppSection {
  home('首页', Icons.home_rounded),
  calendar('日历', Icons.calendar_month_rounded),
  todos('待办', Icons.check_circle_outline_rounded),
  stats('统计', Icons.insights_rounded),
  search('搜索', Icons.search_rounded),
  campusMap('校园地图', Icons.map_rounded),
  reading('科研文献', Icons.menu_book_rounded),
  myNotes('我的笔记', Icons.sticky_note_2_rounded),
  myFiles('我的文件', Icons.folder_copy_rounded),
  documentView('文档查阅', Icons.description_outlined),
  pdfTools('PDF 操作', Icons.picture_as_pdf_rounded),
  agent('AI 助手', Icons.smart_toy_rounded),
  analysis('周分析', Icons.auto_awesome_rounded),
  persons('人物关系', Icons.hub_rounded),
  history('历史', Icons.library_books_rounded),
  settings('设置', Icons.settings_rounded);

  const AppSection(this.label, this.icon);

  final String label;
  final IconData icon;
}
