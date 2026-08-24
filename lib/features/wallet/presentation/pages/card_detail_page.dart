import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/services/clipboard_service.dart';
import '../../../../shared/utils/card_number_utils.dart';
import '../../domain/models.dart';
import '../../logic/cards_controller.dart';

class CardDetailPage extends ConsumerWidget {
  const CardDetailPage({super.key, required this.card});

  final CardRecord card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grouped = CardNumberValidation.groupForDisplay(card.cardNumber);
    final rows = <(String, String)>[
      if (card.holderName != null && card.holderName!.isNotEmpty)
        ('姓名', card.holderName!),
      ('卡号', grouped),
      if (card.expiryMonth != null && card.expiryYear != null)
        (
          '有效期',
          '${card.expiryMonth.toString().padLeft(2, '0')}/'
              '${(card.expiryYear! % 100).toString().padLeft(2, '0')}',
        ),
      if (card.cvv != null && card.cvv!.isNotEmpty) ('CVV', card.cvv!),
      if (card.uShieldExpiryDate != null)
        (
          'U 盾证书到期日',
          '${card.uShieldExpiryDate!.year}/'
              '${card.uShieldExpiryDate!.month.toString().padLeft(2, '0')}/'
              '${card.uShieldExpiryDate!.day.toString().padLeft(2, '0')}',
        ),
      if (card.note != null && card.note!.isNotEmpty) ('备注', card.note!),
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
              extra: (card: card, isNew: false),
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除卡片'),
        content: const Text('删除后无法恢复，确定删除这张卡片吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
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
