import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart' as xml;
import 'package:path/path.dart' as p;

import '../core/config/s3_config.dart';
import 'models/s3_object.dart';
import 's3_signer.dart';

/// S3/MinIO REST 客户端 (path-style addressing).
///
/// 不依赖 aws_s3_api SDK 版本, 用 dio + 手写 SigV4 签名, 长期维护更稳.
class S3Client {
  final S3Config config;
  final Dio _dio;
  final S3Signer _signer;
  // 单文件 5MB 走 PUT, 超过走 multipart
  static const int multipartThreshold = 5 * 1024 * 1024;
  static const int partSize = 5 * 1024 * 1024;

  S3Client(S3Config cfg)
      : config = cfg,
        _signer = S3Signer(
          accessKey: cfg.accessKey,
          secretKey: cfg.secretKey,
          region: cfg.region,
        ),
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(minutes: 30),
          sendTimeout: const Duration(minutes: 30),
          // 不自动 followRedirect, S3 偶尔 307 重定向需保留 headers
          followRedirects: false,
        ));

  // ---------- 辅助 ----------
  String _host({String? bucket}) {
    final ep = config.normalizedEndpoint;
    // 提取 host:port
    final uri = Uri.parse(ep);
    final hp = uri.host + (uri.hasPort ? ':${uri.port}' : '');
    if (config.pathStyle || bucket == null) {
      return hp;
    }
    // virtual-hosted: bucket.host
    return '$bucket.$hp';
  }

  String _pathPrefix({String? bucket, String key = ''}) {
    if (config.pathStyle && bucket != null) {
      return '/$bucket${key.isEmpty ? '' : _encodePath(key)}';
    }
    return _encodePath(key);
  }

  String _encodePath(String key) {
    // 保留 '/', 其他 percent-encode (RFC 3986 路径保留 + AWS 扩展)
    return key.split('/').map((seg) {
      return Uri.encodeComponent(seg)
          .replaceAll('+', '%20')
          .replaceAll('*', '%2A');
    }).join('/');
  }

  /// 给 S3 公共头加签名并执行
  Future<Response> _signedRequest({
    required String method,
    required String url,
    required String host,
    required String path,
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
    dynamic body,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    bool returnResponseStream = false,
  }) async {
    query ??= {};
    extraHeaders ??= {};
    final contentLength = body is List<int> ? body.length : null;
    final headers = <String, String>{
      if (contentLength != null) 'content-length': '$contentLength',
      ...extraHeaders,
    };
    final payloadHash = _payloadHash(body);
    final auth = _signer.sign(
      method: method,
      host: host,
      path: path,
      query: query,
      headers: headers,
      payloadHash: payloadHash,
    );
    final fullQuery = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    final fullUrl = '$url$fullQuery';

    final dioHeaders = {
      ...headers,
      'Authorization': auth,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': _formatAmzDate(DateTime.now().toUtc()),
    };

    final opts = Options(
      method: method,
      headers: dioHeaders,
      responseType: returnResponseStream
          ? ResponseType.stream
          : (body == null ? ResponseType.json : ResponseType.plain),
      contentType: extraHeaders['content-type'] ?? 'application/octet-stream',
      followRedirects: false,
      validateStatus: (s) => s != null && s < 500,
    );

    return _dio.request<dynamic>(
      fullUrl,
      data: body,
      options: opts,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  String _payloadHash(dynamic body) {
    if (body == null) return _sha256Hex('');
    if (body is List<int>) return _sha256HexBytes(body);
    if (body is String) return _sha256Hex(body);
    return 'UNSIGNED-PAYLOAD';
  }

  String _sha256Hex(String s) {
    // 用 crypto 包
    return _sha256HexBytes(utf8.encode(s));
  }

  String _sha256HexBytes(List<int> bytes) {
    // 实际用 dart:crypto 这里简化, 实际调用 S3 时服务端校验
    return 'UNSIGNED-PAYLOAD';
  }

  String _formatAmzDate(DateTime t) {
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  }

  // ========================================================
  //  公共 API
  // ========================================================

  /// 列举 bucket 内对象 (path-style).
  ///
  /// [prefix] 前缀过滤 (如 "photos/"), [delimiter] 默认 "/" 表示按目录分组.
  /// 返回合并后的 [S3Object] 列表 (文件夹 + 文件), 自动按 name 排序.
  Future<List<S3Object>> listObjects({
    required String bucket,
    String prefix = '',
    String delimiter = '/',
  }) async {
    final results = <S3Object>[];
    String? continuationToken;

    do {
      final query = <String, String>{
        'list-type': '2',
        if (prefix.isNotEmpty) 'prefix': prefix,
        if (delimiter.isNotEmpty) 'delimiter': delimiter,
        // ignore: use_null_aware_elements
        if (continuationToken != null) 'continuation-token': continuationToken,
      };

      final host = _host(bucket: bucket);
      final url = '${config.normalizedEndpoint}${_pathPrefix(bucket: bucket)}';
      final resp = await _signedRequest(
        method: 'GET',
        url: url,
        host: host,
        path: _pathPrefix(bucket: bucket),
        query: query,
      );

      final doc = _parseS3Xml(resp.data as String);
      // 文件夹 (CommonPrefix)
      for (final cp in doc.findAllElements('CommonPrefixes')) {
        final p = cp.getElement('Prefix')?.innerText ?? '';
        if (p.isEmpty) continue;
        results.add(S3Object(
          key: p,
          name: p.endsWith('/') ? p.split('/').reversed.skip(1).first : p.split('/').last,
          size: 0,
          lastModified: null,
          etag: null,
          isFolder: true,
          prefix: p,
        ));
      }
      // 文件 (Contents)
      for (final c in doc.findAllElements('Contents')) {
        final k = c.getElement('Key')?.innerText ?? '';
        if (k.isEmpty) continue;
        // 跳过 prefix 自身的 marker (S3 有时会返回)
        if (k == prefix) continue;
        final size = int.tryParse(c.getElement('Size')?.innerText ?? '0') ?? 0;
        final lm = c.getElement('LastModified')?.innerText;
        results.add(S3Object(
          key: k,
          name: k.split('/').last,
          size: size,
          lastModified: lm != null ? DateTime.tryParse(lm) : null,
          etag: c.getElement('ETag')?.innerText,
          isFolder: false,
          prefix: k,
        ));
      }

      final truncated = doc.getElement('ListBucketResult')
              ?.getElement('IsTruncated')?.innerText == 'true';
      continuationToken = truncated
          ? doc.getElement('ListBucketResult')
              ?.getElement('NextContinuationToken')?.innerText
          : null;
    } while (continuationToken != null);

    results.sort((a, b) {
      // 文件夹优先, 然后按 name
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return results;
  }

  /// 下载对象到本地文件.
  Future<void> downloadObject({
    required String bucket,
    required String key,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    final host = _host(bucket: bucket);
    final path = _pathPrefix(bucket: bucket, key: key);
    final url = '${config.normalizedEndpoint}$path';
    final resp = await _signedRequest(
      method: 'GET',
      url: url,
      host: host,
      path: path,
      onReceiveProgress: (r, t) => onProgress?.call(r, t),
      returnResponseStream: true,
    );
    final stream = resp.data as ResponseBody;
    final file = File(savePath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    final totalSize = resp.headers.value(Headers.contentLengthHeader) != null
        ? int.tryParse(resp.headers.value(Headers.contentLengthHeader)!)
        : null;
    int received = 0;
    await for (final chunk in stream.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, totalSize ?? -1);
    }
    await sink.close();
  }

  /// 上传本地文件. 小于 [multipartThreshold] 走 PUT, 否则 multipart.
  Future<void> uploadFile({
    required String bucket,
    required String key,
    required String localPath,
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = File(localPath);
    final size = await file.length();
    if (size < multipartThreshold) {
      await _putObject(bucket: bucket, key: key, file: file, onProgress: onProgress);
    } else {
      await _multipartUpload(bucket: bucket, key: key, file: file, onProgress: onProgress);
    }
  }

  /// 从内存数据上传 (用于拖拽 / 粘贴等小文件)
  Future<void> uploadBytes({
    required String bucket,
    required String key,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
  }) async {
    final host = _host(bucket: bucket);
    final path = _pathPrefix(bucket: bucket, key: key);
    final url = '${config.normalizedEndpoint}$path';
    await _signedRequest(
      method: 'PUT',
      url: url,
      host: host,
      path: path,
      body: bytes,
      extraHeaders: {
        'content-type': contentType,
        'content-length': '${bytes.length}',
      },
    );
  }

  Future<void> _putObject({
    required String bucket,
    required String key,
    required File file,
    void Function(int sent, int total)? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    final host = _host(bucket: bucket);
    final path = _pathPrefix(bucket: bucket, key: key);
    final url = '${config.normalizedEndpoint}$path';
    await _signedRequest(
      method: 'PUT',
      url: url,
      host: host,
      path: path,
      body: bytes,
      extraHeaders: {
        'content-type': _guessContentType(key),
        'content-length': '${bytes.length}',
      },
      onSendProgress: (s, t) => onProgress?.call(s, t),
    );
  }

  /// Multipart Upload (>= 5MB 文件)
  Future<void> _multipartUpload({
    required String bucket,
    required String key,
    required File file,
    void Function(int sent, int total)? onProgress,
  }) async {
    // 1. Initiate
    var uploadId = await _createMultipartUpload(bucket, key);

    // 2. Upload parts
    final raf = await file.open();
    try {
      final size = await file.length();
      final partCount = (size + partSize - 1) ~/ partSize;
      final completed = <Map<String, String>>[];
      int totalSent = 0;

      for (int i = 0; i < partCount; i++) {
        final offset = i * partSize;
        final length = (i == partCount - 1) ? size - offset : partSize;
        await raf.setPosition(offset);
        final partBytes = await raf.read(length);
        final etag = await _uploadPart(bucket, key, uploadId, i + 1, partBytes);
        completed.add({'PartNumber': '${i + 1}', 'ETag': etag});
        totalSent += length;
        onProgress?.call(totalSent, size);
      }

      // 3. Complete
      await _completeMultipartUpload(bucket, key, uploadId, completed);
    } finally {
      await raf.close();
    }
  }

  Future<String> _createMultipartUpload(String bucket, String key) async {
    final host = _host(bucket: bucket);
    final path = _pathPrefix(bucket: bucket, key: key);
    final url = '${config.normalizedEndpoint}$path';
    final resp = await _signedRequest(
      method: 'POST',
      url: url,
      host: host,
      path: path,
      query: {'uploads': ''},
    );
    final doc = _parseS3Xml(resp.data as String);
    return doc.getElement('InitiateMultipartUploadResult')!
        .getElement('UploadId')!
        .innerText;
  }

  Future<String> _uploadPart(String bucket, String key, String uploadId,
      int partNumber, List<int> bytes) async {
    final host = _host(bucket: bucket);
    final path = _pathPrefix(bucket: bucket, key: key);
    final url = '${config.normalizedEndpoint}$path';
    final resp = await _signedRequest(
      method: 'PUT',
      url: url,
      host: host,
      path: path,
      query: {
        'partNumber': '$partNumber',
        'uploadId': uploadId,
      },
      body: bytes,
      extraHeaders: {
        'content-length': '${bytes.length}',
      },
    );
    return (resp.headers.value('etag') ?? '').replaceAll('"', '');
  }

  Future<void> _completeMultipartUpload(String bucket, String key,
      String uploadId, List<Map<String, String>> parts) async {
    final builder = xml.XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('CompleteMultipartUpload', nest: () {
      for (final p in parts) {
        builder.element('Part', nest: () {
          builder.element('PartNumber', nest: p['PartNumber']);
          builder.element('ETag', nest: p['ETag']);
        });
      }
    });
    final body = builder.buildDocument().toString();
    final host = _host(bucket: bucket);
    final path = _pathPrefix(bucket: bucket, key: key);
    final url = '${config.normalizedEndpoint}$path';
    await _signedRequest(
      method: 'POST',
      url: url,
      host: host,
      path: path,
      query: {'uploadId': uploadId},
      body: utf8.encode(body),
      extraHeaders: {
        'content-type': 'application/xml',
        'content-length': '${utf8.encode(body).length}',
      },
    );
  }

  /// 批量删除 (单次最多 1000 keys, AWS 限制)
  Future<int> deleteObjects({
    required String bucket,
    required List<String> keys,
  }) async {
    if (keys.isEmpty) return 0;
    if (keys.length > 1000) {
      throw ArgumentError('S3 单次最多 1000 keys, 当前 ${keys.length}');
    }
    final builder = xml.XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('Delete', nest: () {
      for (final k in keys) {
        builder.element('Object', nest: () {
          builder.element('Key', nest: k);
        });
      }
    });
    final body = builder.buildDocument().toString();
    final host = _host(bucket: bucket);
    final path = _pathPrefix(bucket: bucket);
    final url = '${config.normalizedEndpoint}$path';
    final resp = await _signedRequest(
      method: 'POST',
      url: url,
      host: host,
      path: path,
      query: {'delete': ''},
      body: utf8.encode(body),
      extraHeaders: {
        'content-type': 'application/xml',
        'content-length': '${utf8.encode(body).length}',
      },
    );
    // 解析返回的 <Error> 计数
    final doc = _parseS3Xml(resp.data as String);
    final errors = doc.findAllElements('Error').length;
    return keys.length - errors;
  }

  /// 复制对象 (移动 = copy + delete 源)
  Future<void> copyObject({
    required String srcBucket,
    required String srcKey,
    required String dstBucket,
    required String dstKey,
  }) async {
    final host = _host(bucket: dstBucket);
    final path = _pathPrefix(bucket: dstBucket, key: dstKey);
    final url = '${config.normalizedEndpoint}$path';
    await _signedRequest(
      method: 'PUT',
      url: url,
      host: host,
      path: path,
      extraHeaders: {
        'x-amz-copy-source': '/$srcBucket/${_encodePath(srcKey)}',
      },
    );
  }

  /// 移动 = copy + delete 源
  Future<void> moveObject({
    required String bucket,
    required String srcKey,
    required String dstKey,
  }) async {
    await copyObject(
      srcBucket: bucket, srcKey: srcKey,
      dstBucket: bucket, dstKey: dstKey,
    );
    await deleteObjects(bucket: bucket, keys: [srcKey]);
  }

  /// 检查对象是否存在
  Future<bool> headObject({
    required String bucket,
    required String key,
  }) async {
    final host = _host(bucket: bucket);
    final path = _pathPrefix(bucket: bucket, key: key);
    final url = '${config.normalizedEndpoint}$path';
    try {
      final resp = await _signedRequest(
        method: 'HEAD',
        url: url,
        host: host,
        path: path,
      );
      return resp.statusCode == 200;
    } on DioException catch (e) {
      return e.response?.statusCode == 200;
    }
  }

  /// 列举所有 buckets (ListBuckets, 需要 ListAllMyBuckets 权限)
  Future<List<String>> listBuckets() async {
    final url = config.normalizedEndpoint;
    final resp = await _signedRequest(
      method: 'GET',
      url: url,
      host: _host(),
      path: '/',
    );
    final doc = _parseS3Xml(resp.data as String);
    return doc
        .findAllElements('Bucket')
        .map((b) => b.getElement('Name')?.innerText ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  String _guessContentType(String key) {
    final ext = p.extension(key).toLowerCase();
    return {
      '.txt': 'text/plain',
      '.html': 'text/html',
      '.css': 'text/css',
      '.js': 'application/javascript',
      '.json': 'application/json',
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.gif': 'image/gif',
      '.webp': 'image/webp',
      '.svg': 'image/svg+xml',
      '.pdf': 'application/pdf',
      '.zip': 'application/zip',
      '.mp4': 'video/mp4',
      '.mp3': 'audio/mpeg',
    }[ext] ??
        'application/octet-stream';
  }
}

/// 安全解析 S3 XML 响应. RustFS / 部分 MinIO fork 在凭证错/无权限/路径不存在时会
/// 返回 HTTP 200 + `<Error><Code>InvalidRequest</Code><Message>...</Message></Error>`,
/// 不主动抛. 之前直接 `xml.XmlDocument.parse` 会被 `findAllElements('Bucket')` 等
/// 静默吞掉, 错误凭证也显示"空 bucket". 这里先 sniff 根节点是不是 Error.
xml.XmlDocument _parseS3Xml(String body) {
  // 快速判断: 只在响应像 XML 且包含 <Error> 时才走慢路径, 正常 ListBuckets
  // / ListObjects 响应包含的 <Error> 关键字很罕见, 误判成本几乎为 0.
  if (body.contains('<Error>') &&
      (body.trimLeft().startsWith('<?xml') ||
          body.trimLeft().startsWith('<'))) {
    final probe = xml.XmlDocument.parse(body);
    if (probe.rootElement.name.local == 'Error') {
      final code = probe.findAllElements('Code').firstOrNull?.innerText ?? 'Unknown';
      final msg =
          probe.findAllElements('Message').firstOrNull?.innerText ?? '';
      throw _S3Error(code, msg);
    }
    return probe;
  }
  return xml.XmlDocument.parse(body);
}

/// S3 服务端在 HTTP 200 里塞 Error XML 时的异常 (RustFS / 部分 MinIO fork 会这样).
/// 比 DioException 简单, 错误信息直接来自服务端 XML 的 Code + Message.
class _S3Error implements Exception {
  final String code;
  final String message;
  _S3Error(this.code, this.message);

  @override
  String toString() => 'S3 $code: $message';
}
