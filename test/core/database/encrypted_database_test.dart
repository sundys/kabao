import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:kabao/core/database/encrypted_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late EncryptedDatabase db;
  final aead = AeadCipher();
  final dek = aead.generateKey(32);

  Future<EncryptedDatabase> openInMemory() => EncryptedDatabase.open(
    'no-such-file.db',
    aead: AeadCipher(),
    openDatabaseOverride: () async => await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
            CREATE TABLE cards (
              id TEXT PRIMARY KEY NOT NULL,
              card_type TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              model_version INTEGER NOT NULL,
              payload BLOB NOT NULL
            )
          ''');
      },
    ),
  );

  setUp(() async {
    db = await openInMemory();
  });

  tearDown(() async {
    await db.close();
  });

  RecordMetadata meta(String id) => RecordMetadata(
    id: id,
    createdAt: 1000,
    updatedAt: 2000,
    modelVersion: 1,
    extra: {'card_type': 'debit'},
  );

  test('未认证（未附加密钥）时拒绝读写', () async {
    expect(() => db.getPayload('cards', 'a'), throwsA(isA<StateError>()));
    expect(
      () => db.putRecord(
        'cards',
        EncryptedRecord(metadata: meta('a'), json: '{}'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('附加密钥后加密写入并可读回', () async {
    db.attachKey(dek);
    const payloadJson = '{"cardNumber":"6222 0000 1234 5678"}';
    await db.putRecord(
      'cards',
      EncryptedRecord(metadata: meta('a'), json: payloadJson),
    );
    final read = await db.getPayload('cards', 'a');
    expect(read, isNotNull);
    expect(String.fromCharCodes(read!), payloadJson);
  });

  test('数据库中的落盘内容不包含明文卡号', () async {
    db.attachKey(dek);
    await db.putRecord(
      'cards',
      EncryptedRecord(
        metadata: meta('a'),
        json: '{"cardNumber":"6222000012345678"}',
      ),
    );
    final raw = await db.rawQuery('SELECT payload FROM cards');
    final bytes = Uint8List.fromList(raw.first['payload'] as List<int>);
    expect(String.fromCharCodes(bytes).contains('6222'), isFalse);
  });

  test('篡改密文后读取失败', () async {
    db.attachKey(dek);
    await db.putRecord(
      'cards',
      EncryptedRecord(metadata: meta('a'), json: '{"v":1}'),
    );
    // Detach and re-attach with a different key to simulate wrong key.
    db.detachKey();
    db.attachKey(aead.generateKey(32));
    expect(
      () => db.getPayload('cards', 'a'),
      throwsA(isA<AeadDecryptionException>()),
    );
  });

  test('删除记录后不可读', () async {
    db.attachKey(dek);
    await db.putRecord(
      'cards',
      EncryptedRecord(metadata: meta('a'), json: '{"v":1}'),
    );
    expect(await db.deleteRecord('cards', 'a'), 1);
    expect(await db.getPayload('cards', 'a'), isNull);
  });
}
