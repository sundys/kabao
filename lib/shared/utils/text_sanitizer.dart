/// Removes characters that are stored as content but render as nothing.
library;

final class TextSanitizer {
  const TextSanitizer._();

  /// NUL/C0 controls, soft hyphen, zero-width marks, separators, and BOM.
  static final RegExp _invisible = RegExp(
    '[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u00AD'
    '\\u200B-\\u200F\\u2028\\u2029\\uFEFF]',
  );

  static String? clean(String? value) {
    final cleaned = value?.replaceAll(_invisible, '').trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
