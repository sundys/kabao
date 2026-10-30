import 'package:flutter/material.dart';

/// 危险操作的确认按钮组：取消与确认各占一半宽度，中间留出间隔。
///
/// 直接把它们作为 [AlertDialog.actions] 会因为全局 FilledButton 主题里的
/// `minimumSize: Size.fromHeight(48)`（宽度无限）而触发 OverflowBar 换行，
/// 把「取消」挤到确认按钮上方。这里用显式的 Row 布局固定两个按钮的宽度。
class ConfirmDialogActions extends StatelessWidget {
  const ConfirmDialogActions({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
    this.cancelLabel = '取消',
    this.destructive = true,
    this.showConfirm = true,
  });

  /// 取消回调，通常为 `() => Navigator.of(context).pop(false)`。
  final VoidCallback onCancel;

  /// 确认回调，通常为 `() => Navigator.of(context).pop(true)`。
  final VoidCallback onConfirm;

  final String confirmLabel;
  final String cancelLabel;

  /// 确认按钮是否使用错误色（删除、清空等不可逆操作）。
  final bool destructive;

  /// 为 false 时只显示占满整行的取消按钮，用于当前操作不可执行的提示型对话框。
  final bool showConfirm;

  static const double _gap = 16;
  static const double _buttonHeight = 48;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cancel = OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(_buttonHeight),
      ),
      onPressed: onCancel,
      child: Text(cancelLabel),
    );
    if (!showConfirm) {
      return SizedBox(width: double.infinity, child: cancel);
    }
    return Row(
      children: [
        Expanded(child: cancel),
        const SizedBox(width: _gap),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(_buttonHeight),
              backgroundColor: destructive ? scheme.error : null,
              foregroundColor: destructive ? scheme.onError : null,
            ),
            onPressed: onConfirm,
            child: Text(confirmLabel),
          ),
        ),
      ],
    );
  }
}
