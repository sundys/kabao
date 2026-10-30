import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:kabao/features/notifications/data/notification_repository.dart';
import 'package:kabao/features/notifications/logic/reminders_service.dart';
import 'package:kabao/features/wallet/data/card_repository.dart';
import 'package:kabao/features/wallet/data/category_repository.dart';
import 'package:kabao/features/wallet/data/document_repository.dart';
import 'package:kabao/features/wallet/domain/document.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:kabao/shared/services/local_notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/recording_notification_gateway.dart';

/// 单记录重算：保存一张卡片后只重建这张卡片的提醒，既不能漏，也不能
/// 影响其它卡片已经挂好的系统闹钟。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late EncryptedDatabase db;
  late NotificationRepository notifications;
  late CardRepository cards;
  late CategoryRepository categories;
  late DocumentRepository documents;
  final dek = AeadCipher().generateKey(32);

  setUp(() async {
    final raw = await openDatabase(
      inMemoryDatabasePath,
      version: EncryptedDatabase.dbVersion,
      onCreate: (database, _) => EncryptedDatabase.createSchema(database),
    );
    await raw.execute('PRAGMA foreign_keys = ON');
    db = EncryptedDatabase.forTest(raw, AeadCipher())..attachKey(dek);
    notifications = NotificationRepository(db);
    cards = CardRepository(db);
    categories = CategoryRepository(db);
    documents = DocumentRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seedCategory(String id) => categories.save(
    BankCategory(
      id: id,
      cardType: CardType.credit,
      name: '工商银行',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  );

  Future<CardRecord> seedCard({
    required String id,
    required int expiryMonth,
    required int expiryYear,
  }) async {
    final card = CardRecord(
      id: id,
      categoryId: 'cat',
      cardType: CardType.credit,
      cardNumber: '6222000012345678',
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await cards.save(card);
    return card;
  }

  test('只重算指定卡片的提醒，不重复也不遗漏', () async {
    await seedCategory('cat');
    await seedCard(id: 'card-a', expiryMonth: 8, expiryYear: 2027);
    await seedCard(id: 'card-b', expiryMonth: 9, expiryYear: 2027);
    final now = DateTime(2027, 6, 2);

    final all = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: now,
    );
    expect(
      all.every((n) => n.cardId == 'card-a' || n.cardId == 'card-b'),
      isTrue,
    );

    final scoped = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: now,
      onlyRecordId: 'card-a',
    );
    // 已经存在的档位不会重复插入。
    expect(scoped, isEmpty);
  });

  test('单记录重算会补上该记录缺失的档位，且不动其它记录', () async {
    await seedCategory('cat');
    await seedCard(id: 'card-a', expiryMonth: 8, expiryYear: 2027);
    await seedCard(id: 'card-b', expiryMonth: 9, expiryYear: 2027);
    final now = DateTime(2027, 6, 2);

    await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: now,
    );
    final beforeForB = (await notifications.listByCard(
      'card-b',
    )).map((n) => n.dedupeKey).toSet();

    // 模拟编辑 card-a 的日期后清空它的提醒快照。
    await notifications.purgeByCard('card-a');
    final recreated = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: now,
      onlyRecordId: 'card-a',
    );

    expect(recreated, isNotEmpty);
    expect(recreated.every((n) => n.cardId == 'card-a'), isTrue);
    expect(
      (await notifications.listByCard(
        'card-b',
      )).map((n) => n.dedupeKey).toSet(),
      beforeForB,
    );
  });

  test('单记录重算不会为其它卡片生成提醒', () async {
    await seedCategory('cat');
    await seedCard(id: 'card-a', expiryMonth: 8, expiryYear: 2027);
    await seedCard(id: 'card-b', expiryMonth: 9, expiryYear: 2027);

    final created = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      // 2027-08-01 距 card-b 的 2027-09-30 截止日 60 天，落在提醒窗口内。
      now: DateTime(2027, 8, 1),
      onlyRecordId: 'card-b',
    );

    expect(created, isNotEmpty);
    expect(created.every((n) => n.cardId == 'card-b'), isTrue);
    expect(await notifications.listByCard('card-a'), isEmpty);
  });

  test('单记录重算同样覆盖证件，且尊重用户已删除的提醒', () async {
    await seedCategory('cat');
    final doc = DocumentRecord(
      id: 'doc-1',
      categoryId: 'cat',
      holderName: '张三',
      idNumber: '110101199001011234',
      issuer: '公安局',
      validFrom: DateTime(2020),
      validTo: DateTime(2027, 9, 1),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await documents.save(doc);
    // 2027-08-01 距 2027-09-01 截止日 31 天，落在 60/30 天档内。
    final now = DateTime(2027, 8, 1);

    final first = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      documents: documents,
      now: now,
      onlyRecordId: 'doc-1',
    );
    expect(first, isNotEmpty);
    expect(first.every((n) => n.cardId == 'doc-1'), isTrue);

    // 用户删除其中一条后，单记录重算不能把它重新创建出来。
    await notifications.delete(first.first.id);
    await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      documents: documents,
      now: now,
      onlyRecordId: 'doc-1',
    );
    final active = await notifications.listActive(now: DateTime(2027, 9, 2));
    expect(
      active.map((n) => n.dedupeKey),
      isNot(contains(first.first.dedupeKey)),
    );
  });

  test('单记录重算只影响该记录的系统闹钟编排', () async {
    await seedCategory('cat');
    await seedCard(id: 'card-a', expiryMonth: 8, expiryYear: 2027);
    await seedCard(id: 'card-b', expiryMonth: 9, expiryYear: 2027);
    final gateway = RecordingGateway();
    final localNotifications = LocalNotificationService(gateway: gateway);
    await localNotifications.initialize();

    await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: DateTime(2027, 6, 2),
      localNotifications: localNotifications,
      onlyRecordId: 'card-a',
    );

    final expectedIds = (await notifications.listByCard(
      'card-a',
    )).map((n) => LocalNotificationService.stableShadeId(n.dedupeKey)).toSet();
    expect(gateway.scheduled.map((c) => c.id).toSet(), expectedIds);
  });
}
