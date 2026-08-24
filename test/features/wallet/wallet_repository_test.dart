import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:kabao/features/wallet/data/card_repository.dart';
import 'package:kabao/features/wallet/data/category_repository.dart';
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
  });

  tearDown(() => db.close());

  Future<BankCategory> seedCategory(CardType type, String name) async {
    final now = DateTime.now();
    final category = BankCategory(
      id: '${name.hashCode}-$type',
      cardType: type,
      name: name,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
    await categories.save(category);
    return category;
  }

  test('分类按类型过滤并按排序字段返回', () async {
    await seedCategory(CardType.debit, '工商银行');
    await seedCategory(CardType.credit, '招商银行');
    await seedCategory(CardType.debit, '建设银行');

    final debit = await categories.listByType(CardType.debit);
    expect(debit.map((c) => c.name), ['工商银行', '建设银行']);
    expect((await categories.listByType(CardType.credit)).length, 1);
  });

  test('分类名称加密落库，明文不可见', () async {
    await seedCategory(CardType.debit, '农业银行');
    final raw = await db.rawQuery('SELECT payload FROM categories');
    final bytes = Uint8List.fromList(raw.first['payload'] as List<int>);
    expect(String.fromCharCodes(bytes).contains('农业银行'), isFalse);
  });

  test('卡片保存后可按分类读回且字段完整', () async {
    final category = await seedCategory(CardType.credit, '招商银行');
    final now = DateTime.now();
    await cards.save(
      CardRecord(
        id: 'card-1',
        categoryId: category.id,
        cardType: CardType.credit,
        cardNumber: '6222000012345678',
        expiryMonth: 8,
        expiryYear: 2029,
        cvv: '123',
        uShieldExpiryDate: DateTime(2027, 3, 8),
        note: '工资卡\n备用',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final loaded = (await cards.listByCategory(category.id)).single;
    expect(loaded.cardNumber, '6222000012345678');
    expect(loaded.expiryMonth, 8);
    expect(loaded.expiryYear, 2029);
    expect(loaded.cvv, '123');
    expect(loaded.uShieldExpiryDate, DateTime(2027, 3, 8));
    expect(loaded.note, '工资卡\n备用');
  });

  test('删除分类前统计卡片数量', () async {
    final category = await seedCategory(CardType.debit, '交通银行');
    final now = DateTime.now();
    await cards.save(
      CardRecord(
        id: 'card-2',
        categoryId: category.id,
        cardType: CardType.debit,
        cardNumber: '1234567890',
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(await categories.countCardsInCategory(category.id), 1);
    // FK RESTRICT prevents deleting a non-empty category.
    await expectLater(categories.delete(category.id), throwsA(anything));
    await cards.delete('card-2');
    expect(await categories.delete(category.id), 1);
    expect(await categories.getById(category.id), isNull);
  });

  test('更新卡片不改变创建时间', () async {
    final category = await seedCategory(CardType.debit, '邮储银行');
    final created = DateTime(2026, 1, 1);
    await cards.save(
      CardRecord(
        id: 'card-3',
        categoryId: category.id,
        cardType: CardType.debit,
        cardNumber: '1111222233334',
        createdAt: created,
        updatedAt: created,
      ),
    );
    final existing = (await cards.listByCategory(category.id)).single;
    await cards.save(
      CardRecord(
        id: existing.id,
        categoryId: existing.categoryId,
        cardType: existing.cardType,
        cardNumber: '9999888877776',
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
      ),
    );
    final updated = (await cards.listByCategory(category.id)).single;
    expect(updated.cardNumber, '9999888877776');
    expect(updated.createdAt, created);
  });
}
