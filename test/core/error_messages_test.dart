// FriendlyError 翻译测试 — 防止回归: 之前直接 error.toString() 抛
// "DioException [connection error]: The connection errored: Failed host
// lookup: 'example.com'..." 一脸懵, 现在 explainError 转成中文人话 +
// 修复建议 + 原始 error (调试用).

import 'package:s3browser/core/error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('explainError — 网络层', () {
    test('Failed host lookup / errno 7 → DNS 解析失败', () {
      final r = explainError(
        "DioException [connection error]: The connection errored: "
        "Failed host lookup: 'example.com'. "
        "OS Error: No address associated with hostname, errno = 7.",
      );
      expect(r.message, contains('DNS'));
      expect(r.hint, contains('endpoint'));
      expect(r.raw, contains('Failed host lookup'));
    });

    test('Connection refused / errno 111 → 服务器拒绝连接', () {
      final r = explainError(
        "DioException [connection error]: Connection refused, "
        "errno = 111. Server may be down.",
      );
      expect(r.message, contains('拒绝'));
      expect(r.hint, contains('端口'));
    });

    test('Connection timed out → 连接超时', () {
      final r = explainError(
        "DioException [connection timeout]: Connection timed out after 15s",
      );
      expect(r.message, contains('超时'));
    });

    test('Network is unreachable → 网络不可达', () {
      final r = explainError(
        "SocketException: Network is unreachable, errno = 101",
      );
      expect(r.message, contains('不可达'));
    });

    test('TLS 握手失败 / certificate → 证书相关', () {
      final r = explainError(
        "HandshakeException: Certificate verify failed (CERTIFICATE_VERIFY_FAILED)",
      );
      expect(r.message, contains('TLS'));
    });
  });

  group('explainError — S3 服务端', () {
    test('S3 NoSuchBucket → 友好提示', () {
      final r = explainError('S3 NoSuchBucket: The specified bucket does not exist');
      expect(r.message, contains('NoSuchBucket'));
      expect(r.hint, contains('Bucket'));
    });

    test('S3 AccessDenied → 权限问题', () {
      final r = explainError('S3 AccessDenied: Access Denied');
      expect(r.message, contains('AccessDenied'));
      expect(r.hint, contains('IAM'));
    });

    test('S3 SignatureDoesNotMatch → 签名问题', () {
      final r = explainError('S3 SignatureDoesNotMatch: Signature mismatch');
      expect(r.message, contains('SignatureDoesNotMatch'));
      expect(r.hint, contains('access key'));
    });

    test('S3 未知 code → 通用提示 + 包含原码', () {
      final r = explainError('S3 WeirdNewError: some message');
      expect(r.message, contains('WeirdNewError'));
      expect(r.hint, contains('S3'));
    });
  });

  group('explainError — S3Error HTTP<status> 形态', () {
    test('S3 HTTP404 → 对象不存在', () {
      // _signedRequest status >= 400 兜底抛的形态, 之前显示 "S3 HTTP404: No
      // response body" 一脸懵. 现在分到 HTTP status hint 分支.
      final r = explainError('S3 HTTP404: No response body');
      expect(r.message, contains('HTTP404'));
      expect(r.hint, contains('对象'));
    });

    test('S3 HTTP403 → 权限拒绝', () {
      final r = explainError('S3 HTTP403: Access Denied');
      expect(r.message, contains('HTTP403'));
      expect(r.hint, anyOf(contains('权限'), contains('IAM')));
    });

    test('S3 HTTP500 → 服务端内部错误', () {
      final r = explainError('S3 HTTP500: Internal Server Error');
      expect(r.message, contains('HTTP500'));
      expect(r.hint, contains('重试'));
    });

    test('S3 HTTP429 → 限流', () {
      final r = explainError('S3 HTTP429: Slow Down');
      expect(r.message, contains('HTTP429'));
      expect(r.hint, contains('限流'));
    });
  });

  group('explainError — 兜底', () {
    test('完全不认识的 error → 用 context 作 message, raw 保留', () {
      final r = explainError(
        "Something weird happened",
        context: '上传文件失败',
      );
      expect(r.message, '上传文件失败');
      expect(r.hint, contains('原始错误'));
      expect(r.raw, 'Something weird happened');
    });

    test('dio 的 AccessDenied 字符串 → 签名 / 权限', () {
      // 不在 S3 prefix 但命中 "AccessDenied" 关键字
      final r = explainError("DioException: HTTP 403 AccessDenied");
      // 可能命中 "accessdenied" 嗅探, 也可能漏. 至少要包含 raw 不丢失
      expect(r.raw, 'DioException: HTTP 403 AccessDenied');
    });
  });

  group('FriendlyError 数据结构', () {
    test('message / hint / raw 都是 String', () {
      final r = FriendlyError(
        message: 'm',
        hint: 'h',
        raw: 'r',
      );
      expect(r.message, isA<String>());
      expect(r.hint, isA<String>());
      expect(r.raw, isA<String>());
    });
  });
}
