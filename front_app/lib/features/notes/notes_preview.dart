/// 将 Markdown 源码剥离符号，得到适合卡片/预览展示的纯文本。
String stripMarkdownForPreview(String markdown) {
  return markdown
      .replaceAll(RegExp(r'[#*_`>\[\]()!\-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
