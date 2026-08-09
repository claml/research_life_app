import 'package:flutter/services.dart';

import '../../core/models/app_models.dart';

/// Heuristics for PDF text selections that look like LaTeX / math.
class ReadingLatexUtils {
  ReadingLatexUtils._();

  static final _latexCommand = RegExp(
    r'\\(?:frac|sum|int|sqrt|alpha|beta|gamma|delta|theta|lambda|mu|pi|sigma|omega|left|right|begin|end|text|mathbf|mathrm)\b',
  );
  static final _dollarWrapped = RegExp(r'\$[^$\n]+\$|\$\$[^$]+\$\$');
  static final _unicodeMath = RegExp(r'[∑∫√∞≤≥≠±×÷α-ωΑ-Ω]');

  static bool looksLikeLatex(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (_dollarWrapped.hasMatch(trimmed)) {
      return true;
    }
    if (_latexCommand.hasMatch(trimmed)) {
      return true;
    }
    if (_unicodeMath.hasMatch(trimmed)) {
      return true;
    }
    final backslashCount = '\\'.allMatches(trimmed).length;
    return backslashCount >= 2;
  }

  static String normalizeLatex(String text) {
    var value = text.trim();
    if (value.startsWith(r'$$') && value.endsWith(r'$$') && value.length > 4) {
      value = value.substring(2, value.length - 2).trim();
    } else if (value.startsWith(r'$') &&
        value.endsWith(r'$') &&
        value.length > 2) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  /// Word 365+ can paste LaTeX when wrapped as display math.
  static String wordPastePayload(String latex) {
    final body = normalizeLatex(latex);
    return r'$$'
        '\n$body\n'
        r'$$';
  }

  static Future<void> copyForWord(String latex) {
    return Clipboard.setData(ClipboardData(text: wordPastePayload(latex)));
  }

  static PdfAnnotationContentType resolveContentType({
    required String selectedText,
    String? reflection,
  }) {
    final selectionIsLatex = looksLikeLatex(selectedText);
    final reflectionIsLatex =
        reflection != null &&
        reflection.trim().isNotEmpty &&
        looksLikeLatex(reflection);
    if (selectionIsLatex && reflectionIsLatex) {
      return PdfAnnotationContentType.mixed;
    }
    if (selectionIsLatex) {
      return PdfAnnotationContentType.latex;
    }
    if (reflectionIsLatex) {
      return PdfAnnotationContentType.mixed;
    }
    return PdfAnnotationContentType.text;
  }

  static String? latexToStore({
    required String selectedText,
    String? reflection,
    required PdfAnnotationContentType contentType,
  }) {
    switch (contentType) {
      case PdfAnnotationContentType.latex:
        return normalizeLatex(selectedText);
      case PdfAnnotationContentType.mixed:
        final parts = <String>[
          if (looksLikeLatex(selectedText)) normalizeLatex(selectedText),
          if (reflection != null &&
              reflection.trim().isNotEmpty &&
              looksLikeLatex(reflection))
            normalizeLatex(reflection),
        ];
        if (parts.isEmpty) {
          return looksLikeLatex(selectedText)
              ? normalizeLatex(selectedText)
              : null;
        }
        return parts.join('\n\n');
      case PdfAnnotationContentType.text:
        return null;
    }
  }
}
