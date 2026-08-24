import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/notifications/domain/reminder_rules.dart';
import 'package:kabao/features/wallet/domain/models.dart';

CardRecord card({String id = 'c1', int? month, int? year, DateTime? uShield}) {
  final now = DateTime(2026);
  return CardRecord(
    id: id,
    categoryId: 'cat',
    cardType: CardType.debit,
    cardNumber: '6222000012345678',
    expiryMonth: month,
    expiryYear: year,
    uShieldExpiryDate: uShield,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('有效期截止日规则', () {
    test('MM/YY 到期日为该月最后一天', () {
      expect(expiryDeadline(2029, 8), DateTime(2029, 8, 31));
      expect(expiryDeadline(2027, 2), DateTime(2027, 2, 28));
      expect(expiryDeadline(2028, 2), DateTime(2028, 2, 29)); // 闰年
      expect(expiryDeadline(2026, 12), DateTime(2026, 12, 31));
    });

    test('非法月份被拒绝', () {
      expect(() => expiryDeadline(2029, 0), throwsArgumentError);
      expect(() => expiryDeadline(2029, 13), throwsArgumentError);
    });
  });

  group('四档提醒生成（90/60/30/15 天）', () {
    test('距到期 90 天整时触发第 90 天档位', () {
      final deadline = DateTime(2027, 3, 31);
      final today = deadline.subtract(const Duration(days: 90));
      final plans = plansForCard(card(uShield: deadline), today);
      expect(plans.single.tier, 90);
      expect(plans.single.deadline, deadline);
    });

    test('距到期 45 天时已覆盖 90 与 60 档位', () {
      final deadline = DateTime(2027, 3, 31);
      final today = deadline.subtract(const Duration(days: 45));
      final plans = plansForCard(card(uShield: deadline), today);
      expect(plans.map((p) => p.tier).toSet(), {90, 60});
    });

    test('距到期 91 天时不产生任何提醒', () {
      final deadline = DateTime(2027, 3, 31);
      final today = deadline.subtract(const Duration(days: 91));
      expect(plansForCard(card(uShield: deadline), today), isEmpty);
    });

    test('卡片有效期在到期当天也生成提醒（当天档）', () {
      final c = card(month: 3, year: 2027);
      final today = DateTime(2027, 3, 31); // 到期当天（月末最后一天）
      final tiers = plansForCard(c, today)
          .where((p) => p.type == ReminderType.cardExpiry)
          .map((p) => p.tier)
          .toSet();
      expect(tiers.containsAll({90, 60, 30, 0}), isTrue);
    });

    test('每个档位的 dueAt 为到期日前 N 天', () {
      final deadline = DateTime(2027, 3, 31);
      final today = DateTime(2026, 12, 31); // 距离 90 天
      final plans = plansForCard(card(uShield: deadline), today);
      final tier90 = plans.singleWhere((p) => p.tier == 90);
      expect(tier90.dueAt, deadline.subtract(const Duration(days: 90)));
    });

    test('已过期的档位在宽限期内仍会生成，宽限期外不再生成', () {
      final deadline = DateTime(2026, 1, 1);
      // 过期 10 天：仍在 15 天宽限内 → 全部档位补齐
      final withinGrace = deadline.add(const Duration(days: 10));
      expect(
        plansForCard(card(uShield: deadline), withinGrace).map((p) => p.tier),
        {15, 30, 60, 90},
      );
      // 过期 16 天：超出宽限 → 无提醒
      final beyondGrace = deadline.add(const Duration(days: 16));
      expect(plansForCard(card(uShield: deadline), beyondGrace), isEmpty);
    });

    test('去重键按 卡片+类型+档位 唯一', () {
      final deadline = DateTime(2027, 3, 31);
      final today = deadline.subtract(const Duration(days: 45));
      final a = plansForCard(card(id: 'A', uShield: deadline), today);
      final b = plansForCard(card(id: 'B', uShield: deadline), today);
      expect(a.map((p) => p.tier).toSet(), {90, 60});
      final keys = a.map((p) => p.dedupeKey).toSet();
      expect(keys.length, 2);
      expect(keys.intersection(b.map((p) => p.dedupeKey).toSet()), isEmpty);
    });
  });

  group('卡片有效期与 U 盾日期独立提醒', () {
    test('两个来源各自生成提醒，去重键不同', () {
      // 有效期 08/27 → 截止 2027/8/31；U 盾同一天
      final c = card(month: 8, year: 2027, uShield: DateTime(2027, 8, 31));
      final today = DateTime(2027, 6, 2); // 距截止 90 天
      final plans = plansForCard(c, today);
      expect(plans.length, 2);
      final expiryKeys = plans
          .where((p) => p.type == ReminderType.cardExpiry)
          .map((p) => p.dedupeKey)
          .toSet();
      final ushieldKeys = plans
          .where((p) => p.type == ReminderType.uShieldExpiry)
          .map((p) => p.dedupeKey)
          .toSet();
      expect(expiryKeys.length, 1);
      expect(ushieldKeys.length, 1);
      expect(expiryKeys.intersection(ushieldKeys), isEmpty);
    });

    test('缺少有效期或 U 盾日期时只对存在的来源提醒', () {
      final today = DateTime(2027, 6, 2);
      expect(plansForCard(card(), today), isEmpty);
      final onlyMonth = plansForCard(card(month: 8, year: 2027), today);
      expect(onlyMonthsCount(onlyMonth), 1);
    });
  });
}

int onlyMonthsCount(List<ReminderPlan> plans) =>
    plans.where((p) => p.type == ReminderType.cardExpiry).length;
