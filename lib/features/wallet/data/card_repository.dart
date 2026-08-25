import '../../../core/database/encrypted_database.dart';
import '../../../core/database/encrypted_record.dart';
import '../domain/models.dart';

/// Persistence for bank card records. All sensitive fields (number, CVV,
/// dates, note) live inside the encrypted payload. Certificate documents
/// (card_type = 'document') share this table and are skipped here — they are
/// owned by [DocumentRepository].
final class CardRepository {
  CardRepository(this._db);

  static const String table = 'cards';

  final EncryptedDatabase _db;

  static bool _isBankCard(Map<String, Object?> metadata) =>
      (metadata['card_type'] as String?) != 'document';

  Future<List<CardRecord>> listByCategory(String categoryId) async {
    final records = await _db.listRecords(table);
    final cards = <CardRecord>[];
    for (final record in records) {
      if (!_isBankCard(record.metadata.extra)) {
        continue;
      }
      final card = CardRecord.fromJsonFields(
        metadata: record.metadata.extra,
        payloadJson: record.json,
      );
      if (card.categoryId == categoryId) {
        cards.add(card);
      }
    }
    cards.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return cards;
  }

  Future<List<CardRecord>> listByType(CardType type) async {
    assert(type != CardType.document, 'documents use DocumentRepository');
    final records = await _db.listRecords(table);
    return records
        .where((record) => _isBankCard(record.metadata.extra))
        .map(
          (record) => CardRecord.fromJsonFields(
            metadata: record.metadata.extra,
            payloadJson: record.json,
          ),
        )
        .where((card) => card.cardType == type)
        .toList();
  }

  Future<CardRecord?> getById(String id) async {
    final records = await _db.listRecords(table);
    for (final record in records) {
      if (record.metadata.id == id && _isBankCard(record.metadata.extra)) {
        return CardRecord.fromJsonFields(
          metadata: record.metadata.extra,
          payloadJson: record.json,
        );
      }
    }
    return null;
  }

  Future<void> save(CardRecord card) => _db.putRecord(
    table,
    EncryptedRecord(
      metadata: RecordMetadata(
        id: card.id,
        createdAt: card.createdAt.millisecondsSinceEpoch,
        updatedAt: card.updatedAt.millisecondsSinceEpoch,
        modelVersion: card.modelVersion,
        extra: {
          'card_type': cardTypeToWire(card.cardType),
          'category_id': card.categoryId,
        },
      ),
      json: card.payloadJson(),
    ),
  );

  /// 批量持久化手动排序（同一分类内全部卡片重排序号）。
  Future<void> updateSortOrders(Map<String, int> orders) =>
      _db.runInTransaction(() async {
        for (final entry in orders.entries) {
          await _db.updateWhere(
            table,
            {
              'sort_order': entry.value,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [entry.key],
          );
        }
      });

  Future<int> delete(String id) => _db.deleteRecord(table, id);
}
