// local_files.dart 测试.
//
// 主要覆盖 [getLocalDownloadPath] 的 path traversal 防御:
// 用户在 S3 key 里塞 "../" 之类的字符, 上层 _downloadSingle 走 obj.name
// (basename) 应该是干净的, 但万一上层传错 (e.g. 直接传 key), 我们兜底
// 防御一次, 避免写到 Downloads 之外.
//
// 用 MethodChannel mock 走 path_provider, 这样能跑在 flutter_test 里.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:s3browser/core/local_files.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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

void main() {
  // 用临时目录跑测试, 不污染真实目录
  late Directory tmpRoot;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpRoot = await Directory.systemTemp.createTemp('s3browser_local_files_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpRoot.path);
    // 主动建一下, 模拟正常情况下 getDownloadsDirectory 返回的目录存在
    await Directory(p.join(tmpRoot.path, 'fake_downloads')).create(recursive: true);
  });

  tearDown(() async {
    if (tmpRoot.existsSync()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  group('getLocalDownloadPath — 正常情况', () {
    test('普通文件名 → 在 fake_downloads 下', () async {
      final file = await getLocalDownloadPath('hello.apk');
      expect(p.basename(file.path), 'hello.apk');
      expect(p.dirname(file.path), p.join(tmpRoot.path, 'fake_downloads'));
    });

    test('中文文件名', () async {
      final file = await getLocalDownloadPath('测试文件.pdf');
      expect(p.basename(file.path), '测试文件.pdf');
    });
  });

  group('getLocalDownloadPath — path traversal 防御', () {
    test('"../etc/passwd" → basename 后只剩 "passwd", 仍在 Downloads 内', () async {
      // p.basename('../etc/passwd') = 'passwd' (Dart 行为).
      // 我们要保证: 不管输入多可疑, 最终路径都在 fake_downloads 之内.
      final file = await getLocalDownloadPath('../etc/passwd');
      expect(p.basename(file.path), 'passwd');
      expect(file.path.startsWith(p.join(tmpRoot.path, 'fake_downloads')), isTrue);
    });

    test('"/etc/passwd" → basename 后只剩 "passwd"', () async {
      final file = await getLocalDownloadPath('/etc/passwd');
      expect(p.basename(file.path), 'passwd');
      expect(file.path.startsWith(p.join(tmpRoot.path, 'fake_downloads')), isTrue);
    });

    test('空字符串 / "." / ".." → 抛 ArgumentError', () async {
      // 防 path traversal 收尾: 三个特殊名都拒绝.
      await expectLater(getLocalDownloadPath(''), throwsA(isA<ArgumentError>()));
      await expectLater(getLocalDownloadPath('.'), throwsA(isA<ArgumentError>()));
      await expectLater(getLocalDownloadPath('..'), throwsA(isA<ArgumentError>()));
    });
  });

  group('getLocalDownloadsDir', () {
    test('getDownloadsPath 返回非 null → 直接用', () async {
      final dir = await getLocalDownloadsDir();
      expect(dir.path, p.join(tmpRoot.path, 'fake_downloads'));
      expect(dir.existsSync(), isTrue);
    });
  });
}
