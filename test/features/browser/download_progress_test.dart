// 下载进度对话框的 ChangeNotifier + 字节格式化测试.
//
// DownloadProgress 是 dialog 的状态机, 测试覆盖:
//   - 初始值 (0 / -1 / false)
//   - update 累计语义 (received 单调增, total 在 > 0 时设一次不再变)
//   - 边界: total=-1 不让 fraction 变 0 (avoid divide-by-zero / 跳 indeterminate)
//   - markFinished 只置 finished 标志
//   - notifyListeners 在每次 update / markFinished 触发
//
// formatDownloadSize 是 dialog 用的纯函数, 测它避免 toast 里出现 "0 B / -1 B"
// 这种呆字符串.

import 'package:s3browser/features/browser/dialogs/download_progress_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadProgress', () {
    test('初始值: received=0, total=-1 (未知), finished=false, fraction=null', () {
      final p = DownloadProgress();
      expect(p.received, 0);
      expect(p.total, -1);
      expect(p.finished, isFalse);
      expect(p.fraction, isNull); // total=-1 → indeterminate
    });

    test('update(r, t>0) 设 received + total + fraction = r/t', () {
      final p = DownloadProgress();
      p.update(50, 100);
      expect(p.received, 50);
      expect(p.total, 100);
      expect(p.fraction, 0.5);
    });

    test('update 累计: 多次 update 反映最新值', () {
      final p = DownloadProgress();
      p.update(25, 100);
      p.update(50, 100);
      p.update(75, 100);
      expect(p.received, 75);
      expect(p.fraction, 0.75);
    });

    test('update with t=-1 (server 还没给 Content-Length) 不覆盖 total', () {
      // 场景: S3 GET 开始先发不带 Content-Length 的 chunk, dio onReceiveProgress
      // 调 (r, -1). 我们不能在 t<=0 时把已知的 total 覆盖成 -1, UI 会闪一下
      // indeterminate.
      final p = DownloadProgress();
      p.update(10, 100); // 设了 total=100
      p.update(20, -1); // chunked callback, 不应改 total
      expect(p.total, 100, reason: 'total 保持 100, 没被 -1 覆盖');
      expect(p.received, 20);
      expect(p.fraction, 0.2);
    });

    test('fraction 在 r > t 时 clamp 到 1.0 (server 报 total 偏小也安全)', () {
      // 边界 case: server Content-Length 给小了 (e.g. 压缩 / multipart 包装),
      // 我们已下载字节数 > total. UI 不该爆.
      final p = DownloadProgress();
      p.update(150, 100);
      expect(p.fraction, 1.0);
    });

    test('markFinished 只置 finished, 不改 received/total/fraction', () {
      final p = DownloadProgress();
      p.update(80, 100);
      p.markFinished();
      expect(p.finished, isTrue);
      expect(p.received, 80);
      expect(p.total, 100);
      expect(p.fraction, 0.8);
    });

    test('notifyListeners 每次 update / markFinished 触发', () {
      // ListenableBuilder 靠这个重绘. 漏一次 → UI 卡住不更新.
      final p = DownloadProgress();
      int callCount = 0;
      p.addListener(() => callCount++);
      p.update(50, 100);
      expect(callCount, 1);
      p.update(75, 100);
      expect(callCount, 2);
      p.markFinished();
      expect(callCount, 3);
    });
  });

  group('formatDownloadSize', () {
    test('total=已知 → "received / total" 形式', () {
      expect(formatDownloadSize(0, 100), '0 B / 100 B');
      expect(formatDownloadSize(1024, 2048), '1.0 KB / 2.0 KB');
      // 5.0 MB / 12.4 MB 这种典型 case
      expect(
        formatDownloadSize(5 * 1024 * 1024, 12 * 1024 * 1024 + 414 * 1024),
        '5.0 MB / 12.4 MB',
      );
    });

    test('total=未知 (-1) → 只显示 received', () {
      // chunked transfer / server 没返 Content-Length
      expect(formatDownloadSize(2 * 1024 * 1024, -1), '2.0 MB');
      expect(formatDownloadSize(512, -1), '512 B');
    });

    test('GB 级别 (大文件下载) → 1 位小数', () {
      // 1.5 GB / 3.0 GB
      final g = 1024 * 1024 * 1024;
      expect(
        formatDownloadSize((1.5 * g).round(), (3.0 * g).round()),
        '1.50 GB / 3.00 GB',
      );
    });
  });
}
