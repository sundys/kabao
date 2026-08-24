import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';

import '../crypto/aead_cipher.dart';
import 'encrypted_record.dart';

/// SQLite database where every business record is stored as a single
/// authenticated-encrypted blob. Only non-sensitive metadata (UUID,
/// timestamps, record type) is kept in plaintext columns so lists can be
/// sorted without decryption keys.
final class EncryptedDatabase {
  EncryptedDatabase._(this._db, this._aead);

  /// Test-only constructor over an externally managed raw database.
  @visibleForTesting
  factory EncryptedDatabase.forTest(Database database, AeadCipher aead) =>
      EncryptedDatabase._(database, aead);

  static const int dbVersion = 1;

  final Database _db;
  final AeadCipher _aead;

  static Future<EncryptedDatabase> open(
    String path, {
    AeadCipher? aead,
    Future<Database> Function()? openDatabaseOverride,
  }) async {
    final db =
        await (openDatabaseOverride?.call() ??
            openDatabase(
              path,
              version: dbVersion,
              onConfigure: (database) async {
                await database.execute('PRAGMA foreign_keys = ON');
              },
              onCreate: (database, version) => createSchema(database),
            ));
    return EncryptedDatabase._(db, aead ?? AeadCipher());
  }

  /// Creates all vault tables. Exposed so tests can build the same schema
  /// against an in-memory database.
  static Future<void> createSchema(Database database) async {
    await database.execute('''
                  CREATE TABLE categories (
                    id TEXT PRIMARY KEY NOT NULL,
                    card_type TEXT NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    model_version INTEGER NOT NULL,
                    payload BLOB NOT NULL
                  )
                ''');
    await database.execute('''
                  CREATE TABLE cards (
                    id TEXT PRIMARY KEY NOT NULL,
                    category_id TEXT NOT NULL REFERENCES categories(id)
                      ON DELETE RESTRICT,
                    card_type TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    model_version INTEGER NOT NULL,
                    payload BLOB NOT NULL
                  )
                ''');
    await database.execute('''
                  CREATE TABLE notifications (
                    id TEXT PRIMARY KEY NOT NULL,
                    card_id TEXT,
                    dedupe_key TEXT NOT NULL UNIQUE,
                    read_at INTEGER,
                    deleted_at INTEGER,
                    created_at INTEGER NOT NULL,
                    scheduled_for INTEGER,
                    model_version INTEGER NOT NULL,
                    payload BLOB NOT NULL
                  )
                ''');
    await database.execute('''
                  CREATE INDEX idx_cards_category ON cards(category_id)
                ''');
    await database.execute('''
                  CREATE INDEX idx_notifications_dedupe
                  ON notifications(dedupe_key)
                ''');
  }

  Future<void> close() => _db.close();

  DatabaseExecutor get _exec => _txOverride ?? _db;

  DatabaseExecutor? _txOverride;
  bool _inTransaction = false;

  /// Runs [action] inside a database transaction; any error rolls back all
  /// writes, keeping imports atomic.
  Future<T> runInTransaction<T>(Future<T> Function() action) async {
    if (_inTransaction) {
      return action();
    }
    _inTransaction = true;
    try {
      return await _db.transaction((txn) async {
        _txOverride = txn;
        return action();
      });
    } finally {
      _txOverride = null;
      _inTransaction = false;
    }
  }

  Future<void> putRecord(String table, EncryptedRecord record) async {
    final key = await _requireKey();
    final payload = await _aead.encrypt(
      key,
      Uint8List.fromList(utf8.encode(record.json)),
    );
    await _exec.insert(table, {
      ...record.metadata.toRow(),
      'payload': payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns null when the record does not exist; throws
  /// [AeadDecryptionException] when the blob was tampered with or the key is
  /// wrong.
  Future<Uint8List?> getPayload(String table, String id) async {
    final key = await _requireKey();
    final rows = await _exec.query(
      table,
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final stored = rows.first['payload']! as List<int>;
    return _aead.decrypt(key, Uint8List.fromList(stored));
  }

  Future<List<EncryptedRecord>> listRecords(String table) async {
    final key = await _requireKey();
    final rows = await _exec.query(table);
    final records = <EncryptedRecord>[];
    for (final row in rows) {
      final payload = Uint8List.fromList(row['payload']! as List<int>);
      final json = utf8.decode(await _aead.decrypt(key, payload));
      records.add(EncryptedRecord.fromRow(row, json));
    }
    return records;
  }

  Future<int> deleteRecord(String table, String id) =>
      _exec.delete(table, where: 'id = ?', whereArgs: [id]);

  /// Generic metadata-level query (no decryption). Payload stays a blob.
  Future<List<Map<String, Object?>>> queryWhere(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) => _exec.query(
    table,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    orderBy: orderBy,
  );

  Future<void> insertRow(String table, Map<String, Object?> row) =>
      _exec.insert(table, row);

  Future<int> updateWhere(
    String table,
    Map<String, Object?> values, {
    required String where,
    List<Object?>? whereArgs,
  }) => _exec.update(table, values, where: where, whereArgs: whereArgs);

  Future<int> deleteWhere(String table, String where, List<Object?> args) =>
      _exec.delete(table, where: where, whereArgs: args);

  Future<int> countRecords(String table) async {
    final result = await _exec.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return result.first['c']! as int;
  }

  /// Count of rows matching a plaintext metadata condition.
  Future<int> countWhere(String table, String where, List<Object?> args) async {
    final result = await _exec.query(
      table,
      columns: ['COUNT(*) AS c'],
      where: where,
      whereArgs: args,
    );
    return result.first['c']! as int;
  }

  Future<List<String>> listIds(String table) async {
    final rows = await _exec.query(table, columns: ['id']);
    return rows.map((row) => row['id']! as String).toList();
  }

  /// Raw read-only query over metadata/ciphertext columns. Used by security
  /// regression tests to assert no plaintext is persisted.
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? args,
  ]) => _exec.rawQuery(sql, args);

  bool _keyAvailable = false;

  /// The DEK is supplied after authentication; before that no reads or writes
  /// of payloads are possible.
  void attachKey(Uint8List dek) {
    _dek = dek;
    _keyAvailable = true;
  }

  void detachKey() {
    if (_dek != null) {
      _dek!.fillRange(0, _dek!.length, 0);
    }
    _dek = null;
    _keyAvailable = false;
  }

  Uint8List? _dek;

  Future<Uint8List> _requireKey() async {
    final dek = _dek;
    if (!_keyAvailable || dek == null) {
      throw StateError('vault is locked: no data key attached');
    }
    return dek;
  }

  Future<void> destroyAllData() async {
    await _db.transaction((txn) async {
      await txn.delete('notifications');
      await txn.delete('cards');
      await txn.delete('categories');
    });
  }
}
