import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notifications/data/notification_repository.dart';
import '../../features/wallet/data/card_repository.dart';
import '../../features/wallet/data/category_repository.dart';
import '../../features/wallet/data/document_repository.dart';
import 'vault_providers.dart';

export 'vault_providers.dart';

final categoryRepositoryProvider = Provider<CategoryRepository?>((ref) {
  final db = ref.watch(vaultDatabaseProvider).value;
  if (db == null) {
    return null;
  }
  return CategoryRepository(db);
});

final cardRepositoryProvider = Provider<CardRepository?>((ref) {
  final db = ref.watch(vaultDatabaseProvider).value;
  if (db == null) {
    return null;
  }
  return CardRepository(db);
});

final notificationRepositoryProvider = Provider<NotificationRepository?>((ref) {
  final db = ref.watch(vaultDatabaseProvider).value;
  if (db == null) {
    return null;
  }
  return NotificationRepository(db);
});

final documentRepositoryProvider = Provider<DocumentRepository?>((ref) {
  final db = ref.watch(vaultDatabaseProvider).value;
  if (db == null) {
    return null;
  }
  return DocumentRepository(db);
});
