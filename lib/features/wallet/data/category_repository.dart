import '../../../core/database/encrypted_database.dart';
import '../../../core/database/encrypted_record.dart';
import '../domain/models.dart';

/// Persistence for bank categories. Payload (name) is encrypted; card_type
/// and sort_order stay as plaintext metadata for filtering and ordering.
final class CategoryRepository {
  CategoryRepository(this._db);

  static const String table = 'categories';

  final EncryptedDatabase _db;

  Future<List<BankCategory>> listAll() async {
    final records = await _db.listRecords(table);
    return records
        .map(
          (record) => BankCategory.fromJsonFields(
            metadata: record.metadata.extra,
            payloadJson: record.json,
          ),
        )
        .toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
      });
  }

  Future<List<BankCategory>> listByType(CardType type) async {
    final records = await _db.listRecords(
      table,
      where: 'card_type = ?',
      whereArgs: [cardTypeToWire(type)],
    );
    final categories = <BankCategory>[];
    for (final record in records) {
      final category = BankCategory.fromJsonFields(
        metadata: record.metadata.extra,
        payloadJson: record.json,
      );
      if (category.cardType == type) {
        categories.add(category);
      }
    }
    categories.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return categories;
  }

  Future<BankCategory?> getById(String id) async {
    final json = await _db.getPayload(table, id);
    if (json == null) {
      return null;
    }
    // Metadata columns are needed for full reconstruction; fetch via list.
    final records = await _db.listRecords(table);
    for (final record in records) {
      if (record.metadata.id == id) {
        return BankCategory.fromJsonFields(
          metadata: record.metadata.extra,
          payloadJson: record.json,
        );
      }
    }
    return null;
  }

  Future<void> save(BankCategory category) => _db.putRecord(
    table,
    EncryptedRecord(
      metadata: RecordMetadata(
        id: category.id,
        createdAt: category.createdAt.millisecondsSinceEpoch,
        updatedAt: category.updatedAt.millisecondsSinceEpoch,
        modelVersion: category.modelVersion,
        extra: {
          'card_type': cardTypeToWire(category.cardType),
          'sort_order': category.sortOrder,
        },
      ),
      json: category.payloadJson(),
    ),
  );

  Future<int> delete(String id) => _db.deleteRecord(table, id);

  Future<int> countCardsInCategory(String categoryId) =>
      _db.countWhere('cards', 'category_id = ?', [categoryId]);
}
