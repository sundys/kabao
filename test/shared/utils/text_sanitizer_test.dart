import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/shared/utils/text_sanitizer.dart';

void main() {
  test('清理零宽字符并保留可见内容', () {
    expect(TextSanitizer.clean('\u200B张三\uFEFF'), '张三');
  });

  test('仅含不可见字符时返回空', () {
    expect(TextSanitizer.clean('\u200B\uFEFF'), isNull);
    expect(TextSanitizer.clean(null), isNull);
  });
}
