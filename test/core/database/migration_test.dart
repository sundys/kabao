import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v1 → v2 迁移：cards 表增加 sort_order 列且默认值为 0', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (database, _) async {
        // 模拟 v1 的 cards 表（无 sort_order 列）。
        await database.execute('''
          CREATE TABLE cards (
            id TEXT PRIMARY KEY NOT NULL,
            category_id TEXT NOT NULL,
            card_type TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            model_version INTEGER NOT NULL,
            payload BLOB NOT NULL
          )
        ''');
        await database.execute('''
          INSERT INTO cards (id, category_id, card_type, created_at,
            updated_at, model_version, payload)
          VALUES ('c1', 'cat', 'debit', 1, 1, 1, x'00')
        ''');
      },
    );

    await EncryptedDatabase.migrate(db, 1, 2);

    final columns = await db.rawQuery('PRAGMA table_info(cards)');
    expect(columns.any((c) => c['name'] == 'sort_order'), isTrue);
    final row = await db.query('cards', where: 'id = ?', whereArgs: ['c1']);
    expect(row.first['sort_order'], 0);
    await db.close();
  });

  test('新建库直接包含 sort_order 列', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: EncryptedDatabase.dbVersion,
      onCreate: (database, _) => EncryptedDatabase.createSchema(database),
    );
    final columns = await db.rawQuery("PRAGMA table_info(cards)");
    expect(columns.any((c) => c['name'] == 'sort_order'), isTrue);
    await db.close();
  });
}
