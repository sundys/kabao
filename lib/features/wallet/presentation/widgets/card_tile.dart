import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/services/clipboard_service.dart';
import '../../../../shared/utils/card_number_utils.dart';
import '../../../../shared/utils/text_sanitizer.dart';
import '../../domain/models.dart';

/// 分类详情页中的银行卡片瓦片。
/// 三行布局：第一行姓名+卡种；第二行脱敏卡号；第三行有效期+备注。
/// 三行高度固定，保证不同内容的卡片行与列对齐；卡种、备注允许为空。
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

  static const double _lineHeight = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tileKey = GlobalKey();
    final theme = Theme.of(context);
    final masked = CardNumberValidation.maskForList(card.cardNumber);
    final holderName = TextSanitizer.clean(card.holderName);
    final cardKind = TextSanitizer.clean(card.cardKind);
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        key: tileKey,
        color: categoryColor.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 4, 8),
            child: Row(
              children: [
                if (dragIndex == null)
                  const Icon(Icons.credit_card)
                else
                  Tooltip(
                    message: '拖动排序',
                    child: ReorderableDragStartListener(
                      index: dragIndex!,
                      child: const Icon(Icons.credit_card),
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fixedLine(
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                holderName ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (holderName != null && cardKind != null)
                              const SizedBox(width: 8),
                            if (cardKind != null)
                              Flexible(
                                child: Text(
                                  cardKind,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: secondaryStyle,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _fixedLine(
                        Text(
                          masked,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      _fixedLine(
                        Text(
                          _thirdLine(card),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondaryStyle,
                        ),
                      ),
                    ],
                  ),
                ),
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

  /// 固定高度的行容器：空字段仍占一行，保证多张卡片三行对齐。
  static Widget _fixedLine(Widget child) => SizedBox(
    height: _lineHeight,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );

  /// 第三行内容：有效期（MM/YY）+ 备注。
  static String _thirdLine(CardRecord card) {
    final parts = <String>[];
    if (card.expiryMonth != null && card.expiryYear != null) {
      parts.add(
        '${card.expiryMonth.toString().padLeft(2, '0')}/'
        '${(card.expiryYear! % 100).toString().padLeft(2, '0')}',
      );
    }
    final note = TextSanitizer.clean(card.note);
    if (note != null) {
      parts.add(note);
    }
    return parts.join('  ');
  }
}
