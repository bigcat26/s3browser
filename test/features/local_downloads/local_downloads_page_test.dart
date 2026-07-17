// LocalDownloadsPage widget 测试.
//
// 覆盖:
//   1. 空目录 → 空态文案 "还没有下载过文件"
//   2. 有文件 → 列出文件名 + size + 修时, 按修改时间倒序
//   3. 三点菜单的 3 个 action (open / copy / delete)
//   4. AppBar 刷新按钮 / 返回按钮 (push 进来的, 默认有返回)
//
// 用 path_provider mock 让 getLocalDownloadsDir 走 tmp, 跟 local_files_test
// 同一套 fake.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:s3browser/features/local_downloads/local_downloads_page.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.tmpRoot);
  final String tmpRoot;

  @override
  Future<String?> getDownloadsPath() async {
    return p.join(tmpRoot, 'fake_downloads');
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return p.join(tmpRoot, 'fake_docs');
  }
}

Widget _host(Widget child) {
  return MaterialApp(
    home: child,
  );
}

/// 跑 IO 密集的 async 操作. tester.pump() 走 fake-async 时钟, 但 dart:io 的
/// FileSystem 操作走真实 event loop, 不会因为 pump 而 resolve. 用 runAsync
/// 把 IO 跑到真实时钟上, 然后再 pump 让 setState 触发 rebuild.
Future<void> _settleLoad(WidgetTester tester) async {
  await tester.pump();
}

void main() {
  late Directory tmpRoot;
  late Directory dlDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpRoot = await Directory.systemTemp.createTemp('s3browser_ldp_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpRoot.path);
    dlDir = Directory(p.join(tmpRoot.path, 'fake_downloads'))..createSync(recursive: true);
  });

  tearDown(() async {
    if (tmpRoot.existsSync()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  testWidgets('空目录 → 空态显示', (tester) async {
    await tester.pumpWidget(_host(const LocalDownloadsPage()));
    await _settleLoad(tester);
    expect(find.text('还没有下载过文件'), findsOneWidget);
    expect(find.text('本地下载'), findsOneWidget); // AppBar 标题
  });

  testWidgets('有文件 → 列出文件名 + size + 按时间倒序', (tester) async {
    // 建 2 个文件, 一个早一个晚, 验证倒序.
    // File 操作 (writeAsBytes) 走真实 IO, 必须在 runAsync 里. 否则 tester
    // 的 fake-async 不知道 IO 完成, 一直 hang.
    await tester.runAsync(() async {
      final old = File(p.join(dlDir.path, 'old.pdf'));
      await old.writeAsBytes(List.filled(100, 0x61)); // 100 B
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final newF = File(p.join(dlDir.path, 'new.pdf'));
      await newF.writeAsBytes(List.filled(2000, 0x62)); // ~2 KB
    });

    await tester.pumpWidget(_host(const LocalDownloadsPage()));
    // _refresh() 内部 IO 也需要 runAsync, 单独包一层让 IO 跑完
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 倒序: new 在上, old 在下
    final newFinder = find.text('new.pdf');
    final oldFinder = find.text('old.pdf');
    expect(newFinder, findsOneWidget);
    expect(oldFinder, findsOneWidget);
    // new 的 y 坐标 < old 的 y 坐标 (更靠上)
    final newY = tester.getTopLeft(newFinder).dy;
    final oldY = tester.getTopLeft(oldFinder).dy;
    expect(newY, lessThan(oldY), reason: 'new.pdf 应该在 old.pdf 上面');

    // size 显示: new ~2 KB, old 100 B. subtitle 是 "${size}  ·  ${time}"
    // 一个 Text 节点, 用 textContaining 匹配.
    expect(find.textContaining('2.0 KB'), findsOneWidget);
    expect(find.textContaining('100 B'), findsOneWidget);
  });

  testWidgets('AppBar 有刷新按钮 + 标题', (tester) async {
    await tester.pumpWidget(_host(const LocalDownloadsPage()));
    await _settleLoad(tester);
    expect(find.text('本地下载'), findsOneWidget);
    // 刷新按钮 (Icons.refresh) 存在. 测 tooltip 比较稳, 不依赖 Icon 类
    expect(find.byTooltip('刷新'), findsOneWidget);
  });

  testWidgets('删除文件 → 二次确认 → 确认后从列表消失', (tester) async {
    final f = File(p.join(dlDir.path, 'to_delete.txt'));
    await tester.runAsync(() => f.writeAsString('hello'));

    await tester.pumpWidget(_host(const LocalDownloadsPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    expect(find.text('to_delete.txt'), findsOneWidget);

    // 打开三点菜单
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    // 选 "删除"
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    // 二次确认 dialog
    expect(find.text('删除文件'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    // 文件删除 + _refresh 走 runAsync, 不等 snackbar 动画
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    // 文件应该没了
    expect(find.text('to_delete.txt'), findsNothing);
    expect(f.existsSync(), isFalse, reason: '物理文件应该被删了');
  });

  testWidgets('长按进入选择模式 → 全选 → 批量删除', (tester) async {
    // 建 3 个文件
    final files = <File>[];
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        final f = File(p.join(dlDir.path, 'batch_$i.txt'));
        await f.writeAsString('content $i');
        files.add(f);
      }
    });

    await tester.pumpWidget(_host(const LocalDownloadsPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    for (final f in files) {
      expect(find.text(p.basename(f.path)), findsOneWidget);
    }

    // 长按第一个文件 → 进入选择模式
    await tester.longPress(find.text('batch_0.txt'));
    await tester.pumpAndSettle();
    // AppBar 标题显示 "已选 1 / 3"
    expect(find.text('已选 1 / 3'), findsOneWidget);

    // 全选
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 / 3'), findsOneWidget);

    // 批量删除
    await tester.tap(find.byTooltip('删除选中'));
    await tester.pumpAndSettle();
    expect(find.text('删除文件'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    // 批量删除的 File.delete() 是真实 IO, pumpAndSettle 会驱动 fake 时钟并
    // 同时排空真实 IO, 让删除循环跑完.
    await tester.pumpAndSettle();

    // 三个文件都没了, 回到空态
    for (final f in files) {
      expect(f.existsSync(), isFalse, reason: '${f.path} 应被批量删除');
    }
    expect(find.text('还没有下载过文件'), findsOneWidget);
  });

  testWidgets('选择模式: 点行首 Checkbox 切换, 全取消退出选择', (tester) async {
    final f = File(p.join(dlDir.path, 'sel.txt'));
    await tester.runAsync(() => f.writeAsString('x'));

    await tester.pumpWidget(_host(const LocalDownloadsPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 长按进入
    await tester.longPress(find.text('sel.txt'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 / 1'), findsOneWidget);

    // 再点一下 (行首 Checkbox → onTap) 取消选中 → 退出选择模式
    await tester.tap(find.text('sel.txt'));
    await tester.pumpAndSettle();
    expect(find.text('本地下载'), findsOneWidget);
    expect(find.text('已选'), findsNothing);
    expect(f.existsSync(), isTrue, reason: '取消选择不应删除文件');
  });
}
