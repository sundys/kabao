import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/shared/widgets/input_formatters.dart';

void main() {
  TextEditingValue input(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  group('SeparatorAutoFormatter', () {
    test('MM/YY：逐位输入自动补 /', () {
      const f = SeparatorAutoFormatter([2, 2], ['/']);
      var value = const TextEditingValue(text: '');
      for (final ch in '0829'.split('')) {
        value = f.formatEditUpdate(value, input(value.text + ch));
      }
      expect(value.text, '08/29');
    });

    test('yyyy/MM/dd：逐位输入自动补 /', () {
      const f = SeparatorAutoFormatter([4, 2, 2], ['/', '/', '/']);
      var value = const TextEditingValue(text: '');
      for (final ch in '20270308'.split('')) {
        value = f.formatEditUpdate(value, input(value.text + ch));
      }
      expect(value.text, '2027/03/08');
    });

    test('yyyy.MM.dd-yyyy.MM.dd：完整 16 位正确分组', () {
      const f = SeparatorAutoFormatter(
        [4, 2, 2, 4, 2, 2],
        ['.', '.', '-', '.', '.'],
      );
      var value = const TextEditingValue(text: '');
      for (final ch in '2020120320280511'.split('')) {
        value = f.formatEditUpdate(value, input(value.text + ch));
      }
      expect(value.text, '2020.12.03-2028.05.11');
    });

    test('输入到第 11 位时年份保持连续（回归：20.28.05）', () {
      const f = SeparatorAutoFormatter(
        [4, 2, 2, 4, 2, 2],
        ['.', '.', '-', '.', '.'],
      );
      final digits = '2020120320280511';
      final atEleven = digits.substring(0, 11);
      final result = f.formatEditUpdate(input(atEleven), input(atEleven));
      expect(result.text, '2020.12.03-202');
    });

    test('超过最大位数时拒绝新输入', () {
      const f = SeparatorAutoFormatter([2, 2], ['/']);
      // 真实流程中 oldValue 已是被格式化过的文本。
      final full = f.formatEditUpdate(input('08/29'), input('08/299'));
      expect(full.text, '08/29');
    });

    test('删除时正常回退（重建自纯数字）', () {
      const f = SeparatorAutoFormatter(
        [4, 2, 2, 4, 2, 2],
        ['.', '.', '-', '.', '.'],
      );
      // 模拟从 "2020.12.03-2028.05.11" 删除最后一个字符
      final afterDelete = f.formatEditUpdate(
        input('2020.12.03-2028.05.11'),
        input('2020.12.03-2028.05.1'),
      );
      expect(afterDelete.text, '2020.12.03-2028.05.1');
    });
  });

  group('BoundedSeparatorAutoFormatter', () {
    test('有效期月份限制为 01-12，同时保留自动补 /', () {
      const f = BoundedSeparatorAutoFormatter(
        [2, 2],
        ['/'],
        minValues: [1, null],
        maxValues: [12, null],
      );
      var value = const TextEditingValue(text: '');
      for (final ch in '0829'.split('')) {
        value = f.formatEditUpdate(value, input(value.text + ch));
      }
      expect(value.text, '08/29');
      expect(f.formatEditUpdate(input('1'), input('13')).text, '1');
    });

    test('U 盾日期限制年份、月份和日期范围，同时保留自动补 /', () {
      const f = BoundedSeparatorAutoFormatter(
        [4, 2, 2],
        ['/', '/', '/'],
        minValues: [2000, 1, 1],
        maxValues: [2999, 12, 31],
        requiredPrefixes: ['2', null, null],
      );
      var value = const TextEditingValue(text: '');
      for (final ch in '20270308'.split('')) {
        value = f.formatEditUpdate(value, input(value.text + ch));
      }
      expect(value.text, '2027/03/08');
      expect(f.formatEditUpdate(input(''), input('3689')).text, '');
      expect(
        f.formatEditUpdate(input('2027/1'), input('2027/13')).text,
        '2027/1',
      );
      expect(
        f.formatEditUpdate(input('2027/12/3'), input('2027/12/32')).text,
        '2027/12/3',
      );
    });
  });
}
