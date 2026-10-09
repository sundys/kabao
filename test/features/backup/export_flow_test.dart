import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/app/providers/repositories_providers.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:kabao/features/backup/logic/backup_codec.dart';
import 'package:kabao/features/backup/presentation/backup_flows.dart';
import 'package:kabao/features/wallet/data/card_repository.dart';
import 'package:kabao/features/wallet/data/category_repository.dart';
import 'package:kabao/features/wallet/data/document_repository.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 测试替身：记录 saveFile 的调用参数，并复现 Android/iOS 上“由插件通过 SAF
/// 写入字节”的行为，同时保留 file_picker 对 bytes 的非空要求。
final class _RecordingFilePicker extends FilePicker {
  _RecordingFilePicker(this.savePath);

  /// 保存对话框返回的路径。插件会把密文写到 [safPath]，用它校验真实产物。
  final String? savePath;

  /// 模拟 SAF 落盘的目标文件，与返回路径分开，避免与桌面端分支重复写同一文件。
  late final String safPath = '${savePath ?? 'out'}.saf';

  final List<Uint8List?> bytesSeen = [];
  final List<String?> fileNamesSeen = [];
  Uint8List? writtenBytes;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    // 与 file_picker 10.x 的 IO 实现保持一致：缺 bytes 直接失败。
    if (bytes == null) {
      throw ArgumentError(
        'Bytes are required on Android & iOS when saving a file.',
      );
    }
    bytesSeen.add(bytes);
    fileNamesSeen.add(fileName);
    if (savePath != null) {
      await File(safPath).writeAsBytes(bytes, flush: true);
      writtenBytes = bytes;
    }
    return savePath;
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late EncryptedDatabase db;
  late CategoryRepository categories;
  late CardRepository cards;
  late DocumentRepository documents;
  late _RecordingFilePicker picker;
  late String targetPath;

  setUp(() async {
    // 测试环境没有插件注册，FilePicker.platform 尚未初始化，无法先读出旧值，
    // 因此每个用例都直接装上自己的替身。
    tempDir = await Directory.systemTemp.createTemp('kabao-export-test');
    targetPath = '${tempDir.path}${Platform.pathSeparator}out.kabao';
    picker = _RecordingFilePicker(targetPath);
    FilePicker.platform = picker;

    final raw = await openDatabase(
      inMemoryDatabasePath,
      version: EncryptedDatabase.dbVersion,
      onCreate: (database, _) => EncryptedDatabase.createSchema(database),
    );
    await raw.execute('PRAGMA foreign_keys = ON');
    db = EncryptedDatabase.forTest(raw, AeadCipher())
      ..attachKey(AeadCipher().generateKey(32));
    categories = CategoryRepository(db);
    cards = CardRepository(db);
    documents = DocumentRepository(db);

    final now = DateTime.fromMillisecondsSinceEpoch(1756000000000);
    await categories.save(
      BankCategory(
        id: 'cat-1',
        cardType: CardType.credit,
        name: '工商银行',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await cards.save(
      CardRecord(
        id: 'card-1',
        categoryId: 'cat-1',
        cardType: CardType.credit,
        cardNumber: '6222000012345678',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    // Windows 上文件句柄释放稍慢，清理失败不影响断言结论。
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } on FileSystemException {
      // ignore
    }
  });

  Widget exportScreen() => ProviderScope(
    overrides: [
      vaultDatabaseProvider.overrideWithBuild((ref, notifier) async => db),
      categoryRepositoryProvider.overrideWithValue(categories),
      cardRepositoryProvider.overrideWithValue(cards),
      documentRepositoryProvider.overrideWithValue(documents),
    ],
    child: MaterialApp(
      home: Scaffold(
        // 真实应用在根组件里 watch 保险库 provider；这里同样保持订阅，
        // 否则导出读到的仍是 AsyncLoading，会被当成“已锁定”。
        body: Consumer(
          builder: (context, ref, _) {
            ref.watch(vaultDatabaseProvider);
            return TextButton(
              key: const Key('export-button'),
              onPressed: () => BackupFlows.export(context, ref),
              child: const Text('导出备份'),
            );
          },
        ),
      ),
    ),
  );

  /// 仓储读取走真实 sqlite I/O，密码派生跑在 worker isolate 上：两者都在真实
  /// 事件循环里完成，测试的假时钟推不动它们，必须借 [WidgetTester.runAsync]
  /// 让事件循环转起来，再回到假时钟渲染。
  Future<void> settleAsyncWork(
    WidgetTester tester, {
    bool Function()? done,
  }) async {
    for (var i = 0; i < 60; i++) {
      if (done != null && done()) {
        break;
      }
      // 在 runAsync 里等真实事件循环，再在假时钟里 pump 一帧；两者交替才能
      // 让 isolate/sqlite 的回调落到 widget 树上。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// 走完真实的导出流程：点击入口 → 填写备份密码与确认 → 等加密落盘。
  Future<void> runExport(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('export-button')));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2), reason: '导出需要密码与确认密码两栏');
    await tester.enterText(fields.at(0), 'export-pass-1');
    await tester.enterText(fields.at(1), 'export-pass-1');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 等到成功提示出现，说明加密与落盘都已结束；只等 saveFile 被调用会在
    // 文件仍处于写入过程中就去读取。
    await settleAsyncWork(
      tester,
      done: () => find.text('备份已导出').evaluate().isNotEmpty,
    );
    expect(
      find.text('备份已导出'),
      findsOneWidget,
      reason: '导出成功提示应出现（失败时会显示“导出失败，请重试”）',
    );
  }

  testWidgets('导出把密文字节交给 saveFile（回归：空 bytes 导致无法导出）', (tester) async {
    await tester.pumpWidget(exportScreen());
    // 先让异步 provider 完成一次构建，否则导出读到的是锁定状态。
    await settleAsyncWork(tester);

    await runExport(tester);

    expect(picker.bytesSeen, hasLength(1), reason: 'saveFile 应被调用一次');
    expect(picker.bytesSeen.single, isNotNull, reason: '必须传入密文字节');
    expect(picker.bytesSeen.single!.isNotEmpty, isTrue);
    expect(picker.fileNamesSeen.single, endsWith('.kabao'));
  });

  testWidgets('导出的文件是可解密的备份，且不含明文', (tester) async {
    await tester.pumpWidget(exportScreen());
    await settleAsyncWork(tester);

    await runExport(tester);

    // 读取插件侧通过“SAF”落盘的文件——这正是 Android 上用户得到的内容。
    final report = await tester.runAsync(() async {
      final file = File(picker.safPath);
      if (!await file.exists()) {
        return (exists: false, contents: '', snapshot: null);
      }
      final contents = await file.readAsString();
      final snapshot = await BackupCodec.decrypt(
        contents: contents,
        password: 'export-pass-1',
      );
      return (exists: true, contents: contents, snapshot: snapshot);
    });

    expect(report!.exists, isTrue, reason: '文件应被真正写入');
    final contents = report.contents;
    final json = jsonDecode(contents) as Map<String, Object?>;
    expect(json['format'], 'kabao-backup');
    expect(json['version'], 1);
    // 明文不得落盘。
    expect(contents.contains('工商银行'), isFalse);
    expect(contents.contains('6222000012345678'), isFalse);

    // 用导出时设置的密码可以解回原始数据。
    final snapshot = report.snapshot!;
    expect(snapshot.categories.single.name, '工商银行');
    expect(snapshot.cards.single.cardNumber, '6222000012345678');
  });
}
