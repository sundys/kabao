import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/material.dart';

/// Best-effort clipboard helper. Only card numbers may ever be copied, and
/// the content is cleared again as soon as the app loses the foreground so
/// clipboard managers and previews see it for as short a time as possible.
abstract final class ClipboardService {
  static Future<void> copyCardNumber(
    BuildContext context,
    WidgetRef ref,
    String digitsOnly,
  ) async {
    await Clipboard.setData(ClipboardData(text: digitsOnly));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('卡号已复制')));
    }
  }

  /// Call from app lifecycle when leaving foreground.
  static Future<void> clear() async {
    await Clipboard.setData(const ClipboardData(text: ''));
  }
}
