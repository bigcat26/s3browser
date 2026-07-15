// 字节数 → 人读格式 (B / KB / MB / GB). 跨多个页面复用:
//   - S3Object.sizeHuman (列表显示)
//   - download_progress_dialog (下载进度)
//   - local_downloads_page (本地文件列表)
//   - 下载前 overwrite 对比 (本地 vs 云端)
//
// 之前散在 3 个文件, 改一个忘一个. 抽到顶层统一.

/// 字节数 → 字符串. size 0 不返回 "0 B" 而是 "—" (跟 S3 文件夹约定一致,
/// 视觉上跟 "有内容" 区分开). 调用方如果想拿 "0 B" 自己特判.
String formatBytesShort(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
