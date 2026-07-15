// formatBytesShort 测试.
//
// 之前散在 3 个文件: S3Object.sizeHuman / download_progress_dialog 内部
// _fmtBytes / 这次新增的 local_downloads_page. 抽到顶层 format_bytes.dart
// 之后, 改一处生效, 这里测覆盖各档位的边界.

import 'package:s3browser/core/format_bytes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytesShort — B 档 (< 1024)', () {
    test('0 字节 → "0 B" (跟 S3Object "—" 区分, 调用方自己特判)', () {
      expect(formatBytesShort(0), '0 B');
    });
    test('1 字节 → "1 B"', () {
      expect(formatBytesShort(1), '1 B');
    });
    test('1023 字节 → "1023 B"', () {
      expect(formatBytesShort(1023), '1023 B');
    });
  });

  group('formatBytesShort — KB 档 (1024 - 1MB)', () {
    test('1024 → "1.0 KB"', () {
      expect(formatBytesShort(1024), '1.0 KB');
    });
    test('1536 → "1.5 KB"', () {
      expect(formatBytesShort(1536), '1.5 KB');
    });
    test('1024 * 1024 - 1 → "1024.0 KB" (边界, 还不到 MB)', () {
      // 1023.999... KB, 1 位小数 → "1024.0 KB" (而不是 MB). 这是约定.
      expect(formatBytesShort(1024 * 1024 - 1), '1024.0 KB');
    });
  });

  group('formatBytesShort — MB 档 (1MB - 1GB)', () {
    test('1024 * 1024 → "1.0 MB"', () {
      expect(formatBytesShort(1024 * 1024), '1.0 MB');
    });
    test('5.5 MB (典型 APK 大小)', () {
      expect(formatBytesShort((5.5 * 1024 * 1024).round()), '5.5 MB');
    });
  });

  group('formatBytesShort — GB 档 (>= 1GB)', () {
    test('1 GB → "1.00 GB" (2 位小数, GB 用 2 位精度)', () {
      expect(formatBytesShort(1024 * 1024 * 1024), '1.00 GB');
    });
    test('100 MB → "100.0 MB" (1 位小数, MB 不进 GB)', () {
      expect(formatBytesShort(100 * 1024 * 1024), '100.0 MB');
    });
  });
}
