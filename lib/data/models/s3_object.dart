/// S3 Object (文件 / 文件夹) 统一模型.
///
/// AWS ListObjectsV2 返回 CommonPrefix (文件夹) 和 Contents (文件),
/// 这里统一为 [S3Object] + [isFolder] 字段.
library;

import '../../core/format_bytes.dart';

class S3Object {
  /// S3 key (如 "photos/2024/img.jpg" 或 "photos/2024/")
  final String key;

  /// 去掉当前路径前缀后的最后一段 ("photos/2024/img.jpg" → "img.jpg")
  final String name;

  /// 文件大小, 文件夹为 0
  final int size;

  /// 最后修改时间
  final DateTime? lastModified;

  /// ETag
  final String? etag;

  /// true = 文件夹 (CommonPrefix)
  final bool isFolder;

  /// 完整路径 prefix
  final String prefix;

  const S3Object({
    required this.key,
    required this.name,
    required this.size,
    required this.lastModified,
    required this.etag,
    required this.isFolder,
    required this.prefix,
  });

  /// 人读大小 (1.2 MB, 456 KB, etc.). 文件夹 / 0 字节显示 "—".
  /// 实际格式化委托给 [formatBytesShort] (lib/core/format_bytes.dart), 跟
  /// 下载进度 / 本地文件列表共用一份, 改一处生效.
  String get sizeHuman {
    if (isFolder || size == 0) return '—';
    return formatBytesShort(size);
  }

  S3Object copyWithPrefix(String newPrefix) => S3Object(
        key: key,
        name: name,
        size: size,
        lastModified: lastModified,
        etag: etag,
        isFolder: isFolder,
        prefix: newPrefix,
      );

  @override
  String toString() => 'S3Object($key, ${size}B, folder=$isFolder)';
}
