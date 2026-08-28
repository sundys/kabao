import 'dart:convert';
import 'dart:typed_data';

import '../../../core/crypto/aead_cipher.dart';
import '../../../core/crypto/kdf_service.dart';
import '../../wallet/domain/document.dart';
import '../../wallet/domain/models.dart';

/// Errors raised while parsing or decrypting a backup. Never leak any
/// content of the file beyond the failure reason.
enum BackupCodecError {
  malformed,
  unsupportedFormat,
  unsupportedVersion,
  badKdfParams,
  authenticationFailed,
}

final class BackupCodecException implements Exception {
  const BackupCodecException(this.error);

  final BackupCodecError error;

  @override
  String toString() => 'BackupCodecException(${error.name})';
}

const String backupFormatTag = 'kabao-backup';
const int backupFormatVersion = 1;

/// Non-sensitive metadata of a backup, safe to display before decryption.
final class BackupMetadata {
  const BackupMetadata({
    required this.version,
    required this.createdAt,
    required this.kdf,
  });

  final int version;
  final DateTime createdAt;
  final KdfParams kdf;
}

/// The decrypted business content of a backup.
final class VaultSnapshot {
  const VaultSnapshot({
    required this.categories,
    required this.cards,
    this.documents = const [],
  });

  final List<BankCategory> categories;
  final List<CardRecord> cards;

  /// Certificate documents (added without breaking v1 readers: unknown JSON
  /// keys are ignored by older versions).
  final List<DocumentRecord> documents;
}

/// Pure encode/decode of the `kabao-backup` v1 container.
///
/// See docs/backup-format.md for the on-disk contract.
abstract final class BackupCodec {
  static Future<String> encode({
    required VaultSnapshot snapshot,
    required String password,
    required DateTime now,
    AeadCipher? aead,
    KdfService? kdf,
    KdfParams kdfParams = KdfParams.mobileDefault,
  }) async {
    final cipher = aead ?? AeadCipher();
    final deriver = kdf ?? KdfService();

    final salt = cipher.generateKey(16);
    final kek = deriver.deriveKey(password, salt, kdfParams);
    final plaintext = Uint8List.fromList(
      utf8.encode(jsonEncode(_snapshotToJson(snapshot))),
    );
    final data = await cipher.encrypt(kek, plaintext);

    return const JsonEncoder.withIndent('  ').convert({
      'format': backupFormatTag,
      'version': backupFormatVersion,
      'createdAt': now.millisecondsSinceEpoch,
      'cipher': 'aes-256-gcm',
      'kdf': {
        'algo': 'argon2id',
        'iterations': kdfParams.iterations,
        'memoryKiB': kdfParams.memoryKiB,
        'parallelism': kdfParams.parallelism,
        'hashLength': kdfParams.hashLength,
        'salt': base64Encode(salt),
      },
      'data': base64Encode(data),
    });
  }

  /// Parses the envelope and returns its non-sensitive metadata without
  /// touching the encrypted payload.
  static BackupMetadata readMetadata(String contents) {
    final envelope = _parseEnvelope(contents);
    return BackupMetadata(
      version: envelope.version,
      createdAt: envelope.createdAt,
      kdf: envelope.kdfParams,
    );
  }

  static Future<VaultSnapshot> decrypt({
    required String contents,
    required String password,
    AeadCipher? aead,
    KdfService? kdf,
  }) async {
    final cipher = aead ?? AeadCipher();
    final deriver = kdf ?? KdfService();
    final envelope = _parseEnvelope(contents);

    final salt = base64Decode(envelope.saltBase64);
    final kek = deriver.deriveKey(password, salt, envelope.kdfParams);
    final Uint8List data;
    try {
      data = Uint8List.fromList(base64Decode(envelope.dataBase64));
      final clear = await cipher.decrypt(kek, data);
      return _snapshotFromJson(
        jsonDecode(utf8.decode(clear)) as Map<String, Object?>,
      );
    } on AeadDecryptionException {
      throw const BackupCodecException(BackupCodecError.authenticationFailed);
    } on FormatException {
      throw const BackupCodecException(BackupCodecError.malformed);
    }
  }
}

