import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/utils/category_colors.dart';
import '../../../../shared/validation/validators.dart';
import '../../../../shared/widgets/draggable_fab.dart';
import '../../domain/models.dart';
import '../../logic/categories_controller.dart';

class CategoryListView extends ConsumerWidget {
  const CategoryListView({super.key, required this.cardType});

  final CardType cardType;

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(switch (cardType) {
          CardType.debit => '新建借记卡分类',
          CardType.credit => '新建信用卡分类',
          CardType.document => '新建证件分类',
        }),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('category-name-field'),
            controller: controller,
            autofocus: true,
            maxLength: 10,
            validator: Validators.categoryName,
            decoration: const InputDecoration(
              labelText: '银行分类名称',
              hintText: '如：工商银行',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(controller.text);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) {
      return;
    }
    await ref.read(categoriesProvider(cardType).notifier).add(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider(cardType));
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          categoriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(child: Text('加载失败，请重试')),
            data: (categories) {
              if (categories.isEmpty) {
                return _EmptyPlaceholder(cardType: cardType);
              }
              return RefreshIndicator(
                onRefresh: () async =>
                    ref.refresh(categoriesProvider(cardType).future),
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.45,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return _CategoryTile(
                      category: category,
                      cardType: cardType,
                    );
                  },
                ),
              );
            },
          ),
          DraggableFab(
            key: ValueKey('create-category-${cardType.name}'),
            tooltip: '新建分类',
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category, required this.cardType});

  final BankCategory category;
  final CardType cardType;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final count = await ref
        .read(categoriesProvider(cardType).notifier)
        .cardCount(category.id);
    if (!context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除分类'),
        content: Text(
          count > 0
              ? '「${category.name}」下还有 $count 张卡片，请先删除或移动这些卡片。'
              : '确定删除「${category.name}」吗？此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          if (count == 0)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(categoriesProvider(cardType).notifier).delete(category.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final background = CategoryColors.forId(category.id);
    final ink = CategoryColors.foregroundFor(background);
    final cardCount = ref.watch(categoryCardCountProvider(category.id));
    final typeLabel = switch (cardType) {
      CardType.debit => '借记卡',
      CardType.credit => '信用卡',
      CardType.document => '证件卡',
    };
    final countLabel = cardCount.when(
      data: (count) => '共 $count 张卡片',
      loading: () => '共 0 张卡片',
      error: (_, _) => '共 0 张卡片',
    );
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push('/wallet/category/${category.id}', extra: category),
        onLongPress: () => _confirmDelete(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    switch (cardType) {
                      CardType.debit => Icons.account_balance_outlined,
                      CardType.credit => Icons.credit_card_outlined,
                      CardType.document => Icons.badge_outlined,
                    },
                    color: ink,
                    size: 23,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        height: 1.2,
                        color: ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: ink.withValues(alpha: 0.6),
                    size: 21,
                  ),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: ink.withValues(alpha: .72),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 14,
                    color: ink.withValues(alpha: .32),
                  ),
                  Expanded(
                    child: Text(
                      countLabel,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        color: ink.withValues(alpha: .72),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder({required this.cardType});

  final CardType cardType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            switch (cardType) {
              CardType.debit => Icons.account_balance_outlined,
              CardType.credit => Icons.credit_card_outlined,
              CardType.document => Icons.badge_outlined,
            },
            size: 72,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            switch (cardType) {
              CardType.debit => '还没有借记卡分类',
              CardType.credit => '还没有信用卡分类',
              CardType.document => '还没有证件分类',
            },
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '点击右下角按钮创建银行分类',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
