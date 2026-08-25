import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/services/clipboard_service.dart';
import '../../../../shared/utils/card_number_utils.dart';
import '../../domain/models.dart';

/// 分类详情页中的银行卡片瓦片。
/// 标题：姓名（未填则卡号）；副标题：卡号、有效期、备注（同行，超 6 字截断）。
class CardTile extends ConsumerWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.categoryColor,
    this.onTap,
  });

  final CardRecord card;
  final Color categoryColor;

  /// 点击卡片（进入详情页），由调用方注入。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final masked = CardNumberValidation.maskForList(card.cardNumber);
    // 显示顺序：姓名 → 卡号 → 有效期（同行追加备注，超 6 字截断）。
    final hasName = card.holderName != null && card.holderName!.isNotEmpty;
    final expiryText = card.expiryMonth == null || card.expiryYear == null
        ? ''
        : '${card.expiryMonth.toString().padLeft(2, '0')}/'
              '${(card.expiryYear! % 100).toString().padLeft(2, '0')}';
    final remark = card.note ?? '';
    final remarkShort = remark.length > 6
        ? '${remark.substring(0, 6)}…'
        : remark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: categoryColor.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            leading: const Icon(Icons.credit_card),
            title: Text(
              hasName ? card.holderName! : masked,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            isThreeLine: true,
            subtitle: Text(
              buildSubtitle(
                showCardNumber: hasName,
                masked: masked,
                expiryText: expiryText,
                remarkShort: remarkShort,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: '复制卡号',
              onPressed: () => ClipboardService.copyCardNumber(
                context,
                ref,
                card.cardNumber,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 副标题：卡号（已填姓名时才重复显示）→ 有效期 → 备注（同行，超 6 字截断）。
  static String buildSubtitle({
    required bool showCardNumber,
    required String masked,
    required String expiryText,
    required String remarkShort,
  }) {
    final parts = <String>[];
    if (showCardNumber) {
      parts.add(masked);
    }
    if (expiryText.isNotEmpty) {
      parts.add('有效期 $expiryText');
    }
    if (remarkShort.isNotEmpty) {
      parts.add(remarkShort);
    }
    return parts.join(' ');
  }
}
