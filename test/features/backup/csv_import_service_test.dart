import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:kabao/features/backup/logic/csv_import_service.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late EncryptedDatabase db;
  setUp(() async {
    final raw = await openDatabase(
      inMemoryDatabasePath,
      version: EncryptedDatabase.dbVersion,
      onCreate: (database, _) => EncryptedDatabase.createSchema(database),
    );
    db = EncryptedDatabase.forTest(raw, AeadCipher())
      ..attachKey(AeadCipher().generateKey(32));
  });
  tearDown(() => db.close());

  test('银行卡 CSV 全量校验并解析分类和字段', () {
    final draft = CsvImportService(categories: const [], database: db).prepare(
      kind: CsvImportKind.cards,
      contents:
          'record_type,category_type,category_name,card_number,expiry,cvv,note\n'
          'card,debit,工商银行,6222 0000 0000 0000,08/29,123,"第一行\n第二行"\n',
    );
    expect(draft.isValid, isTrue);
    expect(draft.recordCount, 1);
    expect(draft.createdCategoryCount, 1);
    expect(draft.snapshot.cards.single.cardNumber, '6222000000000000');
    expect(draft.snapshot.cards.single.note, '第一行\n第二行');
  });

  test('中文模板表头和可选标记可直接导入', () {
    final draft = CsvImportService(categories: const [], database: db).prepare(
      kind: CsvImportKind.cards,
      contents:
          '记录类型（可选）,分类类型,分类名称,分类ID（可选）,记录ID（可选）,持有人姓名（可选）,卡号,有效期（可选）,CVV（可选）,U盾到期日（可选）,备注（可选）,创建时间（可选）,更新时间（可选）\n'
          ',借记卡,农业银行,,,,6222111111111111,,,,,,\n',
    );
    expect(draft.isValid, isTrue);
    expect(draft.snapshot.cards.single.cardType, CardType.debit);
    expect(draft.snapshot.cards.single.cardNumber, '6222111111111111');
  });

  test('证件 CSV 非长期有效必须有合法日期', () {
    final draft = CsvImportService(categories: const [], database: db).prepare(
      kind: CsvImportKind.documents,
      contents:
          'record_type,category_type,category_name,holder_name,id_number,issuer,valid_from,valid_to,validity_permanent,remark\n'
          'document,document,身份证,张三,110000000000000000,公安局,2030.01.01,2029.01.01,false,\n',
    );
    expect(draft.isValid, isFalse);
    expect(draft.errors.single.field, 'valid_from');
  });

  test('重复 ID 和错误列数均不允许导入', () {
    const csv =
        'record_type,category_type,category_name,card_number,id\n'
        'card,debit,工商银行,6222000000000000,550e8400-e29b-41d4-a716-446655440000\n'
        'card,debit,工商银行,6222000000000001,550e8400-e29b-41d4-a716-446655440000\n';
    final draft = CsvImportService(
      categories: const [],
      database: db,
    ).prepare(kind: CsvImportKind.cards, contents: csv);
    expect(draft.isValid, isFalse);
    expect(draft.errors.any((e) => e.field == 'id'), isTrue);
  });
}
