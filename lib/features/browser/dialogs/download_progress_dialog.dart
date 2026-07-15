// 下载进度对话框 (单文件下载专用).
//
// 之前下载是黑盒: 点 "下载" → 沉默几秒到几小时 (大文件) → 一个 snackbar.
// 大文件用户不知道是挂了还是在跑, 也没办法中止. 这个 dialog 解决两件事:
//   1. 实时显示 "已接收 / 总大小" + 百分比, 让用户知道在跑.
//   2. 取消按钮 → CancelToken.cancel() → dio 抛 Cancel 错 → 我们关掉 dialog
//      + 删掉半成品 (由调用方在 catch 里做).
//
// 暂停/续传 (HTTP Range 续传) 这次不做, 原因:
//   - S3 Range 需要 client 跟 server 双方都正确实现, 一些 S3 兼容
//     (RustFS 早期版本) Range 头解析有 bug, 续传不一定能跑.
//   - 暂停语义需要持久化进度, 跨进程续传要换算法 (类似浏览器下载的 .crdownload
//     + 临时文件). 工作量跟 "从 0 实现一个 mini download manager" 相当.
//   - 取消后必须能 resume 才有价值, 但目前取消 → 重新下载, 体验已经够用.

import 'package:flutter/material.dart';

import '../../../core/format_bytes.dart';

/// 下载进度状态机. [DownloadProgressDialog] 监听它的 [Listenable] 重绘.
class DownloadProgress extends ChangeNotifier {
  int _received = 0;
  // 已知文件总字节数. -1 = 服务端没给 Content-Length (chunked / unknown).
  int _total = -1;
  bool _finished = false;

  int get received => _received;
  int get total => _total;
  bool get finished => _finished;

  /// 进度比例 (0.0 - 1.0). [total] 未知 (== -1) 时返回 null, UI 走 indeterminate.
  double? get fraction {
    if (_total <= 0) return null;
    final f = _received / _total;
    return f.clamp(0.0, 1.0);
  }

  /// S3 客户端流式回调一次 (r, t). r 总是累计已下载字节, t 偶尔为 -1
  /// (server 没给 Content-Length). 我们只在 t > 0 时更新 _total,
  /// 避免流式 chunk callback 把 total 覆盖成 -1 让 UI 闪一下 indeterminate.
  void update(int r, int t) {
    _received = r;
    if (t > 0) _total = t;
    notifyListeners();
  }

  /// 标记下载完成 (body 全部接收). 按钮变灰, 调用方拿到控制权去 pop dialog.
  void markFinished() {
    _finished = true;
    notifyListeners();
  }
}

/// 进度条 + 文件名 + 取消按钮. 监听 [progress] 自动重绘.
class DownloadProgressDialog extends StatelessWidget {
  final DownloadProgress progress;
  final String filename;
  final VoidCallback onCancel;

  const DownloadProgressDialog({
    super.key,
    required this.progress,
    required this.filename,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        final frac = progress.fraction;
        final pct = frac == null ? '—' : '${(frac * 100).toStringAsFixed(0)}%';
        return AlertDialog(
          title: const Text('下载中'),
          // 不让用户点 dialog 外面关闭, 必须点取消或等下载完成.
          // 之前 snackbar 时代用户能感觉到 "卡住" 但没控制感, 这次把控制权还回去.
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                if (frac == null)
                  // 总大小未知: indeterminate 进度条, 配合累计已下载大小
                  // (大文件 chunked transfer / server 没返 Content-Length 时走这条)
                  const LinearProgressIndicator()
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: frac),
                  ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      pct,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      formatDownloadSize(progress.received, progress.total),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: progress.finished ? null : onCancel,
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }
}

/// "5.2 MB / 12.4 MB" 或 "5.2 MB" (total 未知时). 复用 [formatBytesShort].
@visibleForTesting
String formatDownloadSize(int received, int total) {
  final r = formatBytesShort(received);
  if (total > 0) {
    return '$r / ${formatBytesShort(total)}';
  }
  return r;
}
