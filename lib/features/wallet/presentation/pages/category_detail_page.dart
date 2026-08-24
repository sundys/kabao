import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/services/clipboard_service.dart';
import '../../../../shared/utils/card_number_utils.dart';
import '../../../../shared/utils/category_colors.dart';
import '../../domain/models.dart';
import '../../logic/cards_controller.dart';
import '../../logic/documents_controller.dart';
import '../../domain/document.dart';

/// Lists all cards of a category. Rows show masked grouped numbers with a
/// dedicated copy action; tapping the row opens the detail page.
/// Document categories (证件卡) list certificate documents instead.
class CategoryDetailPage extends ConsumerWidget {
  const CategoryDetailPage({super.key, required this.category});

  final BankCategory category;

  bool get _isDocumentCategory => category.cardType == CardType.document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_isDocumentCategory) {
      return _DocumentListView(category: category);
    }
    final cardsAsync = ref.watch(cardsProvider(category.id));
    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-card-${category.id}',
        onPressed: () async {
          final draft = await ref
              .read(cardsProvider(category.id).notifier)
              .createDraft(category.cardType);
          if (!context.mounted) {
            return;
          }
          await context.push<CardRecord?>(
            '/wallet/card/edit',
            extra: (card: draft, isNew: true),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('添加卡片'),
      ),
      body: cardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(child: Text('加载失败，请重试')),
        data: (cards) {
          if (cards.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.credit_card_off_outlined,
                    size: 72,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '还没有卡片，点击右下角添加',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _CardTile(
              card: cards[index],
              categoryColor: CategoryColors.forId(category.id),
            ),
          );
        },
      ),
    );
  }
}

class _DocumentListView extends ConsumerWidget {
  const _DocumentListView({required this.category});

  final BankCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsProvider(category.id));
    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-doc-${category.id}',
        onPressed: () async {
          final draft = await ref
              .read(documentsProvider(category.id).notifier)
              .createDraft();
          if (!context.mounted) {
            return;
          }
          await context.push(
            '/wallet/document/edit',
            extra: (document: draft, isNew: true),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('添加证件'),
      ),
      body: docsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('加载失败，请重试')),
        data: (docs) {
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 72,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '还没有证件，点击右下角添加',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _DocTile(
              document: docs[index],
              categoryColor: CategoryColors.forId(category.id),
            ),
          );
        },
      ),
    );
  }
}

class _DocTile extends ConsumerWidget {
  const _DocTile({required this.document, required this.categoryColor});

  final DocumentRecord document;
  final Color categoryColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String fmt(DateTime? d) => d == null
        ? ''
        : '${d.year}.${d.month.toString().padLeft(2, '0')}.'
              '${d.day.toString().padLeft(2, '0')}';
    final masked = CardNumberValidation.maskForList(document.idNumber);
    return Material(
      color: categoryColor.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push('/wallet/document/${document.id}', extra: document),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 6,
          ),
          leading: const Icon(Icons.badge_outlined),
          title: Text(
            document.holderName.isEmpty ? masked : document.holderName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          isThreeLine: document.holderName.isNotEmpty,
          subtitle: Text(
            document.holderName.isEmpty
                ? '${fmt(document.validFrom)} - ${fmt(document.validTo)}'
                : '$masked\n${fmt(document.validFrom)} - '
                      '${fmt(document.validTo)}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: '复制证件号',
            onPressed: () => ClipboardService.copyCardNumber(
              context,
              ref,
              document.idNumber,
            ),
          ),
        ),
      ),
    );
  }
}

class _CardTile extends ConsumerWidget {
  const _CardTile({required this.card, required this.categoryColor});

  final CardRecord card;
  final Color categoryColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final masked = CardNumberValidation.maskForList(card.cardNumber);
    // 显示顺序：姓名 → 卡号 → 有效期（排版与证件卡一致）。
    final hasName = card.holderName != null && card.holderName!.isNotEmpty;
    final expiryText = card.expiryMonth == null || card.expiryYear == null
        ? ''
        : '${card.expiryMonth.toString().padLeft(2, '0')}/'
              '${(card.expiryYear! % 100).toString().padLeft(2, '0')}';
    return Material(
      color: categoryColor.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/wallet/card/${card.id}', extra: card),
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
          isThreeLine: expiryText.isNotEmpty,
          subtitle: Text(
            hasName
                ? (expiryText.isEmpty ? masked : '$masked\n有效期 $expiryText')
                : (expiryText.isEmpty ? '' : '有效期 $expiryText'),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: '复制卡号',
            onPressed: () =>
                ClipboardService.copyCardNumber(context, ref, card.cardNumber),
          ),
        ),
      ),
    );
  }
}
