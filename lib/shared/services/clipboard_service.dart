import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/material.dart';

/// Best-effort clipboard helper. Only card numbers may ever be copied, and
/// the content is cleared again as soon as the app loses the foreground so
/// clipboard managers and previews see it for as short a time as possible.
abstract final class ClipboardService {
  static OverlayEntry? _feedback;
  static Future<void> _showFeedback(BuildContext context) async {
    final overlay = Overlay.maybeOf(context);
    final render = context.findRenderObject();
    if (overlay == null || render is! RenderBox || !render.hasSize) return;
    _feedback?.remove();
    final topLeft = render.localToGlobal(
      Offset.zero,
      ancestor: overlay.context.findRenderObject(),
    );
    final center =
        topLeft + Offset(render.size.width / 2, render.size.height / 2);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: center.dx - 56,
        top: center.dy - 24,
        child: IgnorePointer(
          child: Material(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(24),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text('已复制', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
    _feedback = entry;
    overlay.insert(entry);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (identical(_feedback, entry)) {
      entry.remove();
      _feedback = null;
    }
  }

  static Future<void> copyCardNumber(
    BuildContext context,
    WidgetRef ref,
    String digitsOnly, {
    BuildContext? feedbackContext,
  }) async {
    await Clipboard.setData(ClipboardData(text: digitsOnly));
    if (context.mounted) {
      await _showFeedback(feedbackContext ?? context);
    }
  }

  /// Call from app lifecycle when leaving foreground.
  static Future<void> clear() async {
    await Clipboard.setData(const ClipboardData(text: ''));
  }
}
