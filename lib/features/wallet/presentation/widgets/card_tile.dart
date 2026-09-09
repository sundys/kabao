import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/services/clipboard_service.dart';
import '../../../../shared/utils/card_number_utils.dart';
import '../../../../shared/utils/text_sanitizer.dart';
import '../../domain/models.dart';

/// 分类详情页中的银行卡片瓦片。
/// 标题：姓名 + 备注（未填姓名则为卡号）；副标题：脱敏卡号。
class CardTile extends ConsumerWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.categoryColor,
    this.dragIndex,
    this.onTap,
  });

  final CardRecord card;
  final Color categoryColor;

  /// ReorderableListView 的拖动索引；设置后用左侧卡片图标作为拖动把手。
  final int? dragIndex;

  /// 点击卡片（进入详情页），由调用方注入。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tileKey = GlobalKey();
    final masked = CardNumberValidation.maskForList(card.cardNumber);
    // 两行布局可让长列表更紧凑；备注只作为辅助信息，避免撑高卡片。
    final holderName = TextSanitizer.clean(card.holderName);
    final hasName = holderName != null;
    final remark = TextSanitizer.clean(card.note) ?? '';
    final remarkShort = remark.length > 8 ? remark.substring(0, 8) : remark;
    final title = hasName
        ? (remarkShort.isEmpty ? holderName : '$holderName $remarkShort')
        : masked;
    final subtitle = buildSubtitle(showCardNumber: hasName, masked: masked);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        key: tileKey,
        color: categoryColor.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 4,
            ),
            visualDensity: VisualDensity.compact,
            leading: dragIndex == null
                ? const Icon(Icons.credit_card)
                : Tooltip(
                    message: '拖动排序',
                    child: ReorderableDragStartListener(
                      index: dragIndex!,
                      child: const Icon(Icons.credit_card),
                    ),
                  ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: '复制卡号',
                  onPressed: () => ClipboardService.copyCardNumber(
                    context,
                    ref,
                    card.cardNumber,
                    feedbackContext: tileKey.currentContext,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 副标题：已填姓名时显示脱敏卡号；未填姓名时标题已是卡号，不重复显示。
  static String buildSubtitle({
    required bool showCardNumber,
    required String masked,
  }) {
    return showCardNumber ? masked : '';
  }
}
