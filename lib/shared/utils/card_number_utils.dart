/// Card number utilities. The canonical stored/copied form is digits-only;
/// grouping is presentation-only.
library;

final class CardNumberValidation {
  const CardNumberValidation._();

  /// Removes spaces and common separators; returns null when the remaining
  /// input contains non-digit characters or exceeds 19 digits.
  static String? normalize(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\s\-—–]'), '');
    if (cleaned.isEmpty) {
      return null;
    }
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
      return null;
    }
    if (cleaned.length > 19) {
      return null;
    }
    return cleaned;
  }

  /// Groups digits by 4; the last group may be shorter.
  static String groupForDisplay(String normalized) {
    final buffer = StringBuffer();
    for (var i = 0; i < normalized.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write(' ');
      }
      buffer.write(normalized[i]);
    }
    return buffer.toString();
  }

  /// Masked display like `6222 **** **** 5678`. Numbers shorter than 12
  /// digits reveal at most the last 4 digits.
  static String maskForList(String normalized) {
    final length = normalized.length;
    if (length < 8) {
      return '*' * length;
    }
    if (length < 12) {
      return '${'*' * (length - 4)} ${normalized.substring(length - 4)}';
    }
    final head = normalized.substring(0, 4);
    final tail = normalized.substring(length - 4);
    final middleGroups = ((length - 8) / 4).ceil();
    final maskedMiddle = List.generate(middleGroups, (_) => '****').join(' ');
    return '$head $maskedMiddle $tail';
  }
}
