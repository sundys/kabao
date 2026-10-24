import 'package:flutter/material.dart';

/// 椭圆胶囊形搜索入口条。仅作为入口展示，点击后由调用方弹出
/// 磨砂背景的动态搜索层（首页全量搜索 / 类型页限定类型搜索）。
class CapsuleSearchBar extends StatelessWidget {
  const CapsuleSearchBar({
    super.key,
    required this.hintText,
    required this.onTap,
    this.keyId = 'capsule-search-bar',
  });

  final String hintText;
  final VoidCallback onTap;
  final String keyId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: '搜索',
      child: Material(
        color: isDark
            ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
            : theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          key: Key(keyId),
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hintText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
