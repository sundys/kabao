import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/features/wallet/domain/document.dart';
import 'package:kabao/features/wallet/presentation/widgets/document_edit_page.dart';
import 'package:kabao/shared/utils/document_id_utils.dart';

void main() {
  DocumentRecord draft() {
    final now = DateTime(2026, 8, 28);
    return DocumentRecord(
      id: 'doc-1',
      categoryId: 'cat-1',
      holderName: '',
      idNumber: '',
      issuer: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  group('DocumentIdFormatting', () {
    test('按 6/8/尾号分组显示', () {
      expect(
        DocumentIdFormatting.groupForDisplay('402356201202263038'),
        '402356 20120226 3038',
      );
    });

    test('位数不足时只切出已有部分', () {
      expect(DocumentIdFormatting.groupForDisplay('4023'), '4023');
      expect(DocumentIdFormatting.groupForDisplay('402356'), '402356');
      expect(DocumentIdFormatting.groupForDisplay('4023562012'), '402356 2012');
      expect(DocumentIdFormatting.groupForDisplay(''), '');
    });

    test('已分组的输入重新分组保持稳定（幂等）', () {
      const grouped = '402356 20120226 3038';
      expect(DocumentIdFormatting.groupForDisplay(grouped), grouped);
    });

    test('normalize 去掉分隔符，复制出去是连续数字', () {
      expect(
        DocumentIdFormatting.normalize('402356 20120226 3038'),
        '402356201202263038',
      );
      expect(DocumentIdFormatting.normalize('4023-5620'), '40235620');
    });

    test('20 位上限内的尾组不会丢数字', () {
      final digits = '4' * 20;
      final grouped = DocumentIdFormatting.groupForDisplay(digits);
      expect(DocumentIdFormatting.normalize(grouped), digits);
    });
  });

  group('DocumentRecord 有效期限', () {
    test('长期有效时展示固定文案，日期字段留空', () {
      final doc = DocumentRecord(
        id: 'd',
        categoryId: 'c',
        holderName: '张三',
        idNumber: '402356201202263038',
        issuer: '中南县公安局',
        validityIsPermanent: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(doc.validityLabel, '长期有效');
      expect(doc.validFrom, isNull);
      expect(doc.validTo, isNull);
    });

    test('普通证件展示起止日期', () {
      final doc = DocumentRecord(
        id: 'd',
        categoryId: 'c',
        holderName: '张三',
        idNumber: '402356201202263038',
        issuer: '中南县公安局',
        validFrom: DateTime(2022, 2, 25),
        validTo: DateTime(2038, 2, 25),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(doc.validityLabel, '2022.02.25 - 2038.02.25');
    });

    test('两个日期都为空且未勾选长期有效时文案为空', () {
      final doc = DocumentRecord(
        id: 'd',
        categoryId: 'c',
        holderName: '',
        idNumber: '1',
        issuer: '',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(doc.validityLabel, '');
    });

    test('payload 往返保留长期有效标记与中文字段（无乱码）', () {
      final doc = DocumentRecord(
        id: 'd',
        categoryId: 'c',
        holderName: '张三',
        idNumber: '402356201202263038',
        issuer: '中南县公安局',
        validityIsPermanent: true,
        remark: '长期有效的居民身份证，备注含中文与符号：（）—',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final restored = DocumentRecord.fromJsonFields(
        metadata: {
          'id': 'd',
          'category_id': 'c',
          'created_at': DateTime(2026).millisecondsSinceEpoch,
          'updated_at': DateTime(2026).millisecondsSinceEpoch,
          'model_version': 1,
        },
        payloadJson: doc.payloadJson(),
      );
      expect(restored.validityIsPermanent, isTrue);
      expect(restored.validityLabel, '长期有效');
      expect(restored.holderName, '张三');
      expect(restored.issuer, '中南县公安局');
      expect(restored.remark, '长期有效的居民身份证，备注含中文与符号：（）—');
    });

    test('旧数据缺少 validityPermanent 字段时按非长期有效解析', () {
      final restored = DocumentRecord.fromJsonFields(
        metadata: {
          'id': 'd',
          'category_id': 'c',
          'created_at': 0,
          'updated_at': 0,
          'model_version': 1,
        },
        payloadJson:
            '{"holderName":"张三","idNumber":"402356201202263038",'
            '"issuer":"中南县公安局","validFrom":"2022.02.25",'
            '"validTo":"2038.02.25","remark":null}',
      );
      expect(restored.validityIsPermanent, isFalse);
      expect(restored.validityLabel, '2022.02.25 - 2038.02.25');
    });
  });

  group('证件录入表单', () {
    Future<void> pumpEdit(WidgetTester tester, DocumentRecord doc) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DocumentEditPage(document: doc, isNew: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('证件号连续输入时自动按 6/8/尾号分组', (tester) async {
      await pumpEdit(tester, draft());

      await tester.enterText(
        find.byKey(const Key('doc-id-number')),
        '402356201202263038',
      );
      await tester.pump();

      expect(find.text('402356 20120226 3038'), findsOneWidget);
    });

    testWidgets('勾选长期有效后清空日期并禁止录入', (tester) async {
      await pumpEdit(tester, draft());

      await tester.enterText(
        find.byKey(const Key('doc-validity')),
        '20220225'
        '20380225',
      );
      await tester.pump();
      expect(find.text('2022.02.25-2038.02.25'), findsOneWidget);

      await tester.tap(find.byKey(const Key('doc-permanent-validity')));
      await tester.pumpAndSettle();

      // 日期被清空。
      expect(find.text('2022.02.25-2038.02.25'), findsNothing);
      // 输入框被禁用。
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('doc-validity')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.enabled, isFalse);
      expect(find.text('长期有效'), findsOneWidget);
    });

    testWidgets('取消勾选后重新允许录入日期', (tester) async {
      await pumpEdit(tester, draft());

      await tester.tap(find.byKey(const Key('doc-permanent-validity')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('doc-permanent-validity')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('doc-validity')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.enabled, isTrue);
    });

    testWidgets('已有长期有效证件进入编辑页时勾选框默认选中', (tester) async {
      final now = DateTime(2026, 8, 28);
      await pumpEdit(
        tester,
        DocumentRecord(
          id: 'doc-2',
          categoryId: 'cat-1',
          holderName: '张三',
          idNumber: '402356201202263038',
          issuer: '中南县公安局',
          validityIsPermanent: true,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final checkbox = tester.widget<CheckboxListTile>(
        find.byKey(const Key('doc-permanent-validity')),
      );
      expect(checkbox.value, isTrue);
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('doc-validity')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.enabled, isFalse);
    });

    testWidgets('有效期限输入框拒绝中文，不产生乱码', (tester) async {
      await pumpEdit(tester, draft());

      await tester.enterText(find.byKey(const Key('doc-validity')), '长期有效');
      await tester.pump();

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('doc-validity')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller?.text, '');
    });
  });
}
