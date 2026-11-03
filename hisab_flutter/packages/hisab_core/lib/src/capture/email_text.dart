/// The visible text of an alert email, for the extractor.
///
/// Shortcuts' Email trigger hands an automation the message body as a file,
/// and an alert email's body is usually HTML. The extractor reads at most
/// `max_len` (192) tokens, and a stylesheet alone spends them before the
/// amount, so markup has to go before the read. SMS and notification text is
/// never HTML and passes through untouched.
abstract final class EmailText {
  static final _looksLikeHtml = RegExp(
      r'<(html|head|body|div|table|tr|td|p|br|span|font)\b',
      caseSensitive: false);
  static final _blocks = RegExp(r'<(style|script|head)\b.*?</\1\s*>',
      caseSensitive: false, dotAll: true);
  static final _comments = RegExp(r'<!--.*?-->', dotAll: true);
  static final _tags = RegExp(r'<[^>]*>');
  static final _numericEntity = RegExp(r'&#(x?)([0-9a-fA-F]+);');
  static final _whitespace = RegExp(r'\s+');

  /// [text] unchanged unless it looks like HTML; otherwise its text with tags,
  /// styles and scripts removed, entities decoded and whitespace collapsed.
  static String plain(String text) {
    if (!_looksLikeHtml.hasMatch(text)) return text;
    var s = text
        .replaceAll(_blocks, ' ')
        .replaceAll(_comments, ' ')
        .replaceAll(_tags, ' ');
    s = s.replaceAllMapped(_numericEntity, (m) {
      final value = int.tryParse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16);
      return value == null ? m[0]! : String.fromCharCode(value);
    });
    // `&amp;` last, so "&amp;lt;" decodes to the text "&lt;", not to "<".
    for (final (entity, character) in const [
      ('&nbsp;', ' '),
      ('&lt;', '<'),
      ('&gt;', '>'),
      ('&quot;', '"'),
      ('&apos;', "'"),
      ('&amp;', '&'),
    ]) {
      s = s.replaceAll(RegExp(RegExp.escape(entity), caseSensitive: false),
          character);
    }
    return s.trim().split(_whitespace).where((w) => w.isNotEmpty).join(' ');
  }
}
