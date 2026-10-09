import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/app/providers/repositories_providers.dart';
import 'package:kabao/core/crypto/aead_cipher.dart';
import 'package:kabao/core/database/encrypted_database.dart';
import 'package:kabao/features/wallet/data/card_repository.dart';
import 'package:kabao/features/wallet/data/category_repository.dart';
import 'package:kabao/features/wallet/data/document_repository.dart';
import 'package:kabao/features/wallet/domain/models.dart';
import 'package:kabao/features/wallet/presentation/pages/category_detail_page.dart';
import 'package:kabao/features/wallet/presentation/widgets/wallet_search_button.dart';
import 'package:kabao/features/wallet/presentation/widgets/wallet_search_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 仓储读写走真实异步 I/O，测试用的假时钟不会推进它们；必须在
/// [WidgetTester.runAsync] 内让事件循环跑起来，再回到假时钟渲染。
Future<void> _settleRepositoryReads(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 打开右下角搜索面板：弹出动画在假时钟下推进，结果读取在真实事件循环内完成。
Future<void> _openSearchSheet(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byType(WalletSearchButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });
  await tester.pump();
}

/// 分类页的入口位置与搜索作用域：
/// 添加按钮移到标题右侧，右下角改为搜索入口，搜索只覆盖当前分类。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late EncryptedDatabase db;
  late CategoryRepository categories;
  late CardRepository cards;
  late DocumentRepository documents;
  late BankCategory target;
  final dek = AeadCipher().generateKey(32);

  Future<BankCategory> seedCategory(String id, String name) async {
    final now = DateTime.now();
    final category = BankCategory(
      id: id,
      cardType: CardType.debit,
      name: name,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
    await categories.save(category);
    return category;
  }

  Future<void> seedCard(String id, String categoryId, String number) async {
    final now = DateTime.now();
    await cards.save(
      CardRecord(
        id: id,
        categoryId: categoryId,
        cardType: CardType.debit,
        cardNumber: number,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

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

    target = await seedCategory('cat-target', '工商银行');
    await seedCard('card-target', target.id, '6222000012345678');
    final other = await seedCategory('cat-other', '招商银行');
    await seedCard('card-other', other.id, '6225000098765432');
  });

  tearDown(() => db.close());

  Future<void> pumpCategory(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryRepositoryProvider.overrideWithValue(categories),
          cardRepositoryProvider.overrideWithValue(cards),
          documentRepositoryProvider.overrideWithValue(documents),
        ],
        child: MaterialApp(home: CategoryDetailPage(category: target)),
      ),
    );
    await _settleRepositoryReads(tester);
  }

  ProviderContainer containerWithRepositories() {
    final container = ProviderContainer(
      overrides: [
        categoryRepositoryProvider.overrideWithValue(categories),
        cardRepositoryProvider.overrideWithValue(cards),
        documentRepositoryProvider.overrideWithValue(documents),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('分类作用域的搜索结果只包含该分类的记录', () async {
    final container = containerWithRepositories();

    final scoped = await container.read(
      walletSearchResultsProvider(target.id).future,
    );
    expect(scoped.map((result) => result.recordId), ['card-target']);

    // 首页入口不传分类，保持全局搜索。
    final global = await container.read(
      walletSearchResultsProvider(null).future,
    );
    expect(global.map((result) => result.recordId).toSet(), {
      'card-target',
      'card-other',
    });
  });

  testWidgets('添加按钮移至标题右侧，不再使用右下角悬浮按钮', (tester) async {
    await pumpCategory(tester);

    expect(find.byType(FloatingActionButton), findsNothing);

    final addButton = find.byKey(ValueKey('add-card-${target.id}'));
    expect(addButton, findsOneWidget);
    expect(
      tester.getCenter(addButton).dx,
      greaterThan(tester.getCenter(find.text('工商银行')).dx),
    );
  });

  testWidgets('右下角搜索入口只搜索当前分类', (tester) async {
    await pumpCategory(tester);

    final searchButton = find.byType(WalletSearchButton);
    expect(searchButton, findsOneWidget);
    final rect = tester.getRect(searchButton);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.center.dx, greaterThan(size.width * 0.75));
    expect(rect.center.dy, greaterThan(size.height * 0.75));

    await _openSearchSheet(tester);

    // 空查询下列出作用域内的全部记录：仅本分类的一张卡片。
    final sheetResults = find.descendant(
      of: find.byType(WalletSearchSheet),
      matching: find.byType(ListTile),
    );
    expect(sheetResults, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WalletSearchSheet),
        matching: find.textContaining('6222 **** **** 5678'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(WalletSearchSheet),
        matching: find.textContaining('5432'),
      ),
      findsNothing,
    );
  });
}
