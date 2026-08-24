import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/repositories_providers.dart';
import '../../wallet/domain/models.dart';
import '../../wallet/logic/cards_controller.dart' as wallet_cards;
import '../../wallet/logic/categories_controller.dart' as wallet_categories;
import '../../wallet/logic/documents_controller.dart' as wallet_documents;
import '../logic/backup_codec.dart';
import '../logic/backup_service.dart';

final class BackupFlows {
  const BackupFlows._();

  static String get _defaultFileName {
    final now = DateTime.now();
    return 'kabao-backup-${now.year}${_pad(now.month)}${_pad(now.day)}.kabao';
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');

  /// Export flow: choose a backup password → pick location (SAF via
  /// FilePicker) → encrypt and write atomically-ish (single write after full
  /// encryption completes).
  static Future<void> export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final password = await _askPassword(
      context,
      title: '设置备份密码',
      hint: '备份将使用该密码独立加密，与主密码互不影响',
    );
    if (password == null || !context.mounted) {
      return;
    }
    final savePath = await FilePicker.platform.saveFile(
      fileName: _defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['kabao'],
    );
    if (savePath == null || !context.mounted) {
      return;
    }
    try {
      final db = ref.read(vaultDatabaseProvider).value;
      final categoryRepo = ref.read(categoryRepositoryProvider);
      final cardRepo = ref.read(cardRepositoryProvider);
      final documentRepo = ref.read(documentRepositoryProvider);
      if (db == null || categoryRepo == null || cardRepo == null) {
        throw StateError('vault locked');
      }
      final service = BackupService(database: db);
      final snapshot = service.exportSnapshot(
        categories: await categoryRepo.listAll(),
        cards: [
          ...await cardRepo.listByType(CardType.debit),
          ...await cardRepo.listByType(CardType.credit),
        ],
        documents: await documentRepo?.listAll() ?? const [],
      );
      // Encrypt fully before touching the destination.
      final contents = await BackupCodec.encode(
        snapshot: snapshot,
        password: password,
        now: DateTime.now(),
      );
      await File(savePath).writeAsString(contents, flush: true);
      messenger.showSnackBar(const SnackBar(content: Text('备份已导出')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('导出失败，请重试')));
    }
  }

  /// Import flow: pick file → preview non-sensitive metadata → decrypt into
  /// memory (staging) → user confirms merge → transactional merge.
  static Future<void> import(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final contents = await File(path).readAsString();
      final meta = BackupCodec.readMetadata(contents);

      if (!context.mounted) {
        return;
      }
      final proceed = await _confirmMetadata(context, meta);
      if (proceed != true || !context.mounted) {
        return;
      }
      final password = await _askPassword(
        context,
        title: '输入备份密码',
        hint: '用于解密该备份文件',
        confirmField: false,
      );
      if (password == null || !context.mounted) {
        return;
      }

      // Stage: decrypt fully before any write.
      final VaultSnapshot snapshot;
      try {
        snapshot = await BackupCodec.decrypt(
          contents: contents,
          password: password,
        );
      } on BackupCodecException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(_errorText(e.error))));
        return;
      }

      if (!context.mounted) {
        return;
      }
      final confirmed = await _confirmMerge(
        context,
        snapshot.categories.length,
        snapshot.cards.length,
      );
      if (confirmed != true || !context.mounted) {
        return;
      }

      final db = ref.read(vaultDatabaseProvider).value!;
      final service = BackupService(database: db);
      final result = await service.importMerge(snapshot);
      ref.invalidate(wallet_categories.categoriesProvider);
      ref.invalidate(wallet_cards.cardsProvider);
      ref.invalidate(wallet_documents.documentsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('导入完成：${result.toString()}')),
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('导入失败，文件可能已损坏')));
    }
  }

  static String _errorText(BackupCodecError error) => switch (error) {
    BackupCodecError.authenticationFailed => '备份密码错误或文件已被篡改',
    BackupCodecError.unsupportedFormat => '不是有效的卡包备份文件',
    BackupCodecError.unsupportedVersion => '备份格式版本过新，请先升级应用',
    BackupCodecError.badKdfParams => '备份文件加密参数无效',
    BackupCodecError.malformed => '备份文件已损坏',
  };

  static Future<String?> _askPassword(
    BuildContext context, {
    required String title,
    required String hint,
    bool confirmField = true,
  }) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  hint,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
              TextFormField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                validator: (v) =>
                    (v == null || v.length < 8) ? '至少 8 个字符' : null,
              ),
              if (confirmField)
                TextFormField(
                  controller: confirmController,
                  obscureText: true,
                  validator: (v) => v == controller.text ? null : '两次输入不一致',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(controller.text);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  static Future<bool?> _confirmMetadata(
    BuildContext context,
    BackupMetadata meta,
  ) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('确认导入'),
      content: Text(
        '格式版本：v${meta.version}\n'
                '创建时间：${meta.createdAt.toLocal()}'
            .replaceAll(RegExp(r'\.\d+$'), ''),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('下一步'),
        ),
      ],
    ),
  );

  static Future<bool?> _confirmMerge(
    BuildContext context,
    int categories,
    int cards,
  ) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('合并策略'),
      content: Text(
        '将合并 $categories 个分类、$cards 张卡片。\n\n'
        '相同 ID 的记录以更新时间较新者为准，不会删除现有数据。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('开始导入'),
        ),
      ],
    ),
  );
}
