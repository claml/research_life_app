import '../../core/models/app_models.dart';

enum NotesExportFormat {
  markdown('Markdown'),
  wordPlain('Word 纯文本');

  const NotesExportFormat(this.label);

  final String label;
}

class NotesExport {
  NotesExport._();

  static String build({
    required List<PdfNoteDocumentGroup> groups,
    required NotesExportFormat format,
  }) {
    return switch (format) {
      NotesExportFormat.markdown => _markdown(groups),
      NotesExportFormat.wordPlain => _wordPlain(groups),
    };
  }

  static String _markdown(List<PdfNoteDocumentGroup> groups) {
    final buffer = StringBuffer('# 我的阅读笔记\n\n');
    for (final group in groups) {
      buffer.writeln('## ${group.document.title}\n');
      for (final note in group.notes) {
        buffer.writeln('### 第 ${note.pageNumber} 页\n');
        buffer.writeln('> ${note.selectedText.replaceAll('\n', ' ')}\n');
        if (note.note?.isNotEmpty == true) {
          buffer.writeln('${note.note}\n');
        }
        if (note.hasLatex && note.latexContent != null) {
          buffer.writeln('```latex');
          buffer.writeln(note.latexContent);
          buffer.writeln('```\n');
        }
        buffer.writeln('---\n');
      }
    }
    return buffer.toString().trim();
  }

  static String _wordPlain(List<PdfNoteDocumentGroup> groups) {
    final buffer = StringBuffer('我的阅读笔记\n\n');
    for (final group in groups) {
      buffer.writeln(group.document.title);
      buffer.writeln('=' * group.document.title.length);
      for (final note in group.notes) {
        buffer.writeln('\n[第 ${note.pageNumber} 页]');
        buffer.writeln('摘录：${note.selectedText}');
        if (note.note?.isNotEmpty == true) {
          buffer.writeln('感悟：${note.note}');
        }
        if (note.hasLatex && note.latexContent != null) {
          buffer.writeln('公式（LaTeX，可在 Word 中粘贴）：');
          buffer.writeln(note.latexContent);
        }
        buffer.writeln();
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }
}
