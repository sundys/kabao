import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:kabao/features/notifications/data/notification_repository.dart';
import 'package:kabao/features/notifications/domain/models.dart';
import 'package:kabao/features/notifications/domain/reminder_rules.dart';
import 'package:kabao/features/wallet/data/card_repository.dart';
import 'package:kabao/features/wallet/data/category_repository.dart';
import 'package:kabao/features/notifications/logic/reminders_service.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:kabao/shared/services/local_notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/recording_notification_gateway.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late EncryptedDatabase db;
  late NotificationRepository notifications;
  late CardRepository cards;
  late CategoryRepository categories;
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
  });

  tearDown(() => db.close());

  Future<CardRecord> seedCard() async {
    final now = DateTime.now();
    await categories.save(
      BankCategory(
        id: 'cat',
        cardType: CardType.credit,
        name: '工商银行',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final card = CardRecord(
      id: 'card-1',
      categoryId: 'cat',
      cardType: CardType.credit,
      cardNumber: '6222000012345678',
      expiryMonth: 8,
      expiryYear: 2027, // 截止 2027-08-31
      uShieldExpiryDate: DateTime(2027, 3, 8),
      createdAt: now,
      updatedAt: now,
    );
    await cards.save(card);
    return card;
  }

  test('插入后可读取且内容加密落库', () async {
    final n = AppNotification(
      id: 'n1',
      type: ReminderType.cardExpiry,
      cardId: 'card-1',
      dedupeKey: 'expiry:card-1:90',
      title: '卡片有效期提醒',
      body: '将于 2027/8/31 到期',
      createdAt: DateTime.now(),
    );
    expect(await notifications.insertIfAbsent(n), isTrue);
    final list = await notifications.listActive();
    expect(list.single.title, '卡片有效期提醒');
    expect(list.single.dedupeKey, 'expiry:card-1:90');

    // 明文不可见
    // 明文不可见
    final rows = await db.rawQuery(
      'SELECT payload FROM notifications WHERE id = ?',
      ['n1'],
    );
    final blob = String.fromCharCodes(rows.first['payload'] as List<int>);
    expect(blob.contains('到期'), isFalse);
  });

  test('相同去重键的重复插入被拒绝（幂等）', () async {
    AppNotification make(String id) => AppNotification(
      id: id,
      type: ReminderType.cardExpiry,
      cardId: 'card-1',
      dedupeKey: 'expiry:card-1:30',
      title: 't',
      body: 'b',
      createdAt: DateTime.now(),
    );
    expect(await notifications.insertIfAbsent(make('n1')), isTrue);
    expect(await notifications.insertIfAbsent(make('n2')), isFalse);
    expect((await notifications.listActive()).length, 1);
  });

  test('重算服务：首次生成、再次运行不重复', () async {
    final card = await seedCard();
    final now = DateTime(2027, 6, 2); // 距有效期 90 天，U 盾已过 15+ 天

    final first = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: now,
    );
    // 有效期 90 天档 1 条；U 盾 2027/3/8 距今 -86 天 → 超出宽限，不生成
    expect(first.length, 1);
    expect(first.single.type, ReminderType.cardExpiry);
    expect(first.first.body.contains('工商银行'), isTrue);
    expect(first.first.body.contains('**** 5678'), isTrue);

    final second = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: now,
    );
    expect(second, isEmpty);
    expect(
      (await notifications.listActive(now: DateTime(2027, 6, 2, 10))).length,
      1,
    );
    expect(card.cardNumber, '6222000012345678'); // sanity
  });

  test('标记已读与删除', () async {
    await notifications.insertIfAbsent(
      AppNotification(
        id: 'n1',
        type: ReminderType.uShieldExpiry,
        cardId: 'card-1',
        dedupeKey: 'ushield:card-1:60',
        title: 'U 盾证书提醒',
        body: 'body',
        createdAt: DateTime.now(),
      ),
    );
    await notifications.markRead('n1');
    var list = await notifications.listActive();
    expect(list.single.isRead, isTrue);

    await notifications.delete('n1');
    list = await notifications.listActive();
    expect(list, isEmpty);
    // Deletion retains the dedupe key so a later reminder recomputation does
    // not recreate the notification the user explicitly removed.
    expect(
      await notifications.existingDedupeKeys(),
      contains('ushield:card-1:60'),
    );
    expect(
      await notifications.deletedDedupeKeys(),
      contains('ushield:card-1:60'),
    );
  });

  test('未到期的定时提醒不提前显示在应用内通知中心', () async {
    await notifications.insertIfAbsent(
      AppNotification(
        id: 'future',
        type: ReminderType.cardExpiry,
        cardId: 'card-1',
        dedupeKey: 'expiry:card-1:90',
        title: 'future',
        body: 'future',
        createdAt: DateTime.now(),
        scheduledFor: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    expect(await notifications.listActive(), isEmpty);
  });

  test('重算会挂载未来系统提醒，并记录成功挂载状态', () async {
    final card = await seedCard();
    final gateway = RecordingGateway();
    final localNotifications = LocalNotificationService(gateway: gateway);
    await localNotifications.initialize();

    final created = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: DateTime(2026, 1, 1),
      localNotifications: localNotifications,
    );

    expect(created, hasLength(8));
    expect(gateway.shown, isEmpty);
    expect(gateway.scheduled, hasLength(8));
    for (final reminder in created) {
      expect(
        (await notifications.findByDedupeKey(
          reminder.dedupeKey,
        ))?.systemScheduledAt,
        isNotNull,
      );
    }
    expect(card.id, 'card-1');
  });

  test('已到提醒首次展示后记录状态，重复重算不会重复展示', () async {
    await seedCard();
    final gateway = RecordingGateway();
    final localNotifications = LocalNotificationService(gateway: gateway);
    await localNotifications.initialize();
    final now = DateTime(2027, 8, 1, 10);

    final first = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: now,
      localNotifications: localNotifications,
    );
    expect(first, hasLength(4));
    expect(gateway.shown, hasLength(3));
    expect(gateway.scheduled, hasLength(1));

    await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: now,
      localNotifications: localNotifications,
    );
    expect(gateway.shown, hasLength(3));
    expect(gateway.scheduled, hasLength(2));
  });

  test('系统通知权限恢复后，未成功展示的已到提醒会补发', () async {
    await seedCard();
    final gateway = RecordingGateway(permissionGranted: false);
    final localNotifications = LocalNotificationService(gateway: gateway);
    await localNotifications.initialize();
    final now = DateTime(2027, 8, 1, 10);

    await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: now,
      localNotifications: localNotifications,
    );
    expect(gateway.shown, isEmpty);

    gateway.enabled = true;
    await localNotifications.refreshPermission();
    await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: now,
      localNotifications: localNotifications,
    );
    expect(gateway.shown, hasLength(3));
  });

  test('已成功挂载的定时提醒到期后不会因恢复前台而重复展示', () async {
    await seedCard();
    final gateway = RecordingGateway();
    final localNotifications = LocalNotificationService(gateway: gateway);
    await localNotifications.initialize();
    final beforeDue = DateTime(2027, 8, 31, 8, 30);

    await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: beforeDue,
      localNotifications: localNotifications,
    );
    expect(gateway.scheduled, hasLength(1));
    expect(gateway.shown, hasLength(3));

    await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      now: DateTime(2027, 8, 31, 10),
      localNotifications: localNotifications,
    );
    expect(gateway.shown, hasLength(3));
  });
}
