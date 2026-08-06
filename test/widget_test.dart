import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reservily/main.dart';

const _storageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  setUp(() {
    // flutter_secure_storage has no native implementation in widget tests, so
    // answer every read with "nothing stored" and no-op the writes. This makes
    // the startup restore complete immediately with an empty session.
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (call) async {
      switch (call.method) {
        case 'read':
          return null;
        case 'write':
        case 'delete':
        case 'deleteAll':
        case 'readAll':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, null);
  });

  testWidgets('app boots and shows the login screen when signed out',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ReservilyApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    // No session is stored, so the startup restore completes with an empty
    // session and the router should land on the login screen.
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('ReservilyApp builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ReservilyApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
