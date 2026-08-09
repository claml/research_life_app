import 'package:flutter/material.dart';

/// 工作区文件类型：驱动「我的文件」打开方式与 PDF 操作范围。
enum WorkspaceFileKind {
  pdf,
  text,
  presentation,
  image,
  office,
  other;

  bool get isPdf => this == WorkspaceFileKind.pdf;
  bool get isViewable => isText || isPresentation;
  bool get isText =>
      this == WorkspaceFileKind.text || this == WorkspaceFileKind.office;
  bool get isPresentation => this == WorkspaceFileKind.presentation;

  static WorkspaceFileKind fromPath(String path) {
    final ext = _extension(path);
    if (ext == 'pdf') {
      return WorkspaceFileKind.pdf;
    }
    if (_textExtensions.contains(ext)) {
      return WorkspaceFileKind.text;
    }
    if (ext == 'ppt' || ext == 'pptx') {
      return WorkspaceFileKind.presentation;
    }
    if (_imageExtensions.contains(ext)) {
      return WorkspaceFileKind.image;
    }
    if (_officeExtensions.contains(ext)) {
      return WorkspaceFileKind.office;
    }
    return WorkspaceFileKind.other;
  }

  static const _textExtensions = {
    'txt',
    'md',
    'markdown',
    'csv',
    'json',
    'xml',
    'log',
    'yaml',
    'yml',
    'rtf',
  };

  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'};

  static const _officeExtensions = {'doc', 'docx', 'xls', 'xlsx'};

  String get label => switch (this) {
    WorkspaceFileKind.pdf => 'PDF',
    WorkspaceFileKind.text => '文本',
    WorkspaceFileKind.presentation => '演示文稿',
    WorkspaceFileKind.image => '图片',
    WorkspaceFileKind.office => 'Office',
    WorkspaceFileKind.other => '其他',
  };

  IconData get icon => switch (this) {
    WorkspaceFileKind.pdf => Icons.picture_as_pdf_rounded,
    WorkspaceFileKind.text => Icons.description_outlined,
    WorkspaceFileKind.presentation => Icons.slideshow_outlined,
    WorkspaceFileKind.image => Icons.image_outlined,
    WorkspaceFileKind.office => Icons.article_outlined,
    WorkspaceFileKind.other => Icons.insert_drive_file_outlined,
  };

  static String? _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) {
      return null;
    }
    return path.substring(dot + 1).toLowerCase();
  }
}
