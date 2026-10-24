import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../notifications/logic/todo_items.dart';
import '../../domain/models.dart';
import '../../logic/wallet_summary_providers.dart';
import '../widgets/capsule_search_bar.dart';
import '../widgets/frosted_search_overlay.dart';
import '../widgets/wallet_search_sheet.dart';

/// 新版首页：顶部胶囊搜索 → 三个圆形统计 → 三张仿真卡片 → 待办事项。
/// 右下角悬浮搜索入口已移除，搜索统一收敛到顶部胶囊。
class WalletHomePage extends ConsumerWidget {
  const WalletHomePage({super.key});

  static const _typeEntries = [
    (CardType.debit, '借记卡'),
    (CardType.credit, '信用卡'),
    (CardType.document, '证件卡'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: CapsuleSearchBar(
                hintText: '搜索卡片、证件或分类',
                onTap: () => showFrostedSearch(context, scope: walletSearchAll),
              ),
            ),
            const _TypeCountCircles(),
            const _SimulatedCards(),
            const _TodoSection(),
          ],
        ),
      ),
    );
  }
}

/// 三个圆形统计：中间加粗数字 + 下方类型名。圆的直径随屏幕宽度自适应。
class _TypeCountCircles extends ConsumerWidget {
  const _TypeCountCircles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final counts = ref.watch(walletTypeCountsProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    // 依据屏幕逻辑宽度自适应（覆盖不同 DPI/尺寸），并限制在小屏与大屏范围。
    final diameter = (screenWidth * 0.17).clamp(56.0, 88.0);
    final labels = {
      CardType.debit: counts.value?.debit ?? 0,
      CardType.credit: counts.value?.credit ?? 0,
      CardType.document: counts.value?.document ?? 0,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          for (final (type, label) in WalletHomePage._typeEntries)
            Expanded(
              child: _CountCircle(
                key: Key('count-circle-${type.name}'),
                label: label,
                count: labels[type]!,
                diameter: diameter,
                color: switch (type) {
                  CardType.debit => theme.colorScheme.primary,
                  CardType.credit => const Color(0xFFB08D57),
                  CardType.document => theme.colorScheme.tertiary,
                },
                onTap: () => context.push('/wallet/type/${type.name}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountCircle extends StatelessWidget {
  const _CountCircle({
    super.key,
    required this.label,
    required this.count,
    required this.diameter,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final double diameter;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$label $count 张',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(diameter / 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                  border: Border.all(
                    color: color.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontSize: diameter * 0.34,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 三张可左右滑动的仿真卡片 + 顶部圆点指示器。
class _SimulatedCards extends ConsumerStatefulWidget {
  const _SimulatedCards();

  @override
  ConsumerState<_SimulatedCards> createState() => _SimulatedCardsState();
}

class _SimulatedCardsState extends ConsumerState<_SimulatedCards> {
  final PageController _controller = PageController(viewportFraction: 0.86);
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(walletTypeCountsProvider).value;
    final creditTotal = ref.watch(creditTotalLimitProvider).value;
    return Column(
      children: [
        const SizedBox(height: 8),
        _DotIndicator(count: 3, index: _index),
        SizedBox(
          height: 196,
          child: PageView.builder(
            controller: _controller,
            itemCount: 3,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final (type, label) = WalletHomePage._typeEntries[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _SimulatedCard(
                  key: Key('simulated-card-${type.name}'),
                  type: type,
                  label: label,
                  count: switch (type) {
                    CardType.debit => counts?.debit ?? 0,
                    CardType.credit => counts?.credit ?? 0,
                    CardType.document => counts?.document ?? 0,
                  },
                  creditTotal: creditTotal,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 圆点指示器：当前页为拉长的胶囊。
class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == index ? 18 : 6,
            height: 5,
            decoration: BoxDecoration(
              color: i == index
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    );
  }
}

/// 单张仿真卡：借记/信用为纯黑配色 + 芯片与银联标识；证件为 id 背景。
class _SimulatedCard extends StatelessWidget {
  const _SimulatedCard({
    super.key,
    required this.type,
    required this.label,
    required this.count,
    this.creditTotal,
  });

  final CardType type;
  final String label;
  final int count;
  final int? creditTotal;

  String _formatAmount(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );

  @override
  Widget build(BuildContext context) {
    final isDocument = type == CardType.document;
    return Semantics(
      button: true,
      label: '$label，共 $count 张，点击查看分类',
      child: Material(
        color: isDocument ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/wallet/type/${type.name}'),
          child: Container(
            height: 188,
            decoration: isDocument
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1C1C1F), Color(0xFF0A0A0C)],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isDocument)
                  Image.asset(
                    'assets/icon/id.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF2A3B4D)),
                  ),
                // 证件背景上的轻微暗化，保证文字可读。
                if (isDocument)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.30),
                          Colors.black.withValues(alpha: 0.05),
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$count 张',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (type == CardType.credit) ...[
                        Text(
                          '总授信额度',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          creditTotal == null
                              ? '¥ --'
                              : '¥ ${_formatAmount(creditTotal!)}',
                          style: const TextStyle(
                            color: Color(0xFFE7C989),
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        children: [
                          if (!isDocument)
                            Image.asset(
                              'assets/icon/chp.png',
                              width: 42,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox(width: 42, height: 32),
                            ),
                          const Spacer(),
                          if (!isDocument)
                            Image.asset(
                              'assets/icon/unionpay.png',
                              height: 22,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox(width: 56, height: 22),
                            ),
                        ],
                      ),
                    ],
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

/// 待办事项：三种卡片的到期/即将到期提醒。
class _TodoSection extends ConsumerWidget {
  const _TodoSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final todosAsync = ref.watch(todoItemsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '待办提醒',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              todosAsync.maybeWhen(
                data: (todos) => todos.isEmpty
                    ? const SizedBox.shrink()
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${todos.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          todosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('待办加载失败，请重试'),
            data: (todos) {
              if (todos.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      '暂无到期事项，一切正常',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final todo in todos.take(8)) _TodoTile(todo: todo),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({required this.todo});

  final TodoItem todo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = todo.expired || todo.daysLeft <= 15;
    final chipColor = todo.expired
        ? theme.colorScheme.error
        : todo.daysLeft <= 15
        ? const Color(0xFFE08E2B)
        : theme.colorScheme.primary;
    final dateText =
        '${todo.deadline.year}/'
        '${todo.deadline.month.toString().padLeft(2, '0')}/'
        '${todo.deadline.day.toString().padLeft(2, '0')}';
    final daysText = todo.expired
        ? '已过期 ${-todo.daysLeft} 天'
        : todo.daysLeft == 0
        ? '今天到期'
        : '剩余 ${todo.daysLeft} 天';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.onSurface.withValues(
          alpha: danger ? 0.06 : 0.04,
        ),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(
            todo.routeLocation,
            extra: todo.card ?? todo.document,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: chipColor.withValues(alpha: 0.14),
                  ),
                  child: Icon(
                    todo.card == null
                        ? Icons.badge_outlined
                        : todo.kindLabel.contains('U盾')
                        ? Icons.security_outlined
                        : Icons.schedule_outlined,
                    size: 18,
                    color: chipColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${todo.subject} · ${todo.kindLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${todo.maskedTail} · $dateText 到期',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    daysText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: chipColor,
                      fontWeight: FontWeight.w700,
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