final class _Envelope {
  const _Envelope({
    required this.version,
    required this.createdAt,
    required this.kdfParams,
    required this.saltBase64,
    required this.dataBase64,
  });

  final int version;
  final DateTime createdAt;
  final KdfParams kdfParams;
  final String saltBase64;
  final String dataBase64;
}

_Envelope _parseEnvelope(String contents) {
  Map<String, Object?> json;
  try {
    json = jsonDecode(contents) as Map<String, Object?>;
  } on FormatException {
    throw const BackupCodecException(BackupCodecError.malformed);
  }
  if (json['format'] != backupFormatTag) {
    throw const BackupCodecException(BackupCodecError.unsupportedFormat);
  }
  final version = (json['version'] as num?)?.toInt();
  if (version == null || version > backupFormatVersion) {
    throw const BackupCodecException(BackupCodecError.unsupportedVersion);
  }
  final kdfJson = json['kdf'];
  if (kdfJson is! Map<String, Object?>) {
    throw const BackupCodecException(BackupCodecError.malformed);
  }
  final KdfParams params;
  try {
    params = KdfParams.fromJson(kdfJson);
  } catch (_) {
    throw const BackupCodecException(BackupCodecError.badKdfParams);
  }
  if ((json['cipher'] as String?) != 'aes-256-gcm') {
    throw const BackupCodecException(BackupCodecError.unsupportedFormat);
  }
  final salt = kdfJson['salt'] as String?;
  final data = json['data'] as String?;
  if (salt == null || data == null) {
    throw const BackupCodecException(BackupCodecError.malformed);
  }
  final createdAt = (json['createdAt'] as num?)?.toInt();
  if (createdAt == null) {
    throw const BackupCodecException(BackupCodecError.malformed);
  }
  return _Envelope(
    version: version,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
    kdfParams: params,
    saltBase64: salt,
    dataBase64: data,
  );
}

Map<String, Object?> _snapshotToJson(VaultSnapshot s) => {
  'categories': [
    for (final c in s.categories)
      {
        'id': c.id,
        'cardType': cardTypeToWire(c.cardType),
        'name': c.name,
        'sortOrder': c.sortOrder,
        'createdAt': c.createdAt.millisecondsSinceEpoch,
        'updatedAt': c.updatedAt.millisecondsSinceEpoch,
        'modelVersion': c.modelVersion,
      },
  ],
  'cards': [
    for (final c in s.cards)
      {
        'id': c.id,
        'categoryId': c.categoryId,
        'cardType': cardTypeToWire(c.cardType),
        'holderName': c.holderName,
        'cardNumber': c.cardNumber,
        'expiryMonth': c.expiryMonth,
        'expiryYear': c.expiryYear,
        'cvv': c.cvv,
        'uShieldExpiryDate': c.uShieldExpiryDate == null
            ? null
            : '${c.uShieldExpiryDate!.year}/'
                  '${c.uShieldExpiryDate!.month}/'
                  '${c.uShieldExpiryDate!.day}',
        'note': c.note,
        'createdAt': c.createdAt.millisecondsSinceEpoch,
        'updatedAt': c.updatedAt.millisecondsSinceEpoch,
        'modelVersion': c.modelVersion,
      },
  ],
  if (s.documents.isNotEmpty)
    'documents': [
      for (final d in s.documents)
        {
          'id': d.id,
          'categoryId': d.categoryId,
          'holderName': d.holderName,
          'idNumber': d.idNumber,
          'issuer': d.issuer,
          'validFrom': d.validFrom == null
              ? null
              : DocumentRecord.formatDate(d.validFrom!),
          'validTo': d.validTo == null
              ? null
              : DocumentRecord.formatDate(d.validTo!),
          if (d.validityIsPermanent) 'validityPermanent': true,
          'createdAt': d.createdAt.millisecondsSinceEpoch,
          'updatedAt': d.updatedAt.millisecondsSinceEpoch,
          'modelVersion': d.modelVersion,
        },
    ],
};

