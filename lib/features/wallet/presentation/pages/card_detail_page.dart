import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/services/clipboard_service.dart';
import '../../../../shared/utils/card_number_utils.dart';
import '../../../../shared/utils/text_sanitizer.dart';
import '../../../../shared/widgets/confirm_dialog_actions.dart';
import '../../domain/models.dart';
import '../../logic/cards_controller.dart';

class CardDetailPage extends ConsumerWidget {
  const CardDetailPage({super.key, required this.card});

  /// 路由传入的初始快照（列表/搜索结果）。真正的展示数据来自
  /// [cardRecordProvider]，保存编辑后会重新读取，避免停留在旧值。
  final CardRecord card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 读取失败（例如卡片已被删除）时回退到路由快照，页面不至于空白。
    final current = ref.watch(cardRecordProvider(card.id)).value ?? card;
    final theme = Theme.of(context);
    final grouped = CardNumberValidation.groupForDisplay(current.cardNumber);
    final holderName = TextSanitizer.clean(current.holderName);
    final note = TextSanitizer.clean(current.note);
    final rows = <(String, String)>[
      if (holderName != null) ('姓名', holderName),
      if (TextSanitizer.clean(current.cardKind) != null)
        ('卡种', TextSanitizer.clean(current.cardKind)!),
      if (current.creditLimit != null)
        (
          '额度',
          '¥${_formatAmount(current.creditLimit!)}'
              '${current.includeInTotal ? '' : '（不计入总额）'}',
        ),
      ('卡号', grouped),
      if (current.expiryMonth != null && current.expiryYear != null)
        (
          '有效期',
          '${current.expiryMonth.toString().padLeft(2, '0')}/'
              '${(current.expiryYear! % 100).toString().padLeft(2, '0')}',
        ),
      if (current.cvv != null && current.cvv!.isNotEmpty) ('CVV', current.cvv!),
      if (current.uShieldExpiryDate != null)
        (
          'U 盾证书到期日',
          '${current.uShieldExpiryDate!.year}/'
              '${current.uShieldExpiryDate!.month.toString().padLeft(2, '0')}/'
              '${current.uShieldExpiryDate!.day.toString().padLeft(2, '0')}',
        ),
      if (note != null) ('备注', note),
    ];

    bool boldValue(String label) =>
        label == '姓名' || label == '卡号' || label == '有效期';

    return Scaffold(
      appBar: AppBar(
        title: const Text('卡片详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () => context.push(
              '/wallet/card/edit',
              extra: (card: current, isNew: false),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 选项名：加粗。
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SelectableText(
                      value,
                      // 姓名、卡号、有效期加粗显示；其余正常字号 +1。
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: boldValue(label)
                            ? FontWeight.w700
                            : FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (label == '卡号')
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_outlined),
                      tooltip: '复制卡号',
                      onPressed: () => ClipboardService.copyCardNumber(
                        context,
                        ref,
                        card.cardNumber,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除卡片'),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  /// 千位分隔，如 50000 → 50,000。
  static String _formatAmount(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除卡片'),
        content: const Text('删除后无法恢复，确定删除这张卡片吗？'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          ConfirmDialogActions(
            confirmLabel: '删除',
            onCancel: () => Navigator.of(dialogContext).pop(false),
            onConfirm: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final ok = await ref
        .read(cardsProvider(card.categoryId).notifier)
        .delete(card.id);
    if (ok && context.mounted) {
      context.pop();
    }
  }
}
