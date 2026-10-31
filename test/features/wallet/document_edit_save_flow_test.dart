import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kabao/app/providers/repositories_providers.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:kabao/features/wallet/data/card_repository.dart';
import 'package:kabao/features/wallet/data/category_repository.dart';
import 'package:kabao/features/wallet/data/document_repository.dart';
import 'package:kabao/features/wallet/domain/document.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:kabao/features/wallet/presentation/pages/document_detail_page.dart';
import 'package:kabao/features/wallet/presentation/widgets/document_edit_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 证件详情 → 编辑 → 保存：必须退出编辑页，且详情显示新值。
/// 与银行卡的同类回归测试对应（控制器被 autoDispose 回收后的保存路径）。
Future<void> _settleIo(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _awaitSave(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
  await _settleIo(tester);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late EncryptedDatabase db;
  late CategoryRepository categories;
  late CardRepository cards;
  late DocumentRepository documents;
  late DocumentRecord document;
  final dek = AeadCipher().generateKey(32);

  setUp(() async {
    final raw = await openDatabase(
      inMemoryDatabasePath,
      version: EncryptedDatabase.dbVersion,
      onCreate: (database, _) => EncryptedDatabase.createSchema(database),
    );
    await raw.execute('PRAGMA foreign_keys = ON');
    db = EncryptedDatabase.forTest(raw, AeadCipher())..attachKey(dek);
    categories = CategoryRepository(db);
    cards = CardRepository(db);
    documents = DocumentRepository(db);
    final now = DateTime.now();
    await categories.save(
      BankCategory(
        id: 'cat-1',
        cardType: CardType.document,
        name: '身份证',
        createdAt: now,
        updatedAt: now,
      ),
    );
    document = DocumentRecord(
      id: 'doc-1',
      categoryId: 'cat-1',
      holderName: '张三',
      idNumber: '402356201202263038',
      issuer: '中南县公安局',
      validFrom: DateTime(2016, 8, 8),
      validTo: DateTime(2036, 8, 8),
      createdAt: now,
      updatedAt: now,
    );
    await documents.save(document);
  });

  tearDown(() => db.close());

  Future<void> pumpDetail(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: '/wallet/document/edit',
          builder: (context, state) {
            final args =
                state.extra! as ({DocumentRecord document, bool isNew});
            return DocumentEditPage(document: args.document, isNew: args.isNew);
          },
        ),
        GoRoute(
          path: '/wallet/document/:id',
          builder: (context, state) =>
              DocumentDetailPage(document: state.extra as DocumentRecord),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryRepositoryProvider.overrideWithValue(categories),
          cardRepositoryProvider.overrideWithValue(cards),
          documentRepositoryProvider.overrideWithValue(documents),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _settleIo(tester);
    router.push('/wallet/document/doc-1', extra: document);
    await _settleIo(tester);
  }

  testWidgets('证件详情 → 编辑 → 保存：退出编辑页且详情显示新值', (tester) async {
    await pumpDetail(tester);
    expect(find.text('证件详情'), findsOneWidget);
    expect(find.text('中南县公安局'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑'));
    await _settleIo(tester);
    expect(find.text('编辑证件'), findsOneWidget);

    final issuer = find.widgetWithText(TextFormField, '中南县公安局');
    await tester.enterText(issuer, '北山县公安局');
    await tester.pump();
    final formList = find.byType(Scrollable).first;
    await tester.dragUntilVisible(
      find.byKey(const Key('doc-save')),
      formList,
      const Offset(0, -200),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('doc-save')));
    await _awaitSave(tester);

    expect(find.text('编辑证件'), findsNothing);
    expect(find.text('证件详情'), findsOneWidget);
    expect(find.text('北山县公安局'), findsOneWidget);
    expect(find.text('中南县公安局'), findsNothing);

    final stored = await tester.runAsync(() => documents.getById('doc-1'));
    expect(stored?.issuer, '北山县公安局');
  });
}