VaultSnapshot _snapshotFromJson(Map<String, Object?> json) {
  final categoryList = json['categories'];
  final cardList = json['cards'];
  if (categoryList is! List<Object?> || cardList is! List<Object?>) {
    throw const BackupCodecException(BackupCodecError.malformed);
  }
  final categories = <BankCategory>[];
  for (final item in categoryList) {
    if (item is! Map<String, Object?>) {
      throw const BackupCodecException(BackupCodecError.malformed);
    }
    final createdAt = (item['createdAt'] as num).toInt();
    final updatedAt = (item['updatedAt'] as num).toInt();
    categories.add(
      BankCategory(
        id: item['id']! as String,
        cardType: cardTypeFromWire(item['cardType']! as String),
        name: item['name']! as String,
        sortOrder: (item['sortOrder'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
        modelVersion: (item['modelVersion'] as num?)?.toInt() ?? 1,
      ),
    );
  }
  final cards = <CardRecord>[];
  for (final item in cardList) {
    if (item is! Map<String, Object?>) {
      throw const BackupCodecException(BackupCodecError.malformed);
    }
    final uShieldRaw = item['uShieldExpiryDate'] as String?;
    cards.add(
      CardRecord(
        id: item['id']! as String,
        categoryId: item['categoryId']! as String,
        cardType: cardTypeFromWire(item['cardType']! as String),
        holderName: item['holderName'] as String?,
        sortOrder: (item['sortOrder'] as num?)?.toInt() ?? 0,
        cardNumber: item['cardNumber']! as String,
        expiryMonth: (item['expiryMonth'] as num?)?.toInt(),
        expiryYear: (item['expiryYear'] as num?)?.toInt(),
        cvv: item['cvv'] as String?,
        uShieldExpiryDate: parseUSieldDate(uShieldRaw),
        note: item['note'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (item['createdAt'] as num).toInt(),
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (item['updatedAt'] as num).toInt(),
        ),
        modelVersion: (item['modelVersion'] as num?)?.toInt() ?? 1,
      ),
    );
  }
  final documents = <DocumentRecord>[];
  final documentList = json['documents'];
  if (documentList is List<Object?>) {
    for (final item in documentList) {
      if (item is! Map<String, Object?>) {
        throw const BackupCodecException(BackupCodecError.malformed);
      }
      documents.add(
        DocumentRecord(
          id: item['id']! as String,
          categoryId: item['categoryId']! as String,
          holderName: item['holderName'] as String? ?? '',
          idNumber: item['idNumber']! as String,
          issuer: item['issuer'] as String? ?? '',
          validFrom: DocumentRecord.parseDate(item['validFrom'] as String?),
          validTo: DocumentRecord.parseDate(item['validTo'] as String?),
          validityIsPermanent: item['validityPermanent'] == true,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            (item['createdAt'] as num).toInt(),
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (item['updatedAt'] as num).toInt(),
          ),
          modelVersion: (item['modelVersion'] as num?)?.toInt() ?? 1,
        ),
      );
    }
  }
  return VaultSnapshot(
    categories: categories,
    cards: cards,
    documents: documents,
  );
}

DateTime? parseUSieldDate(String? wire) {
  if (wire == null || wire.isEmpty) {
    return null;
  }
  final parts = wire.split('/');
  if (parts.length != 3) {
    throw const BackupCodecException(BackupCodecError.malformed);
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    throw const BackupCodecException(BackupCodecError.malformed);
  }
  final candidate = DateTime(year, month, day);
  if (candidate.year != year ||
      candidate.month != month ||
      candidate.day != day) {
    throw const BackupCodecException(BackupCodecError.malformed);
  }
  return candidate;
}
