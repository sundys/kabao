import 'package:flutter/services.dart';

/// Keeps user input grouped every N digits while typing (card numbers);
/// the stored/copied value is normalized separately on save.
final class DigitGroupingFormatter extends TextInputFormatter {
  const DigitGroupingFormatter({this.groupSize = 4, this.maxDigits = 19});

  final int groupSize;
  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > maxDigits) {
      return oldValue;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % groupSize == 0) {
        buffer.write(' ');
      }
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Auto-inserts fixed separators at digit offsets while typing, e.g. groups
/// `[2, 2]` with `/` turns `0829` into `08/29`; groups `[4, 2, 2]` turns
/// `20270308` into `2027/03/08`. Backspace works naturally because the text
/// is always rebuilt from the digits only.
final class SeparatorAutoFormatter extends TextInputFormatter {
  const SeparatorAutoFormatter(this.groupSizes, this.separators);

  final List<int> groupSizes;
  final List<String> separators;

  int get _maxDigits => groupSizes.fold(0, (a, b) => a + b);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    if (digits.length > _maxDigits) {
      return oldValue;
    }
    final buffer = StringBuffer();
    var consumed = 0;
    for (var g = 0; g < groupSizes.length && consumed < digits.length; g++) {
      if (buffer.isNotEmpty) {
        buffer.write(separators[g - 1]);
      }
      final end = (consumed + groupSizes[g]).clamp(0, digits.length);
      buffer.write(digits.substring(consumed, end));
      consumed = end;
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
