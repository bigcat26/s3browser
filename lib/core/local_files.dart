// 本地文件路径 helper.
//
// 之前下载走 getApplicationDocumentsDirectory()/s3browser/bucket/, 这个路径:
//   - 手机上: app 沙盒内, 用户根本找不到, 想分享 / 打开都得走 app 内机制
//   - macOS:  ~/Library/Containers/.../s3browser/, Finder 不直接显示
// 跟用户 "下载" 的预期完全不符.
//
// 改成:
//   - Android: /sdcard/Download/  (系统 Downloads 公共目录, /sdcard 是
//     /storage/emulated/0 的软链; 用户在文件管理 / 相册 / "我的下载" 都能看到)
//   - macOS:   ~/Downloads/  (跟 Safari / Chrome 下载行为一致)
//   - iOS:     app Documents/Downloads/  (iOS 没公共 Downloads, 隐私模型要求
//              app 数据隔离. 用户想导出走 AirDrop / iTunes File Sharing)
//
// path_provider 的 getDownloadsDirectory():
//   - Android: 返回公共 Downloads 路径 (/sdcard/Download, null 在某些
//     scoped storage 设备上)
//   - iOS:     返回 app Documents (per package docs)
//   - macOS:   返回 ~/Downloads
// 走它 + 兜底 (null 时退到 app Documents/downloads) 跨平台一套逻辑.

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 跨平台本地 Downloads 目录. 一定返回一个**存在**的目录 (不存在会自动创建).
///
/// 抛 IOException 如果创建失败 (e.g. Android 11+ scoped storage 没权限时).
/// 调用方应在 try/catch 里处理, 给用户友好提示 ("无法访问 Downloads 文件夹").
Future<Directory> getLocalDownloadsDir() async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    // Android 11+ scoped storage / 沙盒限制等场景, getDownloadsDirectory 内部
    // 可能抛 PlatformException. 当作 null 处理, 走兜底.
    dir = null;
  }
  if (dir != null) {
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
  // 兜底: app 内 Documents/downloads, iOS 跟权限受限的 Android 走这条.
  final appDir = await getApplicationDocumentsDirectory();
  final fallback = Directory(p.join(appDir.path, 'downloads'));
  if (!fallback.existsSync()) {
    fallback.createSync(recursive: true);
  }
  return fallback;
}

/// 给一个文件名, 返回它在本地 Downloads 里的完整路径. 目录不存在会自动建.
///
/// [name] 不要带路径分隔符, 防止用户在 S3 key 里塞 "../" 越权写到 Downloads
/// 之外的位置. 上层 _downloadSingle 已经用 obj.name (basename), 调这里安全.
/// 这里再防御一次, 万一上层传错了, 也只走 basenamize.
Future<File> getLocalDownloadPath(String name) async {
  // 防 path traversal: 剥掉所有路径分隔符, 只留 basename.
  final safeName = p.basename(name);
  if (safeName.isEmpty || safeName == '.' || safeName == '..') {
    throw ArgumentError('invalid download name: $name');
  }
  final dir = await getLocalDownloadsDir();
  return File(p.join(dir.path, safeName));
}
