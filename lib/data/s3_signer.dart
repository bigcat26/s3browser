import 'package:intl/intl.dart';
import 'package:crypto/crypto.dart';

/// AWS SigV4 签名 (RFC: https://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html)
///
/// 用法:
/// ```dart
/// final signer = S3Signer(accessKey, secretKey, region, service: 's3');
/// final auth = signer.sign(
///   method: 'GET',
///   host: 's3.amazonaws.com',
///   path: '/my-bucket',
///   query: {},
///   headers: {},
///   payloadHash: 'UNSIGNED-PAYLOAD',
/// );
/// // Authorization: AWS4-HMAC-SHA256 Credential=..., SignedHeaders=host, Signature=...
/// ```
class S3Signer {
  final String accessKey;
  final String secretKey;
  final String region;
  final String service;
  final DateTime Function() now;

  S3Signer({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    this.service = 's3',
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  /// 生成 Authorization header
  String sign({
    required String method,
    required String host,
    required String path,
    required Map<String, String> query,
    required Map<String, String> headers,
    required String payloadHash,
  }) {
    final t = now().toUtc();
    final amzDate = _formatAmzDate(t);          // 20260113T123456Z
    final dateStamp = _formatDateStamp(t);      // 20260113

    // 1. Canonical Request
    final sortedQuery = _sortByKey(query);
    final canonicalUri = _canonicalUri(path);
    final canonicalQuery = sortedQuery.entries
        .map((e) =>
            '${_uriEncode(e.key, isKey: true)}=${_uriEncode(e.value, isKey: true)}')
        .join('&');
    final sortedHeaders = _sortByKey({
      ...headers,
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
    });
    final canonicalHeaders = sortedHeaders.entries
        .map((e) => '${e.key.toLowerCase()}:${e.value.trim()}\n')
        .join();
    final signedHeaders = sortedHeaders.keys.map((k) => k.toLowerCase()).join(';');
    final canonicalRequest = [
      method,
      canonicalUri,
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    // 2. String to Sign
    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      _sha256Hex(canonicalRequest),
    ].join('\n');

    // 3. Signing Key
    final kDate = _hmac('AWS4$secretKey', dateStamp);
    final kRegion = _hmacBytes(kDate, region);
    final kService = _hmacBytes(kRegion, service);
    final kSigning = _hmacBytes(kService, 'aws4_request');

    // 4. Signature
    final signature = _hmacHex(kSigning, stringToSign);

    // 5. Authorization
    return 'AWS4-HMAC-SHA256 '
        'Credential=$accessKey/$credentialScope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';
  }

  String _formatAmzDate(DateTime t) =>
      DateFormat("yyyyMMdd'T'HHmmss'Z'").format(t);

  String _formatDateStamp(DateTime t) => DateFormat('yyyyMMdd').format(t);

  /// URI path 规范化: 保留 '/', 其余 percent-encode
  String _canonicalUri(String path) {
    if (path.isEmpty) return '/';
    final parts = path.split('/');
    return parts.map((p) {
      return _uriEncode(p, isKey: false);
    }).join('/');
  }

  String _uriEncode(String s, {required bool isKey}) {
    return Uri.encodeComponent(s)
        .replaceAll('+', '%20')
        .replaceAll('*', '%2A')
        .replaceAll('%7E', '~');
  }

  Map<String, String> _sortByKey(Map<String, String> m) {
    final keys = m.keys.toList()..sort();
    return {for (final k in keys) k: m[k]!};
  }

  String _sha256Hex(String s) {
    final digest = sha256.convert(_toUtf8(s));
    return digest.toString();
  }

  List<int> _hmac(String key, String data) => _hmacBytes(_toUtf8(key), data);
  List<int> _hmacBytes(List<int> key, String data) =>
      Hmac(sha256, key).convert(_toUtf8(data)).bytes;
  String _hmacHex(List<int> key, String data) =>
      Hmac(sha256, key).convert(_toUtf8(data)).toString();
}

List<int> _toUtf8(String s) => s.codeUnits;
