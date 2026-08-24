import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kabao/app/app.dart';

export 'package:flutter/material.dart' show Key, TextFormField, Text;

/// 测试用主密码（仅用于集成测试环境）。
const String testMasterPassword = 'integration-test-pass';

Future<void> pumpFreshApp(WidgetTester tester) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await tester.pumpWidget(const ProviderScope(child: KabaoApp()));
  await tester.pumpAndSettle();
}
