import 'dart:convert';

/// A certificate/ID document (身份证、行驶证…). Lives in the same encrypted
/// `cards` table with `card_type = 'document'`; all sensitive content is in
/// the payload.
class DocumentRecord {
  DocumentRecord({
    required this.id,
    required this.categoryId,
    required this.holderName,
    required this.idNumber,
    required this.issuer,
    this.validFrom,
    this.validTo,
    this.remark,
    required this.createdAt,
    required this.updatedAt,
    this.modelVersion = 1,
  });

  static const int maxIdNumberLength = 20;

  final String id;
  final String categoryId;

  /// 持有人姓名。
  final String holderName;

  /// Digits only (证件号).
  final String idNumber;
  final String issuer;
  final DateTime? validFrom;
  final DateTime? validTo;

  /// 备注（可选）。
  final String? remark;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int modelVersion;

  DocumentRecord copyWith({
    required String holderName,
    String? idNumber,
    String? issuer,
    DateTime? validFrom,
    DateTime? validTo,
    DateTime? updatedAt,
  }) => DocumentRecord(
    id: id,
    categoryId: categoryId,
    holderName: holderName,
    idNumber: idNumber ?? this.idNumber,
    issuer: issuer ?? this.issuer,
    validFrom: validFrom ?? this.validFrom,
    validTo: validTo ?? this.validTo,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    modelVersion: modelVersion,
  );

  String payloadJson() => jsonEncode({
    'holderName': holderName,
    'idNumber': idNumber,
    'issuer': issuer,
    if (validFrom != null) 'validFrom': formatDate(validFrom!),
    if (validTo != null) 'validTo': formatDate(validTo!),
    'remark': remark,
  });

  factory DocumentRecord.fromJsonFields({
    required Map<String, Object?> metadata,
    required String payloadJson,
  }) {
    final payload = jsonDecode(payloadJson) as Map<String, Object?>;
    return DocumentRecord(
      id: metadata['id']! as String,
      categoryId: metadata['category_id']! as String,
      holderName: payload['holderName'] as String? ?? '',
      idNumber: payload['idNumber']! as String,
      issuer: payload['issuer'] as String? ?? '',
      validFrom: parseDate(payload['validFrom'] as String?),
      validTo: parseDate(payload['validTo'] as String?),
      remark: payload['remark'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (metadata['created_at']! as num).toInt(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (metadata['updated_at']! as num).toInt(),
      ),
      modelVersion: (metadata['model_version']! as num).toInt(),
    );
  }

  static String formatDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.'
      '${d.day.toString().padLeft(2, '0')}';

  /// Parses `yyyy.MM.dd`; rejects impossible calendar dates.
  static DateTime? parseDate(String? wire) {
    if (wire == null || wire.isEmpty) {
      return null;
    }
    final parts = wire.split('.');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    final candidate = DateTime(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return null;
    }
    return candidate;
  }
}
