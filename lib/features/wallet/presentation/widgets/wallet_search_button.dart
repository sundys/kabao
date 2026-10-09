import 'package:flutter/material.dart';

import 'wallet_search_sheet.dart';

/// 右下角搜索入口与页面边缘的间距，首页与分类页保持一致。
const EdgeInsets walletSearchButtonMargin = EdgeInsets.only(
  right: 14,
  bottom: 18,
);

/// 右下角搜索入口，样式与首页一致。
///
/// [categoryId] 为空表示全局搜索；非空时搜索结果只包含该分类下的记录。
class WalletSearchButton extends StatelessWidget {
  const WalletSearchButton({super.key, this.categoryId});

  /// 非空时把搜索范围限定在该分类内。
  final String? categoryId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => WalletSearchSheet(categoryId: categoryId),
      ),
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.search, size: 30),
      ),
    );
  }
}
