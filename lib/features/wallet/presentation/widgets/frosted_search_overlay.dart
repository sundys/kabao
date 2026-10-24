import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'wallet_search_sheet.dart';

/// 全屏磨砂背景的动态搜索层。
///
/// 背景使用高斯模糊 + 半透明遮罩（“透明磨砂”），输入关键词即时过滤；
/// 未输入时不加载任何记录，避免无输入时暴露卡片列表。
class FrostedSearchOverlay extends ConsumerStatefulWidget {
  const FrostedSearchOverlay({super.key, required this.scope});

  /// 搜索范围：首页全量 / 类型页限定类型。
  final WalletSearchScope scope;

  @override
  ConsumerState<FrostedSearchOverlay> createState() =>
      _FrostedSearchOverlayState();
}

class _FrostedSearchOverlayState extends ConsumerState<FrostedSearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  bool get _hasQuery => _query.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _matches(WalletSearchResult result) {
    final query = _query.trim().toLowerCase();
    return result.title.toLowerCase().contains(query) ||
        result.categoryName.toLowerCase().contains(query) ||
        result.maskedNumber.replaceAll(' ', '').contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resultsAsync = _hasQuery
        ? ref.watch(walletSearchResultsProvider(widget.scope))
        : null;
    return GestureDetector(
      // 点击空白区域关闭搜索层。
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            color: isDark
                ? Colors.black.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.45),
            child: SafeArea(
              child: GestureDetector(
                // 阻止点击内容区时冒泡关闭。
                onTap: () {},
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('wallet-search-field'),
                              controller: _controller,
                              autofocus: true,
                              onChanged: (value) =>
                                  setState(() => _query = value),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: '搜索姓名、卡号或分类',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _hasQuery
                                    ? IconButton(
                                        key: const Key('wallet-search-clear'),
                                        tooltip: '清除',
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          _controller.clear();
                                          setState(() => _query = '');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withValues(alpha: 0.10)
                                    : Colors.white.withValues(alpha: 0.75),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('取消'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: resultsAsync == null
                          ? Center(
                              child: Text(
                                '输入关键词搜索卡片或证件',
                                style: theme.textTheme.bodyMedium,
                              ),
                            )
                          : resultsAsync.when(
                              loading: () => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              error: (_, _) => Center(
                                child: Text(
                                  '搜索数据加载失败',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              data: (results) {
                                final visible = results
                                    .where(_matches)
                                    .toList();
                                if (visible.isEmpty) {
                                  return Center(
                                    child: Text(
                                      '没有匹配的记录',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  );
                                }
                                return ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    8,
                                    20,
                                    24,
                                  ),
                                  itemCount: visible.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) =>
                                      _resultTile(context, visible[index]),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultTile(BuildContext context, WalletSearchResult result) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 磨砂层内没有 Material 祖先，包一层透明 Material 让 tileColor/水波纹可见。
    return Material(
      color: Colors.transparent,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.72),
        leading: Icon(
          result.kind == WalletSearchKind.bankCard
              ? Icons.credit_card_outlined
              : Icons.badge_outlined,
        ),
        title: Text(
          result.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${result.categoryName} · ${result.maskedNumber}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          Navigator.of(context).pop();
          if (result.kind == WalletSearchKind.bankCard) {
            context.push(
              '/wallet/card/${result.recordId}',
              extra: result.routeValue,
            );
          } else {
            context.push(
              '/wallet/document/${result.recordId}',
              extra: result.routeValue,
            );
          }
        },
      ),
    );
  }
}

/// 弹出全屏磨砂搜索层。
void showFrostedSearch(
  BuildContext context, {
  required WalletSearchScope scope,
}) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) =>
          FrostedSearchOverlay(scope: scope),
      transitionsBuilder: (context, animation, animation2, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}
