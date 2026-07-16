import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
      if (key.isEmpty) return '/$bucket';
      // bucket 和 key 之间必须有 '/', 之前漏了导致 URL 拼成
      // '/packagescomposeApp-debug.apk' (少了 '/'), server 端 400/404.
      return '/$bucket/${_encodePath(key)}';
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
    CancelToken? cancelToken,
  }) async {
    query ??= {};
    extraHeaders ??= {};
    // content-length 的取舍: 服务端是否把它算进签名, 取决于"该请求是否该有
    // body". 实测 s3.internal.example.com:
    //   - PUT/POST/DELETE 服务端会签 content-length (PUT 即使无 body 也按 0 算),
    //     不带 → 签名对不上 (原 CopyObject 重命名就栽在这).
    //   - GET/HEAD 服务端不对"无 body 请求"签 content-length, 强行带 0 反而让
    //     签名头集合跟服务端不一致 → 登录/列举直接签名不匹配.
    // 所以: 有 body 或 PUT/POST/DELETE → 带 content-length (无 body 用 0) 并签名;
    // GET/HEAD → 不带, 恢复改动前行为.
    final methodUpper = method.toUpperCase();
    final signsContentLength = body is List<int> ||
        methodUpper == 'PUT' ||
        methodUpper == 'POST' ||
        methodUpper == 'DELETE';
    final contentLength = body is List<int> ? body.length : 0;
    // 单一时间戳: 签名与发出的 x-amz-date 共用, 避免两次 now() 跨秒不一致.
    final amzNow = DateTime.now().toUtc();
    final headers = <String, String>{
      if (signsContentLength) 'content-length': '$contentLength',
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
      nowOverride: amzNow,
    );
    final fullQuery = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    final fullUrl = '$url$fullQuery';

    final dioHeaders = {
      ...headers,
      'Authorization': auth,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': _formatAmzDate(amzNow),
    };

    final opts = Options(
      method: method,
      headers: dioHeaders,
      responseType: returnResponseStream
          ? ResponseType.stream
          : (body == null ? ResponseType.json : ResponseType.plain),
      contentType: extraHeaders['content-type'] ?? 'application/octet-stream',
      followRedirects: false,
      // 不让 dio 默认在 4xx 抛, 让我们自己嗅探 body + 检 status 后抛带语义的错误.
      // 之前默认 `s < 500` 加上 PUT/POST 类调用完全不看 body,
      // 导致 RustFS "200 + <Error>...</Error>" 的失败被静默吞掉,
      // 上传提示成功但服务端实际没建出来.
      validateStatus: (s) => s != null && s < 500,
    );

    // dio 5.10 把 cancelToken 从 Options 挪到 request() 顶层参数, 5.4
    // 之前的版本 Options 还能接. 我们锁到 5.10+, 必须用新 API.
    final resp = await _dio.request<dynamic>(
      fullUrl,
      data: body,
      options: opts,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );

    // 嗅探 RustFS / 部分 MinIO fork 行为: HTTP 200 但 body 是 <Error>...
    // 写操作 (PUT/POST/DELETE) 之前不调 parseS3Xml, 这条 sniff 之前也没接进来,
    // 静默吞掉, 调上传的人看到 void 返回就当成功了.
    if (resp.data is String) {
      checkS3ErrorBody(resp.data as String);
    }

    // 兜底: 4xx / 5xx 但 body 不是 Error XML (空 body / HTML 错误页 /
    // S3 返回纯文本 "Access Denied" 等), 也不应该当成成功. validateStatus 已
    // 让 dio 不抛 4xx, 5xx 会抛 DioException, 我们这里补 4xx 这条.
    final code = resp.statusCode ?? 0;
    if (code >= 400) {
      // 读 body: 字符串直接拿, stream 需要 drain 出来才能看服务端说啥.
      // 之前漏了 stream 路径, 下载类请求 (returnResponseStream: true) 4xx
      // 永远 "No response body", 看不到服务端具体说啥. 现在补上.
      String bodyStr = '';
      if (resp.data is String) {
        bodyStr = resp.data as String;
      } else if (resp.data != null) {
        // 兜底: 用 toString 拿 (ResponseBody.toString 不会暴露 body bytes,
        // 实际还是得 drain). 用 cast + drain stream.
        try {
          // ignore: avoid_dynamic_calls
          final stream = (resp.data as dynamic).stream as dynamic;
          // bytesToString 是 Stream<List<int>> 的扩展, 限制读 4KB
          // (4xx body 几乎都 < 4KB, 真下载响应 body 大但不进这条分支)
          final bytes = await stream.take(4096).fold<List<int>>(
            [],
            (acc, chunk) => acc..addAll(chunk),
          );
          bodyStr = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {
          bodyStr = '';
        }
      }
      throw S3Error(
        'HTTP$code',
        bodyStr.isEmpty ? 'No response body' : _truncateBody(bodyStr, 200),
        url: fullUrl,
      );
    }

    return resp;
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
    // 真实 SHA256 (crypto 包). 之前这里误返回 'UNSIGNED-PAYLOAD' 常量:
    // 因为调用方把同一个值同时写进 x-amz-content-sha256 头和签名, 二者
    // 一致所以签名能过, 但真实 payload 哈希从没被计算. S3 支持
    // UNSIGNED-PAYLOAD 所以之前"凑巧"能用, 但遇到要求真实校验和的服务端
    // (Object Lock / 部分严格 MinIO-R2) 会失败. 算真实哈希是 SigV4 标准做法,
    // 兼容性更好.
    return sha256.convert(bytes).toString();
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

      final doc = parseS3Xml(resp.data as String);
      // 文件夹 (CommonPrefix)
      for (final cp in doc.findAllElements('CommonPrefixes')) {
        final p = cp.getElement('Prefix')?.innerText ?? '';
        if (p.isEmpty) continue;
        // 隐藏 macOS / iOS Finder 留下的元数据目录, 跟 Cyberduck / Transmit
        // 行为一致. S3 上没意义, 删也删不掉 (server 端 list 假返回, HEAD 直接
        // 403), 显示出来只会让用户右键删 → 看到 "已删除 0 个对象" 一脸懵.
        if (isMacOSArtifact(p)) continue;
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
        // 隐藏 macOS 元数据文件 (._xxx, .DS_Store 等), 跟 CommonPrefixes 过滤一致.
        if (isMacOSArtifact(k)) continue;
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
    CancelToken? cancelToken,
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
      cancelToken: cancelToken,
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
    final doc = parseS3Xml(resp.data as String);
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
    final bodyBytes = utf8.encode(body);
    final host = _host(bucket: bucket);
    final path = _pathPrefix(bucket: bucket, key: key);
    final url = '${config.normalizedEndpoint}$path';
    await _signedRequest(
      method: 'POST',
      url: url,
      host: host,
      path: path,
      query: {'uploadId': uploadId},
      body: bodyBytes,
      extraHeaders: {
        'content-type': 'application/xml',
        'content-length': '${bodyBytes.length}',
        // AWS spec 不强制但推荐, 一些严格 S3 实现 (RustFS / Cloudflare R2 边缘节点)
        // 会拒. 加上没坏处.
        'content-md5': contentMd5Base64(bodyBytes),
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
    final bodyBytes = utf8.encode(body);
    final host = _host(bucket: bucket);
    final path = _pathPrefix(bucket: bucket);
    final url = '${config.normalizedEndpoint}$path';
    final resp = await _signedRequest(
      method: 'POST',
      url: url,
      host: host,
      path: path,
      query: {'delete': ''},
      body: bodyBytes,
      extraHeaders: {
        'content-type': 'application/xml',
        'content-length': '${bodyBytes.length}',
        // AWS S3 多对象删除强制要求, 不带就 400 "Missing ContentMD5".
        // 一些老的 S3 兼容实现 (旧 MinIO) 不强制, 加上没坏处, 一并覆盖.
        'content-md5': contentMd5Base64(bodyBytes),
      },
    );
    // 解析返回的 <Error> 计数
    final doc = parseS3Xml(resp.data as String);
    final errors = doc.findAllElements('Error').length;
    return keys.length - errors;
  }

  /// 递归删除某 prefix 下的所有对象 (含 prefix 自身的 marker).
  ///
  /// S3 没真 "目录", list 时看到的 "folder" (CommonPrefixes) 是按 delimiter='/'
  /// 算出的 virtual grouping. 删 "文件夹" 实际是 list + delete 它所有的 key.
  ///
  /// 之前用 [deleteObjects] 直接删 `yolo-hands/`, 只删了那个 0 字节 marker,
  /// `yolo-hands/file1.txt` / `yolo-hands/sub/inner.txt` 实际都还在,
  /// refresh 看起来 "没删干净".
  ///
  /// - 列 prefix 下所有 key (无 delimiter, 任意深度), 跨页继续
  /// - 每批 1000 调用 [deleteObjects] (S3 限制)
  /// - prefix 自身 (e.g. `yolo-hands/`) 也作为 0 字节 marker 一并删
  /// 返回实际删除的对象总数 (含 marker, 不含失败).
  ///
  /// [prefix] 可带可不带尾 '/', 内部规整.
  Future<int> deletePrefix({
    required String bucket,
    required String prefix,
  }) async {
    // 规整 prefix, folder key 总是以 / 结尾 (CommonPrefixes 永远这样).
    // 不强求, 容忍 'yolo-hands' 这种简写
    final normalized = prefix.endsWith('/') ? prefix : '$prefix/';
    if (normalized == '/') {
      throw ArgumentError('prefix 不能是 "/" (会删整个 bucket)');
    }
    int total = 0;
    String? continuationToken;

    do {
      // 列一批 (最多 1000, 跟后续 delete batch 对齐,
      // 一次 list 一次 delete 配对, 内存占用低, 容易加 progress)
      final query = <String, String>{
        'list-type': '2',
        'prefix': normalized,
        // max-keys 不带也行, 1000 是 S3 默认. 显式带防止某些实现给少.
        'max-keys': '1000',
        // 关键: 不带 delimiter, 否则只拿 prefix 下一层, 漏深层.
        // ignore: use_null_aware_elements
        if (continuationToken != null) 'continuation-token': continuationToken,
      };
      final host = _host(bucket: bucket);
      final path = _pathPrefix(bucket: bucket);
      final url = '${config.normalizedEndpoint}$path';
      final resp = await _signedRequest(
        method: 'GET',
        url: url,
        host: host,
        path: path,
        query: query,
      );
      final doc = parseS3Xml(resp.data as String);
      final keys = doc.findAllElements('Contents')
          .map((c) => c.getElement('Key')?.innerText ?? '')
          .where((k) => k.isNotEmpty)
          .toList();

      if (keys.isEmpty) break;

      // 删这一批
      final deleted = await deleteObjects(bucket: bucket, keys: keys);
      total += deleted;

      final truncated = doc.getElement('ListBucketResult')
              ?.getElement('IsTruncated')?.innerText ==
          'true';
      continuationToken = truncated
          ? doc.getElement('ListBucketResult')
              ?.getElement('NextContinuationToken')?.innerText
          : null;
    } while (continuationToken != null);

    // 兜底: list 返回 0 keys 时 (空 folder / phantom marker / @eaDir 之类
    // server 端 list 假返回), 试删 prefix marker 本身. S3 spec 里 folder
    // marker 是 0 字节带尾 '/' 的真 key, 删了才算彻底. deleteObjects 响应
    // 里没 <Error> 就当成功 (即使 server 实际上没 marker, 也无害, 跟 AWS S3
    // 行为一致: delete 不存在的 key 是 idempotent 的 no-op).
    if (total == 0) {
      total += await deleteObjects(bucket: bucket, keys: [normalized]);
    }

    return total;
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
    final doc = parseS3Xml(resp.data as String);
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

/// 安全解析 S3 XML 响应. 先 sniff 是不是 Error 根节点 (RustFS 行为),
/// 没问题就正常 parse 返回给调用方. 之前这里直接把 sniff 跟 parse 揉一起,
/// 调用方如果忘了 sniff (e.g. uploadBytes), 就会吞掉失败.
xml.XmlDocument parseS3Xml(String body) {
  checkS3ErrorBody(body);
  return xml.XmlDocument.parse(body);
}

/// S3 [POST ?delete] (多对象批量删除) 强制要求 [Content-MD5] 头,
/// 服务端用这个 MD5 校验 body 在传输中没被改. AWS S3 文档明确要求,
/// RustFS / 严格实现的 MinIO 也会拒. 没设就 400 "Missing ContentMD5".
/// 返回 base64 编码 (e.g. "1B2M2Y8AsgTpgAmY7PhCfg==").
String contentMd5Base64(List<int> bytes) {
  return base64.encode(md5.convert(bytes).bytes);
}

/// 嗅探 S3 错误响应 body. 命中 `&lt;Error&gt;` 根节点时抛 [S3Error],
/// 让调用方在拿到响应第一时间知道失败, 而不是被 void / 空 list 静默吞掉.
///
/// 覆盖的场景:
/// - RustFS / 部分 MinIO fork: 凭证错 / 无权限 / 路径不存在时返回
///   `HTTP 200` + `<Error><Code>...</Code><Message>...</Message></Error>`.
///   dio 默认 validateStatus 不抛, 业务代码如果不主动 sniff 就当成成功.
void checkS3ErrorBody(String body) {
  // 快速预检: 包含 <Error> 且像 XML 才走 parse 慢路径, 避免对 JSON /
  // 大文件 body 误触发.
  if (!body.contains('<Error>')) return;
  final head = body.trimLeft();
  if (!(head.startsWith('<?xml') || head.startsWith('<'))) return;
  try {
    final probe = xml.XmlDocument.parse(body);
    if (probe.rootElement.name.local == 'Error') {
      final code =
          probe.findAllElements('Code').firstOrNull?.innerText ?? 'Unknown';
      final msg =
          probe.findAllElements('Message').firstOrNull?.innerText ?? '';
      throw S3Error(code, msg);
    }
  } on S3Error {
    rethrow;
  } catch (_) {
    // body 含 <Error> 但 XML parse 失败 (e.g. 不规范), 仍按 Error 处理
    // 避免 RustFS 边界 case 静默吞掉.
    throw S3Error('MalformedError', _truncateBody(body, 200));
  }
}

String _truncateBody(String s, int n) =>
    s.length <= n ? s : '${s.substring(0, n)}...';

/// 判断 S3 key 是不是 macOS / iOS Finder 留下的元数据, 列表展示时该隐藏.
///
/// 之前 list 把 `@eaDir/` 这种目录也带出来, 用户右键 → 删 → `deletePrefix`
/// 走 list 返回 0 keys → 直接 break, snackbar 显示 "已删除 0 个对象".
/// 实际原因:
///   - 某些 S3 兼容服务 (如部分 MinIO / RustFS 部署) 在 list 时把 `@eaDir`
///     当成虚拟 CommonPrefix 返回, 但 key 在 S3 里根本不存在 (HEAD 直接 403).
///   - 即使调 `deleteObjects` 删 `@eaDir/`, server 响应里没 `<Error>`, 我们的
///     "keys - errors" 计数当成 1 删成功, 但 list 还是返回它 (server 端
///     假数据, 没法真删).
///
/// 跟 Cyberduck / Transmit / CloudBerry 行业惯例一致, 直接过滤掉. 覆盖:
///   - `@eaDir/...`  (Finder 资源分叉目录)
///   - `._xxx`      (AppleDouble 文件的元数据)
///   - `.DS_Store`  (桌面服务存储, 跨目录都在)
///   - `.Spotlight-V100/` / `.Trashes/` / `.fseventsd/` (macOS 系统目录)
///   - `.TemporaryItems/` / `.DocumentRevisions-V100/` (Time Machine 临时)
///   - `Thumbs.db`  (Windows 缩略图, 顺手一起)
///
/// 函数对 [isMacOSArtifact] 测试可见 (单参数纯函数), 过滤逻辑在 listObjects
/// 的 CommonPrefixes / Contents 两条路径都用得上, 一处定义保证一致.
@visibleForTesting
bool isMacOSArtifact(String key) {
  if (key.isEmpty) return false;
  // 末段名 (剥掉前缀路径) 才是真正决定因素. e.g. "photos/2024/._IMG_001.jpg"
  // 末段是 "._IMG_001.jpg", 匹配 AppleDouble 规则.
  final lastSlash = key.lastIndexOf('/');
  final basename = lastSlash >= 0 ? key.substring(lastSlash + 1) : key;
  // 以 "._" 开头 (AppleDouble 隐藏元数据)
  if (basename.startsWith('._')) return true;
  // 精确匹配 (大小写敏感, macOS 默认 HFS+/APFS 不区分, 但 S3 key 区分,
  // 我们按 S3 key 的 byte-level 来比)
  const exactNames = <String>{
    '.DS_Store',
    'Thumbs.db',
    'desktop.ini',
  };
  if (exactNames.contains(basename)) return true;
  // 系统目录 (必须带 '/', 防止误伤名字里偶然含这个串的 user file).
  // 注意 @eaDir 经常是嵌套的: e.g. photos/2024/@eaDir/IMG_001.jpg/, 不一定
  // 出现在 path 开头. 用 '/' + dir + '/' 找路径中是否含这个 segment, 匹配
  // "@eaDir/" 出现在中间的情况. 跟 path segment 必须以 '/' 开头对齐, 防止
  // "my_@eaDir/" 这种用户自定义名字误伤.
  const systemDirs = <String>{
    '@eaDir/',
    '.Spotlight-V100/',
    '.Trashes/',
    '.fseventsd/',
    '.TemporaryItems/',
    '.DocumentRevisions-V100/',
  };
  for (final d in systemDirs) {
    if (key == d) return true; // 顶层就是它
    if (key.startsWith(d)) return true; // 顶层下子项
    if (key.contains('/$d')) return true; // 任意深度嵌套 (e.g. photos/2024/@eaDir/...)
  }
  return false;
}

/// S3 服务端在 HTTP 200 里塞 Error XML 时的异常 (RustFS / 部分 MinIO fork 会这样).
/// 比 DioException 简单, 错误信息直接来自服务端 XML 的 Code + Message.
class S3Error implements Exception {
  final String code;
  final String message;
  // 触发这个错的请求 URL, 排错时给开发者看, snackbar 末尾也会显示
  final String? url;
  S3Error(this.code, this.message, {this.url});

  @override
  String toString() {
    final base = 'S3 $code: $message';
    return url == null ? base : '$base\nURL: $url';
  }
}
