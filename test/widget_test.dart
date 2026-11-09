import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/views/widgets/logo_lockup.dart';
import 'package:stylelink/widgets/custom_avatar.dart';

void main() {
  testWidgets('brand lockup and avatar fallback render without Supabase',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              LogoLockup(compact: true),
              CustomAvatar(displayName: 'Awa N.', radius: 20),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(LogoLockup), findsOneWidget);
    expect(find.byType(CustomAvatar), findsOneWidget);
    // Logo wordmark and the avatar's initials fallback.
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
    expect(find.text('AN'), findsOneWidget);
  });
}
