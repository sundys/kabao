import 'package:sqflite/sqflite.dart';

import '../../../core/database/encrypted_database.dart';
import '../domain/models.dart';

/// Persistence for in-app notifications. Payload (title/body) is encrypted;
/// `dedupe_key` is unique so reminder recomputation is naturally idempotent.
final class NotificationRepository {
  NotificationRepository(this._db);

  static const String table = 'notifications';

  final EncryptedDatabase _db;

  /// Visible notifications, newest first. Soft-deleted rows are excluded.
  Future<List<AppNotification>> listActive() async {
    final rows = await _db.queryWhere(
      table,
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return rows.map(AppNotification.fromRow).toList();
  }

  Future<List<String>> existingDedupeKeys() async {
    final rows = await _db.queryWhere(table, columns: ['dedupe_key']);
    return rows.map((r) => r['dedupe_key']! as String).toList();
  }

  /// Returns true when the row was inserted; false when the dedupe key
  /// already exists.
  Future<bool> insertIfAbsent(AppNotification notification) async {
    try {
      await _db.insertRow(table, notification.toRow());
      return true;
    } on DatabaseException catch (e) {
      if (e.toString().contains('UNIQUE')) {
        return false;
      }
      rethrow;
    }
  }

  Future<int> markRead(String id) => _db.updateWhere(
    table,
    {'read_at': DateTime.now().millisecondsSinceEpoch},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Physical delete: the spec allows either; physical keeps the table small
  /// and the dedupe key of a removed reminder never resurrects it.
  Future<int> delete(String id) => _db.deleteWhere(table, 'id = ?', [id]);

  Future<void> deleteByCard(String cardId) =>
      _db.deleteWhere(table, 'card_id = ?', [cardId]);
}
