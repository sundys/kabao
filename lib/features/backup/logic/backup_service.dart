import '../../../core/database/encrypted_database.dart';
import '../../../core/database/encrypted_record.dart';
import '../../wallet/domain/document.dart';
import '../../wallet/domain/models.dart';
import '../logic/backup_codec.dart';

/// Result summary of an import, safe to display.
final class ImportResult {
  const ImportResult({
    required this.categoriesAdded,
    required this.categoriesUpdated,
    required this.cardsAdded,
    required this.cardsUpdated,
  });

  final int categoriesAdded;
  final int categoriesUpdated;
  final int cardsAdded;
  final int cardsUpdated;
}

final class BackupService {
  BackupService({required this.database});

  /// The encrypted database the snapshot is exported from / merged into.
  final EncryptedDatabase database;

  VaultSnapshot exportSnapshot({
    required List<BankCategory> categories,
    required List<CardRecord> cards,
    List<DocumentRecord> documents = const [],
  }) =>
      VaultSnapshot(categories: categories, cards: cards, documents: documents);

  /// Merges a decrypted snapshot into the vault inside one transaction:
  /// per-UUID conflict resolution keeps the newer `updatedAt` record.
  /// Never deletes records missing from the backup.
  Future<ImportResult> importMerge(VaultSnapshot snapshot) async {
    var categoriesAdded = 0;
    var categoriesUpdated = 0;
    var cardsAdded = 0;
    var cardsUpdated = 0;

    await database.runInTransaction(() async {
      final existingCategories = <String, DateTime>{
        for (final c in await database.listRecords('categories'))
          c.metadata.id: DateTime.fromMillisecondsSinceEpoch(
            c.metadata.updatedAt,
          ),
      };
      for (final category in snapshot.categories) {
        final existing = existingCategories[category.id];
        if (existing == null) {
          await database.putRecord('categories', _categoryRecord(category));
          categoriesAdded++;
        } else if (category.updatedAt.isAfter(existing)) {
          await database.putRecord('categories', _categoryRecord(category));
          categoriesUpdated++;
        }
      }

      final existingCards = <String, DateTime>{
        for (final c in await database.listRecords('cards'))
          c.metadata.id: DateTime.fromMillisecondsSinceEpoch(
            c.metadata.updatedAt,
          ),
      };
      for (final card in snapshot.cards) {
        final existing = existingCards[card.id];
        if (existing == null) {
          await database.putRecord('cards', _cardRecord(card));
          cardsAdded++;
        } else if (card.updatedAt.isAfter(existing)) {
          await database.putRecord('cards', _cardRecord(card));
          cardsUpdated++;
        }
      }

      final existingDocuments = <String, DateTime>{
        for (final c in await database.listRecords('cards'))
          if ((c.metadata.extra['card_type'] as String?) == 'document')
            c.metadata.id: DateTime.fromMillisecondsSinceEpoch(
              c.metadata.updatedAt,
            ),
      };
      for (final doc in snapshot.documents) {
        final existing = existingDocuments[doc.id];
        if (existing == null || doc.updatedAt.isAfter(existing)) {
          await database.putRecord('cards', _documentRecord(doc));
          if (existing == null) {
            cardsAdded++;
          } else {
            cardsUpdated++;
          }
        }
      }
    });

    return ImportResult(
      categoriesAdded: categoriesAdded,
      categoriesUpdated: categoriesUpdated,
      cardsAdded: cardsAdded,
      cardsUpdated: cardsUpdated,
    );
  }

  static const String tableCategories = 'categories';
  static const String tableCards = 'cards';

  EncryptedRecord _categoryRecord(BankCategory category) => EncryptedRecord(
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
  );

  EncryptedRecord _cardRecord(CardRecord card) => EncryptedRecord(
    metadata: RecordMetadata(
      id: card.id,
      createdAt: card.createdAt.millisecondsSinceEpoch,
      updatedAt: card.updatedAt.millisecondsSinceEpoch,
      modelVersion: card.modelVersion,
      extra: {
        'card_type': cardTypeToWire(card.cardType),
        'category_id': card.categoryId,
        'sort_order': card.sortOrder,
      },
    ),
    json: card.payloadJson(),
  );

  EncryptedRecord _documentRecord(DocumentRecord doc) => EncryptedRecord(
    metadata: RecordMetadata(
      id: doc.id,
      createdAt: doc.createdAt.millisecondsSinceEpoch,
      updatedAt: doc.updatedAt.millisecondsSinceEpoch,
      modelVersion: doc.modelVersion,
      extra: {'card_type': 'document', 'category_id': doc.categoryId},
    ),
    json: doc.payloadJson(),
  );
}
