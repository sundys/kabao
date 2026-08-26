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

/// Auto-inserts separators while rejecting out-of-range date components.
///
/// Unlike [SeparatorAutoFormatter], this formatter can constrain completed
/// components (for example month 1-12 and day 1-31) and can require a prefix
/// for a component (for example a four-digit year beginning with `2`).
/// Partial components remain editable so the existing auto-slash behaviour is
/// preserved while typing and deleting.
final class BoundedSeparatorAutoFormatter extends TextInputFormatter {
  const BoundedSeparatorAutoFormatter(
    this.groupSizes,
    this.separators, {
    this.minValues = const <int?>[],
    this.maxValues = const <int?>[],
    this.requiredPrefixes = const <String?>[],
  });

  final List<int> groupSizes;
  final List<String> separators;
  final List<int?> minValues;
  final List<int?> maxValues;
  final List<String?> requiredPrefixes;

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
    if (digits.length > _maxDigits || !_componentsAreAllowed(digits)) {
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

  bool _componentsAreAllowed(String digits) {
    var offset = 0;
    for (var i = 0; i < groupSizes.length && offset < digits.length; i++) {
      final end = (offset + groupSizes[i]).clamp(0, digits.length);
      final component = digits.substring(offset, end);
      final requiredPrefix = i < requiredPrefixes.length
          ? requiredPrefixes[i]
          : null;
      if (requiredPrefix != null &&
          component.isNotEmpty &&
          !component.startsWith(requiredPrefix)) {
        return false;
      }

      final value = int.tryParse(component);
      final isComplete = component.length == groupSizes[i];
      final min = i < minValues.length ? minValues[i] : null;
      final max = i < maxValues.length ? maxValues[i] : null;
      if (value != null && isComplete) {
        if (min != null && value < min) {
          return false;
        }
        if (max != null && value > max) {
          return false;
        }
      }
      offset = end;
    }
    return true;
  }
}
