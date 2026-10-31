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
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:kabao/features/wallet/presentation/pages/card_detail_page.dart';
import 'package:kabao/features/wallet/presentation/widgets/card_edit_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 编辑保存后必须离开编辑页；从详情页进入编辑时，返回后详情必须展示新值。
///
/// 这里刻意不复用分类列表页：详情页也可能由搜索结果直接打开，此时
/// `cardsProvider(categoryId)` 没有任何监听者。保存过程中的 `await` 会让该
/// autoDispose 控制器被回收，旧实现随后用 `ref.invalidate` 抛
/// UnmountedRefException，编辑页把异常当成“保存失败”，既不关闭也不提示。
///
/// 仓储读写是真实异步 I/O，测试的假时钟不会推进它们，因此需要在
/// [WidgetTester.runAsync] 内让事件循环跑起来。
Future<void> _settleIo(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 等待保存完成（按钮上的转圈消失），期间让真实 I/O 事件循环推进。
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
  // 路由退出动画在假时钟下推进。
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
  late CardRecord card;
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
        cardType: CardType.debit,
        name: '工商银行',
        createdAt: now,
        updatedAt: now,
      ),
    );
    card = CardRecord(
      id: 'card-1',
      categoryId: 'cat-1',
      cardType: CardType.debit,
      cardNumber: '6222000012345678',
      holderName: '张三',
      createdAt: now,
      updatedAt: now,
    );
    await cards.save(card);
  });

  tearDown(() => db.close());

  /// 详情页直接作为根路由（等价于搜索结果/待办直接打开），没有分类列表
  /// 监听 `cardsProvider`。
  Future<void> pumpDetail(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: '/wallet/card/edit',
          builder: (context, state) {
            final args = state.extra! as ({CardRecord card, bool isNew});
            return CardEditPage(card: args.card, isNew: args.isNew);
          },
        ),
        GoRoute(
          path: '/wallet/card/:id',
          builder: (context, state) =>
              CardDetailPage(card: state.extra as CardRecord),
        ),
      ],
    );
    // 用 push 打开详情，返回时才有上一页可回退。
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
    router.push('/wallet/card/card-1', extra: card);
    await _settleIo(tester);
  }

  testWidgets('详情页 → 编辑 → 保存：退出编辑页且详情显示新值', (tester) async {
    await pumpDetail(tester);
    expect(find.text('卡片详情'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑'));
    await _settleIo(tester);
    expect(find.text('编辑卡片'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('card-name-field')), '李四');
    await tester.pump();
    final formList = find.byType(Scrollable).first;
    await tester.dragUntilVisible(
      find.byKey(const Key('card-save')),
      formList,
      const Offset(0, -200),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('card-save')));
    await _awaitSave(tester);

    // 编辑页必须关闭，不能因为控制器被回收而停在原地。
    expect(find.text('编辑卡片'), findsNothing);
    expect(find.text('卡片详情'), findsOneWidget);
    // 详情页跟随保存结果刷新。
    expect(find.text('李四'), findsOneWidget);
    expect(find.text('张三'), findsNothing);

    // 数据确实已写入。
    final stored = await tester.runAsync(() => cards.getById('card-1'));
    expect(stored?.holderName, '李四');
  });

  testWidgets('再次进入编辑页回填的是保存后的值', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.byTooltip('编辑'));
    await _settleIo(tester);
    await tester.enterText(find.byKey(const Key('card-name-field')), '王五');
    await tester.pump();
    final formList = find.byType(Scrollable).first;
    await tester.dragUntilVisible(
      find.byKey(const Key('card-save')),
      formList,
      const Offset(0, -200),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('card-save')));
    await _awaitSave(tester);

    await tester.tap(find.byTooltip('编辑'));
    await _settleIo(tester);
    expect(find.text('编辑卡片'), findsOneWidget);
    // 详情页与编辑表单都显示新值。
    expect(find.text('王五'), findsAtLeastNWidgets(1));
    final nameField = tester.widget<TextFormField>(
      find.byKey(const Key('card-name-field')),
    );
    expect(nameField.controller?.text, '王五');
  });
}
