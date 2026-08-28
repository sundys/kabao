import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/core/crypto/kdf_service.dart';
import 'package:kabao/features/backup/logic/backup_codec.dart';
import 'package:kabao/features/wallet/domain/document.dart';
import 'package:kabao/features/wallet/domain/models.dart';

const _fastKdf = KdfParams(
  iterations: 1,
  memoryKiB: 1024,
  parallelism: 1,
  hashLength: 32,
);

VaultSnapshot sampleSnapshot() {
  final now = DateTime.fromMillisecondsSinceEpoch(1756000000000);
  return VaultSnapshot(
    categories: [
      BankCategory(
        id: 'cat-1',
        cardType: CardType.credit,
        name: '工商银行',
        sortOrder: 2,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    cards: [
      CardRecord(
        id: 'card-1',
        categoryId: 'cat-1',
        cardType: CardType.credit,
        cardNumber: '6222000012345678',
        expiryMonth: 8,
        expiryYear: 2029,
        cvv: '123',
        uShieldExpiryDate: DateTime(2027, 3, 8),
        note: '工资卡\n备注行',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    documents: [
      DocumentRecord(
        id: 'doc-1',
        categoryId: 'cat-1',
        holderName: '张三',
        idNumber: '402356201202263038',
        issuer: '中南县公安局',
        validityIsPermanent: true,
        remark: '长期有效',
        createdAt: now,
        updatedAt: now,
      ),
      DocumentRecord(
        id: 'doc-2',
        categoryId: 'cat-1',
        holderName: '李四',
        idNumber: '402356201202263039',
        issuer: '中南县公安局',
        validFrom: DateTime(2022, 2, 25),
        validTo: DateTime(2038, 2, 25),
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

Future<String> encodeFast(VaultSnapshot snapshot, String password) =>
    BackupCodec.encode(
      snapshot: snapshot,
      password: password,
      now: DateTime.fromMillisecondsSinceEpoch(1756000000000),
      kdfParams: _fastKdf,
    );

void main() {
  test('编码后可解密还原全部字段', () async {
    final original = sampleSnapshot();
    final contents = await encodeFast(original, 'backup-pass-1');

    final restored = await BackupCodec.decrypt(
      contents: contents,
      password: 'backup-pass-1',
    );

    expect(restored.categories.single.name, '工商银行');
    expect(restored.categories.single.sortOrder, 2);
    final card = restored.cards.single;
    expect(card.cardNumber, '6222000012345678');
    expect(card.expiryMonth, 8);
    expect(card.expiryYear, 2029);
    expect(card.cvv, '123');
    expect(card.uShieldExpiryDate, DateTime(2027, 3, 8));
    expect(card.note, '工资卡\n备注行');

    // 证件：长期有效标记与中文字段往返无损，也不被解析成乱码。
    final permanent = restored.documents.firstWhere((d) => d.id == 'doc-1');
    expect(permanent.validityIsPermanent, isTrue);
    expect(permanent.validityLabel, '长期有效');
    expect(permanent.validFrom, isNull);
    expect(permanent.validTo, isNull);
    expect(permanent.holderName, '张三');
    expect(permanent.issuer, '中南县公安局');
    expect(permanent.idNumber, '402356201202263038');

    final dated = restored.documents.firstWhere((d) => d.id == 'doc-2');
    expect(dated.validityIsPermanent, isFalse);
    expect(dated.validFrom, DateTime(2022, 2, 25));
    expect(dated.validTo, DateTime(2038, 2, 25));
  });

  test('密文中不含明文卡号或分类名', () async {
    final contents = await encodeFast(sampleSnapshot(), 'backup-pass-1');
    expect(contents.contains('6222000012345678'), isFalse);
    expect(contents.contains('工商银行'), isFalse);
  });

  test('错误密码认证失败', () async {
    final contents = await encodeFast(sampleSnapshot(), 'right-password');
    expect(
      () => BackupCodec.decrypt(contents: contents, password: 'wrong-password'),
      throwsA(
        const BackupCodecException(BackupCodecError.authenticationFailed),
      ),
    );
  });

  test('密文被篡改时认证失败', () async {
    var contents = await encodeFast(sampleSnapshot(), 'some-password');
    // Flip a character inside the data blob.
    final marker = '"data": "';
    final start = contents.indexOf(marker) + marker.length;
    final replacement = contents.codeUnitAt(start) == 'A'.codeUnitAt(0)
        ? 'B'
        : 'A';
    contents = contents.replaceRange(start, start + 1, replacement);
    expect(
      () => BackupCodec.decrypt(contents: contents, password: 'some-password'),
      throwsA(anything),
    );
  });

  test('格式标签错误被拒绝', () async {
    const bad = '{"format":"other-app","version":1,"data":"","salt":""}';
    expect(
      () => BackupCodec.readMetadata(bad),
      throwsA(const BackupCodecException(BackupCodecError.unsupportedFormat)),
    );
  });

  test('更高版本号被拒绝（向前不兼容保护）', () async {
    const future =
        '{"format":"kabao-backup","version":99,"createdAt":1,'
        '"cipher":"aes-256-gcm","kdf":{},"salt":"AA==","data":"AA=="}';
    expect(
      () => BackupCodec.readMetadata(future),
      throwsA(const BackupCodecException(BackupCodecError.unsupportedVersion)),
    );
  });

  test('非 JSON 内容被拒绝', () {
    expect(
      () => BackupCodec.readMetadata('not json at all'),
      throwsA(const BackupCodecException(BackupCodecError.malformed)),
    );
  });

  test('元数据可读取且不含解密', () async {
    final contents = await encodeFast(sampleSnapshot(), 'pw-12345678');
    final meta = BackupCodec.readMetadata(contents);
    expect(meta.version, backupFormatVersion);
    expect(meta.createdAt, DateTime.fromMillisecondsSinceEpoch(1756000000000));
    expect(meta.kdf.iterations, _fastKdf.iterations);
  });
}
