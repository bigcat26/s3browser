/// S3/MinIO 连接配置.
///
/// - [endpoint] 可以是 S3 (`s3.amazonaws.com`) 或 MinIO (`minio.local:9000`)
///   是否带 scheme 都可, 内部统一补 `https://`
/// - [pathStyle] MinIO 必须用 true (path-style), AWS S3 默认 virtual-hosted
/// - [secure] false → HTTP, true → HTTPS
class S3Config {
  final String endpoint;
  final String region;
  final String accessKey;
  final String secretKey;
  final String? defaultBucket; // 启动后默认进入的 bucket, 可空
  final bool pathStyle;
  final bool secure;

  const S3Config({
    required this.endpoint,
    required this.region,
    required this.accessKey,
    required this.secretKey,
    this.defaultBucket,
    this.pathStyle = true, // MinIO 默认开; AWS S3 可关
    this.secure = true,
  });

  S3Config copyWith({
    String? endpoint,
    String? region,
    String? accessKey,
    String? secretKey,
    String? defaultBucket,
    bool? pathStyle,
    bool? secure,
  }) =>
      S3Config(
        endpoint: endpoint ?? this.endpoint,
        region: region ?? this.region,
        accessKey: accessKey ?? this.accessKey,
        secretKey: secretKey ?? this.secretKey,
        defaultBucket: defaultBucket ?? this.defaultBucket,
        pathStyle: pathStyle ?? this.pathStyle,
        secure: secure ?? this.secure,
      );

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'region': region,
        'accessKey': accessKey,
        'secretKey': secretKey,
        'defaultBucket': defaultBucket,
        'pathStyle': pathStyle,
        'secure': secure,
      };

  factory S3Config.fromJson(Map<String, dynamic> j) => S3Config(
        endpoint: j['endpoint'] as String,
        region: j['region'] as String? ?? 'us-east-1',
        accessKey: j['accessKey'] as String,
        secretKey: j['secretKey'] as String,
        defaultBucket: j['defaultBucket'] as String?,
        pathStyle: j['pathStyle'] as bool? ?? true,
        secure: j['secure'] as bool? ?? true,
      );

  /// 规范化 endpoint URL. 缺 scheme 默认补 `https://`.
  String get normalizedEndpoint {
    var e = endpoint.trim();
    if (e.isEmpty) return '';
    if (!e.startsWith('http://') && !e.startsWith('https://')) {
      e = '${secure ? 'https' : 'http'}://$e';
    }
    // 去掉尾斜杠
    while (e.endsWith('/')) {
      e = e.substring(0, e.length - 1);
    }
    return e;
  }

  @override
  String toString() =>
      'S3Config($normalizedEndpoint, region=$region, pathStyle=$pathStyle)';
}
