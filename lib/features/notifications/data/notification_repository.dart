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
  Future<List<AppNotification>> listActive({DateTime? now}) async {
    final rows = await _db.queryWhere(
      table,
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    final current = now ?? DateTime.now();
    return rows
        .map(AppNotification.fromRow)
        .where((notification) => _isVisible(notification, current))
        .toList();
  }

  bool _isVisible(AppNotification notification, DateTime now) {
    final scheduledFor = notification.scheduledFor;
    if (scheduledFor == null) {
      return true;
    }
    // System banners are scheduled for 09:00 on the reminder date. The
    // persisted row stays hidden until that same local wall-clock time.
    final visibleAt = DateTime(
      scheduledFor.year,
      scheduledFor.month,
      scheduledFor.day,
      9,
    );
    return !visibleAt.isAfter(now);
  }

  Future<List<String>> existingDedupeKeys() async {
    final rows = await _db.queryWhere(table, columns: ['dedupe_key']);
    return rows.map((r) => r['dedupe_key']! as String).toList();
  }

  Future<AppNotification?> findByDedupeKey(String dedupeKey) async {
    final rows = await _db.queryWhere(
      table,
      where: 'dedupe_key = ?',
      whereArgs: [dedupeKey],
      orderBy: 'created_at DESC',
    );
    return rows.isEmpty ? null : AppNotification.fromRow(rows.first);
  }

  /// Decrypts all reminder snapshots once for bulk recomputation; this avoids
  /// repeated per-key queries while still including dismissed rows.
  Future<List<AppNotification>> listAll() async {
    final rows = await _db.queryWhere(table);
    return rows.map(AppNotification.fromRow).toList();
  }

  Future<int> markSystemScheduled(String id) => _db.updateWhere(
    table,
    {'system_scheduled_at': DateTime.now().millisecondsSinceEpoch},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<int> markSystemDelivered(String id) => _db.updateWhere(
    table,
    {'system_delivered_at': DateTime.now().millisecondsSinceEpoch},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Dedupe keys deliberately dismissed by the user. Recompute logic must
  /// keep these keys reserved without re-arming their system alarms.
  Future<List<String>> deletedDedupeKeys() async {
    final rows = await _db.queryWhere(
      table,
      columns: ['dedupe_key'],
      where: 'deleted_at IS NOT NULL',
    );
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

  /// Hides a notification while retaining its dedupe key. This prevents the
  /// next startup recomputation from recreating a reminder the user deleted.
  Future<int> delete(String id) => _db.updateWhere(
    table,
    {'deleted_at': DateTime.now().millisecondsSinceEpoch},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> deleteByCard(String cardId) => _db.updateWhere(
    table,
    {'deleted_at': DateTime.now().millisecondsSinceEpoch},
    where: 'card_id = ?',
    whereArgs: [cardId],
  );

  /// Removes old reminder snapshots when a record's expiry dates change.
  /// Unlike a user dismissal, this must release the dedupe keys so the new
  /// dates can generate fresh reminders.
  Future<void> purgeByCard(String cardId) async {
    await _db.deleteWhere(table, 'card_id = ?', [cardId]);
  }
}
