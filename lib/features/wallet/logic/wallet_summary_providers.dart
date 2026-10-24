import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/repositories_providers.dart';
import '../domain/models.dart';

/// 数据修订号：卡片/证件/分类任何变更后调用 [VaultRevision.bump]，
/// 驱动首页统计与待办刷新。比让每个页面各自轮询数据库更可控，
/// 也避免在异步流程中丢失失效信号。
final vaultRevisionProvider = NotifierProvider<VaultRevision, int>(
  VaultRevision.new,
);

/// 数据修订号控制器。
class VaultRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// 自增修订号，通知所有依赖方重新加载。
  void bump() => state++;
}

/// 按类型统计的记录数量。
typedef WalletTypeCounts = ({int debit, int credit, int document});

/// 首页三个圆形统计的数据源：借记卡/信用卡/证件卡各自的总张数。
/// 通过分类计数查询汇总，不解密任何卡片载荷。
final walletTypeCountsProvider = FutureProvider.autoDispose<WalletTypeCounts>((
  ref,
) async {
  ref.watch(vaultRevisionProvider);
  final categoryRepo = ref.watch(categoryRepositoryProvider);
  if (categoryRepo == null) {
    return (debit: 0, credit: 0, document: 0);
  }

  Future<int> countType(CardType type) async {
    var total = 0;
    for (final category in await categoryRepo.listByType(type)) {
      total += await categoryRepo.countCardsInCategory(category.id);
    }
    return total;
  }

  return (
    debit: await countType(CardType.debit),
    credit: await countType(CardType.credit),
    document: await countType(CardType.document),
  );
});

/// 信用卡总授信额度（元）：只汇总勾选“计入总额”的卡片额度。
/// 返回 null 表示当前没有任何有效额度数据。
final creditTotalLimitProvider = FutureProvider.autoDispose<int?>((ref) async {
  ref.watch(vaultRevisionProvider);
  final cardRepo = ref.watch(cardRepositoryProvider);
  if (cardRepo == null) {
    return null;
  }
  var total = 0;
  var hasAny = false;
  for (final card in await cardRepo.listByType(CardType.credit)) {
    final limit = card.creditLimit;
    if (limit != null && card.includeInTotal) {
      total += limit;
      hasAny = true;
    }
  }
  return hasAny ? total : null;
});
