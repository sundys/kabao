import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:kabao/features/backup/logic/backup_codec.dart';
import 'package:kabao/features/backup/logic/backup_service.dart';
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
  });

  tearDown(() => db.close());

  final t0 = DateTime.fromMillisecondsSinceEpoch(1000000000000);
  final t1 = DateTime.fromMillisecondsSinceEpoch(2000000000000);

  BankCategory cat(String id, String name, DateTime updated) => BankCategory(
    id: id,
    cardType: CardType.debit,
    name: name,
    createdAt: t0,
    updatedAt: updated,
  );

  CardRecord card(String id, String categoryId, String number, DateTime up) =>
      CardRecord(
        id: id,
        categoryId: categoryId,
        cardType: CardType.debit,
        cardNumber: number,
        createdAt: t0,
        updatedAt: up,
      );

  test('空库导入：全部计为新增', () async {
    final service = BackupService(database: db);
    final result = await service.importMerge(
      VaultSnapshot(
        categories: [cat('a', '工商银行', t0)],
        cards: [card('c1', 'a', '6222000012345678', t0)],
      ),
    );
    expect(result.categoriesAdded, 1);
    expect(result.cardsAdded, 1);
    expect((await categories.listByType(CardType.debit)).single.id, 'a');
  });

  test('同 ID 冲突时保留更新时间较新者', () async {
    await categories.save(cat('a', '旧名称', t1)); // 本地较新
    final service = BackupService(database: db);
    final result = await service.importMerge(
      VaultSnapshot(
        categories: [
          cat('a', '备份里的新名', t0), // 备份较旧 → 不覆盖
          cat('b', '备份新增', t0),
        ],
        cards: const [],
      ),
    );
    expect(result.categoriesUpdated, 0);
    expect(result.categoriesAdded, 1);
    final names = (await categories.listByType(
      CardType.debit,
    )).map((c) => c.name).toSet();
    expect(names, {'旧名称', '备份新增'});
  });

  test('备份较新时覆盖本地', () async {
    await categories.save(cat('a', '本地旧名', t0));
    final service = BackupService(database: db);
    final result = await service.importMerge(
      VaultSnapshot(categories: [cat('a', '备份新名', t1)], cards: const []),
    );
    expect(result.categoriesUpdated, 1);
    expect((await categories.listByType(CardType.debit)).single.name, '备份新名');
  });

  test('合并不删除备份中缺失的记录', () async {
    await categories.save(cat('local-only', '只在本地', t0));
    final service = BackupService(database: db);
    await service.importMerge(
      VaultSnapshot(categories: [cat('b', '来自备份', t0)], cards: const []),
    );
    final ids = (await categories.listByType(
      CardType.debit,
    )).map((c) => c.id).toSet();
    expect(ids, {'local-only', 'b'});
  });
}
