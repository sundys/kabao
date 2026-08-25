import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/shared/utils/card_number_utils.dart';
import 'package:kabao/shared/validation/validators.dart';

void main() {
  group('卡号规范化与展示', () {
    test('去除空格与常见分隔符', () {
      expect(
        CardNumberValidation.normalize('6222 0000 1234 5678'),
        '6222000012345678',
      );
      expect(CardNumberValidation.normalize('6222-0000-1234'), '622200001234');
    });

    test('拒绝非数字、空输入与超长输入', () {
      expect(CardNumberValidation.normalize(''), isNull);
      expect(CardNumberValidation.normalize('6222abcd'), isNull);
      expect(CardNumberValidation.normalize('1' * 20), isNull);
      expect(CardNumberValidation.normalize('1' * 19), '1' * 19);
    });

    test('按 4 位分组显示，最后一组可不足 4 位', () {
      expect(
        CardNumberValidation.groupForDisplay('6222000012345678'),
        '6222 0000 1234 5678',
      );
      expect(CardNumberValidation.groupForDisplay('12345'), '1234 5');
    });

    test('列表脱敏显示', () {
      expect(
        CardNumberValidation.maskForList('6222000012345678'),
        '6222 **** **** 5678',
      );
      expect(
        CardNumberValidation.maskForList('123456789012'),
        '1234 **** 9012',
      );
      expect(CardNumberValidation.maskForList('12345678'), '**** 5678');
      expect(CardNumberValidation.maskForList('1234567'), '*******');
    });
  });

  group('字段校验', () {
    test('银行分类名称：仅中文且最多 4 字', () {
      expect(Validators.categoryName('工商银行'), isNull);
      expect(Validators.categoryName(null), isNotNull);
      expect(Validators.categoryName('   '), isNotNull);
      expect(Validators.categoryName('工商银行5'), isNotNull);
      expect(Validators.categoryName('Bank of 工商'), isNotNull);
      expect(Validators.categoryName('工行'), isNull);
      expect(Validators.categoryName('五个中文字啊'), isNotNull);
    });

    test('有效期 MM/YY', () {
      expect(Validators.expiry(null), isNull);
      expect(Validators.expiry(''), isNull);
      expect(Validators.expiry('08/29'), isNull);
      expect(Validators.expiry('00/29'), isNotNull);
      expect(Validators.expiry('13/29'), isNotNull);
      expect(Validators.expiry('8/29'), isNotNull);
      expect(Validators.expiry('0829'), isNotNull);
    });

    test('CVV 为 3 位数字', () {
      expect(Validators.cvv(null), isNull);
      expect(Validators.cvv('123'), isNull);
      expect(Validators.cvv('1234'), isNotNull);
      expect(Validators.cvv('12'), isNotNull);
      expect(Validators.cvv('12345'), isNotNull);
      expect(Validators.cvv('12a'), isNotNull);
    });

    test('U 盾到期日 yyyy/M/d 且必须为真实日期', () {
      expect(Validators.uShieldDate(null), isNull);
      expect(Validators.uShieldDate('2027/3/8'), isNull);
      expect(Validators.uShieldDate('2027/12/31'), isNull);
      expect(Validators.uShieldDate('2027/2/30'), isNotNull);
      expect(Validators.uShieldDate('2027/13/1'), isNotNull);
      expect(Validators.uShieldDate('27/3/8'), isNotNull);
      expect(Validators.uShieldDate('2027-3-8'), isNotNull);
    });

    test('备注长度限制且保留换行', () {
      expect(Validators.note(null), isNull);
      expect(Validators.note('第一行\n第二行'), isNull);
      expect(Validators.note('字' * 501), isNotNull);
      expect(Validators.note('字' * 500), isNull);
    });
  });
}
