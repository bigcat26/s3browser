// S3 Content-MD5 头测试.
//
// 背景: AWS S3 [POST ?delete] (多对象删除) 强制要求 Content-MD5 头,
// 服务端用 MD5 校验 body 在传输中没被改. 漏了就 400 "Missing ContentMD5".
// RustFS / 严格实现的 MinIO 也拒.
//
// 之前 deleteObjects 没设这个头, 所有用户的批量删除都 400 失败.
//
// 修法: 在 deleteObjects / _completeMultipartUpload 算 body MD5,
// base64 编码, 放到 content-md5 头.

import 'dart:convert';
import 'package:s3browser/data/s3_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

void main() {
  group('contentMd5Base64', () {
    test('空 body → MD5 已知值 "1B2M2Y8AsgTpgAmY7PhCfg==" (空串 MD5)', () {
      // RFC 1321 附录 A.5: 空字符串的 MD5 = d41d8cd98f00b204e9800998ecf8427e
      // base64 = "1B2M2Y8AsgTpgAmY7PhCfg=="
      expect(contentMd5Base64([]), '1B2M2Y8AsgTpgAmY7PhCfg==');
    });

    test('"hello" → MD5 已知值 + base64 (跟 md5.convert 对照)', () {
      // 不要硬编码 base64 字符串 (容易手算错), 跟权威 crypto.md5.convert
      // 对照即可. 上面的 "空字符串" 那个用 RFC 1321 硬编码是因为太有名了不会错.
      final expected = base64.encode(
          md5.convert(utf8.encode('hello')).bytes);
      expect(contentMd5Base64(utf8.encode('hello')), expected);
    });

    test('跟 crypto.md5.convert 直接算的一致 (sanity check)', () {
      final input = utf8.encode('test delete body');
      final expected = base64.encode(md5.convert(input).bytes);
      expect(contentMd5Base64(input), expected);
    });

    test('Unicode 字符串 → 跟直接 md5.convert 一致', () {
      // 确保我们用 utf8.encode 而不是 latin1 (emoji 之类的字节序列)
      final input = utf8.encode('测试删除 🔥');
      final expected = base64.encode(md5.convert(input).bytes);
      expect(contentMd5Base64(input), expected);
    });

    test('大 body (5MB) → MD5 digest 固定 16 字节 / base64 24 字符, 不爆栈', () {
      // 模拟大请求, 验证不爆栈 / 不阻塞 / 不截断.
      // MD5 输出永远是 16 字节 digest, base64 = 24 字符 (含 padding).
      final big = List<int>.filled(5 * 1024 * 1024, 0x61); // 'a' * 5MB
      final result = contentMd5Base64(big);
      expect(result.length, 24); // 16 字节 → 24 字符 base64
      // 验证是合法 base64
      final decoded = base64.decode(result);
      expect(decoded.length, 16);
    });
  });
}
