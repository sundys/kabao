import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabao/app/app.dart';
import 'package:kabao/features/auth/logic/auth_controller.dart';

import 'helpers/in_memory_secure_store.dart';

void main() {
  testWidgets('首次启动进入主密码创建页', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(InMemorySecureStore()),
        ],
        child: const KabaoApp(),
      ),
    );
    // AuthController performs an async initialization check.
    await tester.pumpAndSettle();

    expect(find.text('创建主密码'), findsOneWidget);
  });
}
