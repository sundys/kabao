import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:kabao/features/notifications/data/notification_repository.dart';
import 'package:kabao/features/notifications/domain/reminder_rules.dart';
import 'package:kabao/features/notifications/logic/reminders_service.dart';
import 'package:kabao/features/wallet/data/card_repository.dart';
import 'package:kabao/features/wallet/data/category_repository.dart';
import 'package:kabao/features/wallet/data/document_repository.dart';
import 'package:kabao/features/wallet/domain/document.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late EncryptedDatabase db;
  late CategoryRepository categories;
  late CardRepository cards;
  late DocumentRepository documents;
  late NotificationRepository notifications;
  final dek = AeadCipher().generateKey(32);

  setUp(() async {
    final raw = await openDatabase(
      inMemoryDatabasePath,
      version: EncryptedDatabase.dbVersion,
      onCreate: (database, _) => EncryptedDatabase.createSchema(database),
    );
    await raw.execute('PRAGMA foreign_keys = ON');
    db = EncryptedDatabase.forTest(raw, AeadCipher())..attachKey(dek);
    categories = CategoryRepository(db);
    cards = CardRepository(db);
    documents = DocumentRepository(db);
    notifications = NotificationRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seedDocument(DateTime validTo) async {
    final now = DateTime.now();
    await categories.save(
      BankCategory(
        id: 'doc-cat',
        cardType: CardType.document,
        name: '身份证',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await documents.save(
      DocumentRecord(
        id: 'doc-1',
        categoryId: 'doc-cat',
        holderName: '张三',
        idNumber: '421366198805123639',
        issuer: '中南县公安局',
        validFrom: DateTime(2016, 8, 8),
        validTo: validTo,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  group('证件提醒规则（90/60/30 三档）', () {
    test('距有效期限止 90 天触发第 90 天档位', () {
      final validTo = DateTime(2027, 8, 8);
      final today = validTo.subtract(const Duration(days: 90));
      final plans = plansForDocument('doc-1', validTo, today);
      expect(plans.single.tier, 90);
      expect(plans.single.type, ReminderType.documentExpiry);
      expect(plans.single.dedupeKey.startsWith('docexpiry:doc-1'), isTrue);
    });

    test('15 天档不存在（证件只有三档）', () {
      final validTo = DateTime(2027, 8, 8);
      final today = validTo.subtract(const Duration(days: 45));
      final tiers = plansForDocument(
        'doc-1',
        validTo,
        today,
      ).map((p) => p.tier).toSet();
      expect(tiers, {90, 60});
    });

    test('无有效期不生成提醒', () {
      expect(plansForDocument('doc-1', null, DateTime(2026)), isEmpty);
    });
  });

  test('证件仓储往返：加密落库且字段完整', () async {
    await seedDocument(DateTime(2036, 8, 8));
    final doc = (await documents.listAll()).single;
    expect(doc.idNumber, '421366198805123639');
    expect(doc.issuer, '中南县公安局');
    expect(doc.validFrom, DateTime(2016, 8, 8));
    expect(doc.validTo, DateTime(2036, 8, 8));

    // 银行卡仓储不得把证件误认为银行卡
    expect(await cards.listByType(CardType.debit), isEmpty);
    expect(await cards.listByType(CardType.credit), isEmpty);

    // 明文不可见
    final rows = await db.rawQuery('SELECT payload FROM cards');
    final blob = String.fromCharCodes(rows.first['payload'] as List<int>);
    expect(blob.contains('421366'), isFalse);
  });

  test('重算服务为证件生成通知（三档独立去重键）', () async {
    final validTo = DateTime(2027, 8, 8);
    await seedDocument(validTo);
    final now = validTo.subtract(const Duration(days: 45));
    // 距到期 45 天 → 已越过 90 与 60 档位

    final created = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      documents: documents,
      now: now,
    );
    expect(created.length, 2);
    expect(created.every((n) => n.type == ReminderType.documentExpiry), isTrue);
    expect(created.first.title, '证件有效期限提醒');
    expect(created.first.body.contains('身份证'), isTrue);
    expect(created.first.body.contains('**** 3639'), isTrue);

    // 幂等
    final again = await recomputeReminders(
      cards: cards,
      categories: categories,
      notifications: notifications,
      documents: documents,
      now: now,
    );
    expect(again, isEmpty);
    expect((await notifications.listActive(now: now)).length, 2);
  });
}
