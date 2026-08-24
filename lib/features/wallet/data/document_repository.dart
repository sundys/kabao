import '../../../core/database/encrypted_database.dart';
import '../../../core/database/encrypted_record.dart';
import '../domain/document.dart';

/// Persistence for certificate documents (card_type = 'document').
final class DocumentRepository {
  DocumentRepository(this._db);

  static const String table = 'cards';

  final EncryptedDatabase _db;

  Future<List<DocumentRecord>> listByCategory(String categoryId) async {
    final records = await _db.listRecords(table);
    return records
        .map((record) => _tryParse(record.metadata.extra, record.json))
        .whereType<DocumentRecord>()
        .where((doc) => doc.categoryId == categoryId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<List<DocumentRecord>> listAll() async {
    final records = await _db.listRecords(table);
    return records
        .map((record) => _tryParse(record.metadata.extra, record.json))
        .whereType<DocumentRecord>()
        .toList();
  }

  Future<DocumentRecord?> getById(String id) async {
    for (final doc in await listAll()) {
      if (doc.id == id) {
        return doc;
      }
    }
    return null;
  }

  Future<void> save(DocumentRecord document) => _db.putRecord(
    table,
    EncryptedRecord(
      metadata: RecordMetadata(
        id: document.id,
        createdAt: document.createdAt.millisecondsSinceEpoch,
        updatedAt: document.updatedAt.millisecondsSinceEpoch,
        modelVersion: document.modelVersion,
        extra: {'card_type': 'document', 'category_id': document.categoryId},
      ),
      json: document.payloadJson(),
    ),
  );

  Future<int> delete(String id) => _db.deleteRecord(table, id);

  static DocumentRecord? _tryParse(Map<String, Object?> metadata, String json) {
    if ((metadata['card_type'] as String?) != 'document') {
      return null;
    }
    return DocumentRecord.fromJsonFields(metadata: metadata, payloadJson: json);
  }
}
