import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/utils/card_number_utils.dart';
import '../../../../shared/utils/category_colors.dart';
import '../../../../app/providers/repositories_providers.dart';
import '../../domain/models.dart';

enum WalletSearchKind { bankCard, document }

final class WalletSearchResult {
  const WalletSearchResult({
    required this.kind,
    required this.cardType,
    required this.recordId,
    required this.categoryId,
    required this.categoryName,
    required this.title,
    required this.maskedNumber,
    required this.routeValue,
  });

  final WalletSearchKind kind;
  final CardType cardType;
  final String recordId;
  final String categoryId;
  final String categoryName;
  final String title;
  final String maskedNumber;
  final Object routeValue;
}

final walletSearchResultsProvider =
    FutureProvider.autoDispose<List<WalletSearchResult>>((ref) async {
      final categoryRepository = ref.watch(categoryRepositoryProvider);
      final cardRepository = ref.watch(cardRepositoryProvider);
      final documentRepository = ref.watch(documentRepositoryProvider);
      if (categoryRepository == null ||
          cardRepository == null ||
          documentRepository == null) {
        return const [];
      }

      final categories = await categoryRepository.listAll();
      final categoryById = {
        for (final category in categories) category.id: category,
      };
      final cards = [
        ...await cardRepository.listByType(CardType.debit),
        ...await cardRepository.listByType(CardType.credit),
      ];
      final documents = await documentRepository.listAll();

      return [
        for (final card in cards)
          WalletSearchResult(
            kind: WalletSearchKind.bankCard,
            cardType: card.cardType,
            recordId: card.id,
            categoryId: card.categoryId,
            categoryName: categoryById[card.categoryId]?.name ?? '未分类',
            title: (card.holderName?.isNotEmpty ?? false)
                ? card.holderName!
                : categoryById[card.categoryId]?.name ?? '未命名卡片',
            maskedNumber: CardNumberValidation.maskForList(card.cardNumber),
            routeValue: card,
          ),
        for (final document in documents)
          WalletSearchResult(
            kind: WalletSearchKind.document,
            cardType: CardType.document,
            recordId: document.id,
            categoryId: document.categoryId,
            categoryName: categoryById[document.categoryId]?.name ?? '未分类',
            title: document.holderName.isEmpty
                ? categoryById[document.categoryId]?.name ?? '未命名证件'
                : document.holderName,
            maskedNumber: CardNumberValidation.maskForList(document.idNumber),
            routeValue: document,
          ),
      ];
    });

class WalletSearchSheet extends ConsumerStatefulWidget {
  const WalletSearchSheet({super.key});

  @override
  ConsumerState<WalletSearchSheet> createState() => _WalletSearchSheetState();
}

class _WalletSearchSheetState extends ConsumerState<WalletSearchSheet> {
  String _query = '';

  bool _matches(WalletSearchResult result) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return result.title.toLowerCase().contains(query) ||
        result.categoryName.toLowerCase().contains(query) ||
        result.maskedNumber.replaceAll(' ', '').contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(walletSearchResultsProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .76,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  key: const Key('wallet-search-field'),
                  autofocus: true,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: '搜索姓名、卡号或分类',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: resultsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(
                    child: Text('搜索数据加载失败', style: theme.textTheme.bodyMedium),
                  ),
                  data: (results) {
                    final visible = results.where(_matches).toList();
                    if (visible.isEmpty) {
                      return Center(
                        child: Text(
                          _query.trim().isEmpty ? '暂无记录' : '没有匹配的记录',
                          style: theme.textTheme.bodyMedium,
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final result = visible[index];
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          tileColor: CategoryColors.forId(
                            result.categoryId,
                          ).withValues(alpha: .30),
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
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
