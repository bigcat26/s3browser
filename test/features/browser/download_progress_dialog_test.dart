// DownloadProgressDialog 的 widget 测试.
//
// 重点:
//   1. 取消按钮真的回调 onCancel (用户点完确实能让 dio 终止).
//   2. 进度条数值随 progress.update 实时变化 (ListenableBuilder 接通).
//   3. markFinished 后取消按钮禁用, 防止 "已完成" 状态再触发 cancel.
//
// 之前没这个 widget test, dialog 的 ListenableBuilder 接错 / 取消按钮 onPressed
// 漏写都看不出来, 只能跑到手机上手点.

import 'package:flutter/material.dart';
import 'package:s3browser/features/browser/dialogs/download_progress_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  group('DownloadProgressDialog', () {
    testWidgets('显示文件名', (tester) async {
      final progress = DownloadProgress();
      await tester.pumpWidget(_host(DownloadProgressDialog(
        progress: progress,
        filename: 'hello.apk',
        onCancel: () {},
      )));
      expect(find.text('hello.apk'), findsOneWidget);
    });

    testWidgets('total=-1 时显示 indeterminate (找不到带 value 的进度条)',
        (tester) async {
      final progress = DownloadProgress();
      progress.update(1024, -1);
      await tester.pumpWidget(_host(DownloadProgressDialog(
        progress: progress,
        filename: 'f',
        onCancel: () {},
      )));
      // 进度条存在, 但没 value (indeterminate). 没法直接 assert,
      // 至少确认 LinearProgressIndicator 存在, 且 received 文本显示 KB.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('1.0 KB'), findsOneWidget);
    });

    testWidgets('update(50, 100) → 进度条 50% + "50%" + "X / Y" 文本',
        (tester) async {
      final progress = DownloadProgress();
      progress.update(50, 100);
      await tester.pumpWidget(_host(DownloadProgressDialog(
        progress: progress,
        filename: 'f',
        onCancel: () {},
      )));
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('50 B / 100 B'), findsOneWidget);
      // LinearProgressIndicator with value=0.5
      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, 0.5);
    });

    testWidgets('update 触发 ListenableBuilder 重绘', (tester) async {
      // 验证 dialog 真的在监听 progress. 漏写 ListenableBuilder → 进度条
      // 永远卡在初始值.
      final progress = DownloadProgress();
      // 初始先给个 known total, 这样 update 走 value 路径, 百分比可见
      progress.update(25, 100);
      await tester.pumpWidget(_host(DownloadProgressDialog(
        progress: progress,
        filename: 'f',
        onCancel: () {},
      )));
      expect(find.text('25%'), findsOneWidget);
      progress.update(75, 100);
      await tester.pump();
      expect(find.text('75%'), findsOneWidget);
    });

    testWidgets('点取消按钮 → onCancel 被调', (tester) async {
      final progress = DownloadProgress();
      int cancelCalls = 0;
      await tester.pumpWidget(_host(DownloadProgressDialog(
        progress: progress,
        filename: 'f',
        onCancel: () => cancelCalls++,
      )));
      await tester.tap(find.text('取消'));
      await tester.pump();
      expect(cancelCalls, 1);
    });

    testWidgets('markFinished 后取消按钮禁用', (tester) async {
      // 完成态再点取消没意义 (已经下载完了, cancel 是空操作).
      // 禁用防误触, 避免 dio 已 finished 但 cancelToken 还没 dispose 时
      // 用户误点导致后续请求被误终止.
      final progress = DownloadProgress();
      int cancelCalls = 0;
      progress.update(100, 100);
      progress.markFinished();
      await tester.pumpWidget(_host(DownloadProgressDialog(
        progress: progress,
        filename: 'f',
        onCancel: () => cancelCalls++,
      )));
      final btn = tester.widget<TextButton>(find.ancestor(
        of: find.text('取消'),
        matching: find.byType(TextButton),
      ));
      expect(btn.onPressed, isNull,
          reason: 'finished 状态取消按钮 onPressed 应为 null');
      // tap 不会触发 (Flutter 测试中 disabled button tap 无效果)
      await tester.tap(find.text('取消'));
      await tester.pump();
      expect(cancelCalls, 0);
    });
  });
}
