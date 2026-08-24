import 'package:characters/characters.dart';

import '../utils/card_number_utils.dart';

final class Validators {
  const Validators._();

  static final RegExp _chineseOnly = RegExp(r'^[\u4E00-\u9FFF]+$');

  /// Bank category name: 1-4 Chinese characters (grapheme clusters), no
  /// whitespace-only or non-Chinese input.
  static String? categoryName(String? raw) {
    if (raw == null) {
      return '请输入银行分类名称';
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '请输入银行分类名称';
    }
    if (!_chineseOnly.hasMatch(trimmed)) {
      return '只能包含中文字符';
    }
    final count = trimmed.characters.length;
    if (count > 4) {
      return '最多 4 个中文字符';
    }
    return null;
  }

  static String? cardNumber(String? raw) =>
      CardNumberValidation.normalize(raw ?? '') == null
      ? '仅支持数字，长度 1-19 位'
      : null;

  /// `MM/YY`, month 01-12.
  static String? expiry(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null; // optional field
    }
    final value = raw.trim();
    if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(value)) {
      return '格式应为 MM/YY';
    }
    final month = int.tryParse(value.substring(0, 2));
    if (month == null || month < 1 || month > 12) {
      return '月份应在 01-12 之间';
    }
    return null;
  }

  /// 3-4 digits, optional.
  static String? cvv(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final value = raw.trim();
    if (!RegExp(r'^\d{3,4}$').hasMatch(value)) {
      return 'CVV 应为 3-4 位数字';
    }
    return null;
  }

  /// `yyyy/M/d` real calendar date, optional.
  static String? uShieldDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final value = raw.trim();
    final match = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$').firstMatch(value);
    if (match == null) {
      return '格式应为 yyyy/M/d，例如 2027/3/8';
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final candidate = DateTime(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return '日期不存在，请检查';
    }
    return null;
  }

  /// `yyyy.MM.dd-yyyy.MM.dd`, both real dates, start ≤ end, all 16 digits
  /// present (the input formatter inserts the separators automatically).
  static String? documentValidityRange(String? raw) {
    final value = raw?.trim() ?? '';
    if (!RegExp(r'^\d{4}\.\d{2}\.\d{2}-\d{4}\.\d{2}\.\d{2}$').hasMatch(value)) {
      return '格式应为 yyyy.MM.dd-yyyy.MM.dd';
    }
    final parts = value.split('-');
    final from = _parseDotDate(parts[0]);
    final to = _parseDotDate(parts[1]);
    if (from == null || to == null) {
      return '日期不存在，请检查';
    }
    if (to.isBefore(from)) {
      return '结束日期不能早于开始日期';
    }
    return null;
  }

  static DateTime? _parseDotDate(String wire) {
    final p = wire.split('.');
    if (p.length != 3) {
      return null;
    }
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) {
      return null;
    }
    final candidate = DateTime(y, m, d);
    if (candidate.year != y || candidate.month != m || candidate.day != d) {
      return null;
    }
    return candidate;
  }

  static String? note(String? raw) {
    if (raw == null) {
      return null;
    }
    final count = raw.characters.length;
    if (count > CardRecordNoteLimit.max) {
      return '备注最多 ${CardRecordNoteLimit.max} 字';
    }
    return null;
  }
}

abstract final class CardRecordNoteLimit {
  static const int max = 500;
}
