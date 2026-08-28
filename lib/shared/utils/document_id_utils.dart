/// 证件号展示与录入的分组规则。规范存储形式始终是纯数字，分组只用于显示，
/// 复制出去的永远是连续数字，避免二次录入时被空格干扰。
library;

final class DocumentIdFormatting {
  const DocumentIdFormatting._();

  /// 分组位数：前 6 位（地区码）、中间 8 位（出生日期）、其余归为一组。
  static const List<int> groupSizes = [6, 8, 6];

  /// 分组之间的分隔符。
  static const String separator = ' ';

  /// 去掉所有非数字字符，得到可入库的规范形式。
  static String normalize(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

  /// 按 6 / 8 / 其余分组，例如 `402356201202263038` →
  /// `402356 20120226 3038`。位数不足时只切出已有的部分。
  static String groupForDisplay(String raw) {
    final digits = normalize(raw);
    if (digits.isEmpty) {
      return '';
    }
    final parts = <String>[];
    var consumed = 0;
    for (final size in groupSizes) {
      if (consumed >= digits.length) {
        break;
      }
      final end = (consumed + size).clamp(0, digits.length);
      parts.add(digits.substring(consumed, end));
      consumed = end;
    }
    // 超出 groupSizes 总长度的尾巴（理论上不会出现，长度上限已卡在 20）
    // 仍然附加到最后，避免静默丢数字。
    if (consumed < digits.length) {
      parts.add(digits.substring(consumed));
    }
    return parts.join(separator);
  }
}
