/// 把 dio / SocketException / S3 服务端错翻译成人话.
///
/// 之前直接 `error.toString()` 抛出来, 用户看到 "DioException [connection
/// error]: The connection errored: Failed host lookup: 'example.com' This
/// indicates an error which most likely cannot be solved by the library. OS
/// Error: No address associated with hostname, errno = 7." 一脸懵.
///
/// 现在先嗅探常见网络/服务端错, 给具体指引 + 把原始 error 当 detail 留底
/// (UI 层可以选择展开). 命中不到的模式降级到原 error, 不强行误导.
class FriendlyError {
  /// 中文用户友好提示 (主标题). 一句话告诉用户哪里有问题.
  final String message;

  /// 修复建议 (副标题). 给用户下一步动作.
  final String hint;

  /// 原始 error 字符串. UI 可选显示在折叠区, 调试 / 报错时给开发看.
  final String raw;

  const FriendlyError({
    required this.message,
    required this.hint,
    required this.raw,
  });
}

/// 把任意 error 转成 [FriendlyError].
///
/// 嗅探策略: 优先匹配原始 string, 不依赖异常类型 (dio + dart:io 各种包装
/// 层都见过, 类型不稳定, 字符串最稳).
FriendlyError explainError(Object error, {String? context}) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  // ---- 网络层: DNS / 连接 / 超时 ----
  if (lower.contains('failed host lookup') ||
      lower.contains('no address associated with hostname') ||
      lower.contains('errno = 7')) {
    return FriendlyError(
      message: 'DNS 解析失败, 找不到主机',
      hint: '检查 endpoint 拼写 / 域名是否存在 / 当前网络能否访问公网 DNS. '
          '手机和电脑的 DNS 不一样, 电脑能通不代表手机能通.',
      raw: raw,
    );
  }
  if (lower.contains('connection refused') ||
      lower.contains('errno = 111')) {
    return FriendlyError(
      message: '服务器拒绝连接',
      hint: '检查 endpoint 端口 (默认 HTTPS 443 / HTTP 80) / 服务器是否在运行 / '
          '防火墙是否放行.',
      raw: raw,
    );
  }
  if (lower.contains('connection timed out') ||
      lower.contains('timeout') ||
      lower.contains('errno = 110')) {
    return FriendlyError(
      message: '连接超时',
      hint: '网络慢或服务端不响应. 重试一次, 仍超时检查 endpoint 是否对得上.',
      raw: raw,
    );
  }
  if (lower.contains('network is unreachable') ||
      lower.contains('no route to host') ||
      lower.contains('errno = 101')) {
    return FriendlyError(
      message: '网络不可达',
      hint: '检查手机 WiFi / 移动数据 / 是否在企业内网需要 VPN.',
      raw: raw,
    );
  }
  if (lower.contains('handshakeexception') ||
      lower.contains('certificate') ||
      lower.contains('cert_') ||
      lower.contains('ssl_')) {
    return FriendlyError(
      message: 'TLS 握手失败',
      hint: '检查证书是否过期 / 自签证书是否信任. 服务端如果只支持 HTTP, '
          '把 "HTTPS" 切到 "HTTP" 试试.',
      raw: raw,
    );
  }

  // ---- S3 服务端错 (S3Error, 我们自己 sniff 出来的) ----
  // format: "S3 <Code>: <Message>" 或 "S3 HTTP<status>: <Message>" (download 等
  // 走 status code 兜底抛的)
  if (raw.startsWith('S3 ') && raw.contains(':')) {
    final code = raw.substring(3, raw.indexOf(':')).trim();
    // HTTP<status> 形态 (S3Error 来自 _signedRequest status >= 400 兜底)
    if (code.startsWith('HTTP')) {
      final status = int.tryParse(code.substring(4)) ?? 0;
      return FriendlyError(
        message: '服务端 $code',
        hint: _httpStatusHint(status),
        raw: raw,
      );
    }
    return FriendlyError(
      message: '服务端拒绝: $code',
      hint: _s3CodeHint(code),
      raw: raw,
    );
  }

  // ---- AWS SigV4 签名失败 (403 / SignatureDoesNotMatch 等) ----
  if (lower.contains('signature') || lower.contains('accessdenied')) {
    return FriendlyError(
      message: '签名 / 权限失败',
      hint: '检查 access key / secret key 拼写, 确认 IAM 策略有 ListAllMyBuckets '
          '和对应 bucket 的读写权限.',
      raw: raw,
    );
  }

  // ---- 兜底: 不知道什么错, 给原 error ----
  return FriendlyError(
    message: context ?? '操作失败',
    hint: '原始错误在下方, 可截图给开发者看.',
    raw: raw,
  );
}

/// HTTP 状态码 → 中文提示. 覆盖 S3 / generic HTTP server 常见 4xx/5xx.
String _httpStatusHint(int status) {
  switch (status) {
    case 400:
      return '请求格式错, 通常是 key 含服务端不接受的字符, 或分块参数不对.';
    case 401:
      return '未认证, 凭证缺失或过期.';
    case 403:
      return '服务端拒绝访问. IAM 策略 / bucket policy 拒绝该操作, 或凭证无此权限. '
          '某些 S3 兼容实现在无权限时返回 404 而不是 403 (隐藏对象存在性).';
    case 404:
      return '对象 / bucket 不存在. 可能文件已被删除 / 移走 / 名字拼错, 或者 '
          '当前 list 是缓存 (强制刷新再试).';
    case 405:
      return '服务端不允许该方法, bucket policy 限制. 换 endpoint 试试.';
    case 409:
      return '冲突, 比如分块上传时 part 已存在或 bucket 已存在同名对象.';
    case 412:
      return '前置条件失败 (If-Match / If-None-Match 等).';
    case 416:
      return 'Range 越界, 分块下载时 part 号超限.';
    case 429:
      return '请求过频被限流, 降低频率重试.';
    case 500:
    case 502:
    case 503:
    case 504:
      return '服务端内部错误, 重试一次. 持续失败说明服务端真挂了.';
    default:
      if (status >= 500) return '服务端错误, 重试或联系运维.';
      if (status >= 400) return '请求被拒绝, 检查 key / 权限 / 服务端配置.';
      return '意外的 HTTP 状态.';
  }
}

/// S3 错误码 → 中文提示. 没收录的给通用 "检查权限 / bucket 是否存在".
String _s3CodeHint(String code) {
  switch (code) {
    case 'NoSuchBucket':
      return 'Bucket 不存在或没在当前 endpoint 下, 检查拼写或服务端配置.';
    case 'NoSuchKey':
      return '对象 key 不存在, 可能被删除或被移到别处.';
    case 'AccessDenied':
      return 'IAM 策略拒绝, 确认 access key 有该 bucket / prefix 的访问权限.';
    case 'InvalidAccessKeyId':
      return 'access key 无效或被禁用, 检查凭证是否过期.';
    case 'SignatureDoesNotMatch':
      return '签名不匹配, access key / secret key 不匹配, 或系统时间漂移过大.';
    case 'MethodNotAllowed':
      return '服务端不支持该方法, 可能是 bucket policy 限制, 换个 endpoint 试试.';
    case 'MalformedXML':
    case 'InvalidRequest':
      return '请求格式被服务端拒绝, 通常是 S3 兼容实现的 bug, 看看详细错误.';
    case 'SlowDown':
      return '服务端限流, 降低请求频率.';
    case 'InternalError':
      return '服务端内部错误, 重试一次.';
    default:
      return '检查 S3 服务端日志, 或对照 AWS 文档看该错误码含义.';
  }
}
