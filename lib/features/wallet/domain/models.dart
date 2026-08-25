import 'dart:convert';

enum CardType { debit, credit, document }

String cardTypeToWire(CardType type) => switch (type) {
  CardType.debit => 'debit',
  CardType.credit => 'credit',
  CardType.document => 'document',
};

CardType cardTypeFromWire(String wire) => switch (wire) {
  'debit' => CardType.debit,
  'document' => CardType.document,
  _ => CardType.credit,
};

/// A bank category, e.g. "工商银行". Immutable with UUID identity and
/// timestamps; never keyed by name.
class BankCategory {
  BankCategory({
    required this.id,
    required this.cardType,
    required this.name,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.modelVersion = 1,
  });

  final String id;
  final CardType cardType;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int modelVersion;

  BankCategory copyWith({String? name, int? sortOrder, DateTime? updatedAt}) {
    return BankCategory(
      id: id,
      cardType: cardType,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      modelVersion: modelVersion,
    );
  }

  String payloadJson() => jsonEncode({'name': name});

  factory BankCategory.fromJsonFields({
    required Map<String, Object?> metadata,
    required String payloadJson,
  }) {
    final payload = jsonDecode(payloadJson) as Map<String, Object?>;
    return BankCategory(
      id: metadata['id']! as String,
      cardType: cardTypeFromWire(metadata['card_type']! as String),
      name: payload['name']! as String,
      sortOrder: (metadata['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (metadata['created_at']! as num).toInt(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (metadata['updated_at']! as num).toInt(),
      ),
      modelVersion: (metadata['model_version']! as num).toInt(),
    );
  }
}

/// A bank card record. `cardNumber` is stored digits-only; grouping is a
/// presentation concern only.
class CardRecord {
  CardRecord({
    required this.id,
    required this.categoryId,
    required this.cardType,
    required this.cardNumber,
    this.holderName,
    this.sortOrder = 0,
    this.expiryMonth,
    this.expiryYear,
    this.cvv,
    this.uShieldExpiryDate,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.modelVersion = 1,
  });

  static const int maxNoteLength = 500;

  final String id;
  final String categoryId;
  final CardType cardType;

  /// Digits only, length 1-19.
  final String cardNumber;

  /// 持卡人姓名（可选）。
  final String? holderName;

  /// 手动排序序号；0 表示未手动排序。
  final int sortOrder;

  /// Expiry month 01-12; null when not provided.
  final int? expiryMonth;

  /// Two-digit year value converted to full year (2000 + YY).
  final int? expiryYear;

  /// Exactly 3 digits.
  final String? cvv;

  /// Local date without timezone for the U-shield certificate expiry.
  final DateTime? uShieldExpiryDate;

  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int modelVersion;

  /// 返回仅更新手动排序序号的副本（编辑保存时不丢失排序）。
  CardRecord withSortOrder(int value) => CardRecord(
    id: id,
    categoryId: categoryId,
    cardType: cardType,
    cardNumber: cardNumber,
    holderName: holderName,
    sortOrder: value,
    expiryMonth: expiryMonth,
    expiryYear: expiryYear,
    cvv: cvv,
    uShieldExpiryDate: uShieldExpiryDate,
    note: note,
    createdAt: createdAt,
    updatedAt: updatedAt,
    modelVersion: modelVersion,
  );

  String payloadJson() => jsonEncode({
    'holderName': holderName,
    'cardNumber': cardNumber,
    'sortOrder': sortOrder,
    'expiryMonth': expiryMonth,
    'expiryYear': expiryYear,
    'cvv': cvv,
    if (uShieldExpiryDate != null)
      'uShieldExpiryDate':
          '${uShieldExpiryDate!.year}/${uShieldExpiryDate!.month}/${uShieldExpiryDate!.day}',
    'note': note,
  });

  factory CardRecord.fromJsonFields({
    required Map<String, Object?> metadata,
    required String payloadJson,
  }) {
    final payload = jsonDecode(payloadJson) as Map<String, Object?>;
    final expiry = _parseUSield(payload['uShieldExpiryDate'] as String?);
    return CardRecord(
      id: metadata['id']! as String,
      categoryId: metadata['category_id']! as String,
      cardType: cardTypeFromWire(metadata['card_type']! as String),
      cardNumber: payload['cardNumber']! as String,
      holderName: payload['holderName'] as String?,
      sortOrder: (metadata['sort_order'] as num?)?.toInt() ?? 0,
      expiryMonth: (payload['expiryMonth'] as num?)?.toInt(),
      expiryYear: (payload['expiryYear'] as num?)?.toInt(),
      cvv: payload['cvv'] as String?,
      uShieldExpiryDate: expiry,
      note: payload['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (metadata['created_at']! as num).toInt(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (metadata['updated_at']! as num).toInt(),
      ),
      modelVersion: (metadata['model_version']! as num).toInt(),
    );
  }

  static DateTime? _parseUSield(String? wire) {
    if (wire == null || wire.isEmpty) {
      return null;
    }
    final parts = wire.split('/');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    // DateTime constructor normalizes invalid dates; reject them instead.
    final candidate = DateTime(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return null;
    }
    return candidate;
  }
}
