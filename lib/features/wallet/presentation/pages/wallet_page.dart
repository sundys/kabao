import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../widgets/capsule_search_bar.dart';
import '../widgets/category_list_view.dart';
import '../widgets/frosted_search_overlay.dart';
import '../widgets/wallet_search_sheet.dart';

/// 分类页：从首页仿真卡进入的固定类型页面。
/// 顶部为返回键 + 限定本类型的胶囊搜索 + 新建分类；正文是该类型的分类列表。
/// 不再提供顶部滑动标签，三个类型各自对应独立页面。
class WalletTypePage extends ConsumerWidget {
  const WalletTypePage({super.key, this.cardType = CardType.debit});

  /// 固定展示的卡片类型。
  final CardType cardType;

  static String labelOf(CardType type) => switch (type) {
    CardType.debit => '借记卡',
    CardType.credit => '信用卡',
    CardType.document => '证件卡',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final label = labelOf(cardType);
    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Material(
              color: theme.colorScheme.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '返回',
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: CapsuleSearchBar(
                            keyId: 'type-page-search-bar',
                            hintText: '搜索$label',
                            onTap: () => showFrostedSearch(
                              context,
                              scope: walletSearchInType(cardType),
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('add-category-button'),
                          tooltip: '新建分类',
                          onPressed: () => CategoryListView.showCreateDialog(
                            context,
                            ref,
                            cardType,
                          ),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.colorScheme.onSurface.withValues(
                      alpha: theme.brightness == Brightness.dark ? .18 : .10,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CategoryListView(
                key: ValueKey(cardType),
                cardType: cardType,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
