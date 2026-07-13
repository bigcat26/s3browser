// S3 Browser 基础 smoke test.
//
// 完整业务测试 (S3 协议 mock) 留到后续 mockito / dio_adapter 阶段.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:s3browser/main.dart';
import 'package:s3browser/features/servers/server_list_page.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App boots into ServerListPage when no servers configured',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: S3BrowserApp(),
      ),
    );
    // 多次 pump 让 serverListProvider 的 load() 异步完成, 跳到 data 状态
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(ServerListPage), findsOneWidget);
  });
}
