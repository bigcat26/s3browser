// isMacOSArtifact 测试.
//
// 背景: macOS / iOS Finder 上传文件到 S3 时会留一堆元数据:
//   - @eaDir/<name>/  资源分叉目录
//   - ._<name>        AppleDouble 单文件元数据
//   - .DS_Store       桌面服务存储
//   - .Spotlight-V100/ .Trashes/ .fseventsd/  macOS 系统目录
//   - .TemporaryItems/ .DocumentRevisions-V100/  Time Machine 临时
//   - Thumbs.db       Windows 缩略图
//
// 这些 S3 key 正常存在, 但 S3 浏览器不该展示给用户 (跟 Cyberduck / Transmit
// 行为一致). 之前没过滤, 用户的 packages bucket 里有 @eaDir/, 右键 → 删除
// → deletePrefix 走 list 返回 0 keys → "已删除 0 个对象" 一脸懵.
//
// 修了之后 listObjects 调 isMacOSArtifact 过滤, 这里测它覆盖正确.

import 'package:s3browser/data/s3_client.dart' show isMacOSArtifact;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isMacOSArtifact — macOS Finder 资源分叉', () {
    test('@eaDir/ 顶层目录', () {
      expect(isMacOSArtifact('@eaDir/'), isTrue);
    });
    test('@eaDir/ 子目录', () {
      expect(isMacOSArtifact('@eaDir/IMG_001.jpg/'), isTrue);
    });
    test('@eaDir/ 任意深度', () {
      expect(isMacOSArtifact('photos/2024/@eaDir/IMG_001.jpg/'), isTrue);
    });
  });

  group('isMacOSArtifact — AppleDouble 文件 (._xxx)', () {
    test('顶层 ._xxx', () {
      expect(isMacOSArtifact('._IMG_001.jpg'), isTrue);
    });
    test('深层 ._xxx (嵌套路径里)', () {
      expect(isMacOSArtifact('photos/2024/._IMG_001.jpg'), isTrue);
    });
  });

  group('isMacOSArtifact — 桌面服务存储', () {
    test('顶层 .DS_Store', () {
      expect(isMacOSArtifact('.DS_Store'), isTrue);
    });
    test('深层 .DS_Store', () {
      expect(isMacOSArtifact('photos/2024/.DS_Store'), isTrue);
    });
  });

  group('isMacOSArtifact — macOS 系统目录', () {
    test('.Spotlight-V100/ 顶层', () {
      expect(isMacOSArtifact('.Spotlight-V100/'), isTrue);
    });
    test('.Trashes/ 顶层', () {
      expect(isMacOSArtifact('.Trashes/'), isTrue);
    });
    test('.fseventsd/ 顶层', () {
      expect(isMacOSArtifact('.fseventsd/'), isTrue);
    });
    test('.TemporaryItems/ 顶层', () {
      expect(isMacOSArtifact('.TemporaryItems/'), isTrue);
    });
    test('.DocumentRevisions-V100/ 顶层', () {
      expect(isMacOSArtifact('.DocumentRevisions-V100/'), isTrue);
    });
  });

  group('isMacOSArtifact — Windows 缩略图', () {
    test('Thumbs.db 顶层', () {
      expect(isMacOSArtifact('Thumbs.db'), isTrue);
    });
    test('Thumbs.db 深层', () {
      expect(isMacOSArtifact('photos/2024/Thumbs.db'), isTrue);
    });
  });

  group('isMacOSArtifact — 正常文件不过滤', () {
    test('普通文件 (e.g. README.pdf)', () {
      expect(isMacOSArtifact('README.pdf'), isFalse);
    });
    test('普通目录 (e.g. photos/)', () {
      expect(isMacOSArtifact('photos/'), isFalse);
    });
    test('名字含 "eaDir" 但不是 @eaDir/ 前缀的 (e.g. my_eaDir_folder/)', () {
      // 不能误伤. 之前 naive 的 startsWith('@eaDir') 写法, 用户文件夹如果
      // 叫 my_eaDir 也会被吃掉. 我们用 == + startsWith('@eaDir/') 双判定.
      expect(isMacOSArtifact('my_eaDir/file.txt'), isFalse);
      expect(isMacOSArtifact('not_@eaDir/'), isFalse);
    });
    test('空字符串 (defensive, 实际不会有)', () {
      expect(isMacOSArtifact(''), isFalse);
    });
    test('大小写敏感: .ds_store (小写) 不匹配 .DS_Store', () {
      // S3 key 区分大小写, 我们按 byte-level 比. macOS HFS+/APFS 默认不
      // 区分, 但上传到 S3 之后 case 是按 Finder 实际写的来, 我们不"帮忙"
      // 修正, 用户自己处理.
      expect(isMacOSArtifact('.ds_store'), isFalse);
    });
    test('名字像 @eaDir 但不带 / 结尾 (e.g. "@eaDir" 没尾 /)', () {
      // 必须是目录 (以 / 结尾的前缀), 单个叫 "@eaDir" 的文件 (理论上不存在)
      // 不算 system dir. 但 ._xxx 类不需要 /, 所以这个 case 还是走 false.
      expect(isMacOSArtifact('@eaDir'), isFalse);
    });
  });
}
