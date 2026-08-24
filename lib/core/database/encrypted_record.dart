final class RecordMetadata {
  const RecordMetadata({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.modelVersion,
    this.extra = const {},
  });

  final String id;
  final int createdAt;
  final int updatedAt;
  final int modelVersion;

  /// Non-sensitive columns used for sorting/filtering (e.g. cardType,
  /// dedupeKey). Never contains card numbers or secrets.
  final Map<String, Object?> extra;

  Map<String, Object?> toRow() => {
    'id': id,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'model_version': modelVersion,
    ...extra,
  };
}

/// A business record as stored in the encrypted database: plaintext metadata
/// plus an authenticated-encrypted JSON payload.
final class EncryptedRecord {
  const EncryptedRecord({required this.metadata, required this.json});

  final RecordMetadata metadata;
  final String json;

  /// Rebuilds a record from a raw database row. All columns except `payload`
  /// are treated as non-sensitive metadata; the standard identity/timestamp
  /// columns are kept inside [RecordMetadata.extra] as well so factories can
  /// reconstruct domain objects from one map.
  static EncryptedRecord fromRow(Map<String, Object?> row, String json) =>
      EncryptedRecord(
        metadata: RecordMetadata(
          id: row['id']! as String,
          createdAt: row['created_at']! as int,
          updatedAt: row['updated_at']! as int,
          modelVersion: row['model_version']! as int,
          extra: Map<String, Object?>.from(row)..remove('payload'),
        ),
        json: json,
      );
}
