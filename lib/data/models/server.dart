import '../../core/config/s3_config.dart';

/// 一个 S3/MinIO 服务器 = 一个独立的 S3Config + 用户起的名字.
///
/// - [id] uuid v4, 稳定标识 (重命名 server 时不变)
/// - [name] 用户起的显示名, 非空, 在 server 列表中唯一
/// - [config] 实际的 endpoint/keys/region 配置
class Server {
  final String id;
  final String name;
  final S3Config config;

  const Server({
    required this.id,
    required this.name,
    required this.config,
  });

  Server copyWith({String? name, S3Config? config}) => Server(
        id: id,
        name: name ?? this.name,
        config: config ?? this.config,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'config': config.toJson(),
      };

  factory Server.fromJson(Map<String, dynamic> j) => Server(
        id: j['id'] as String,
        name: j['name'] as String,
        config: S3Config.fromJson(j['config'] as Map<String, dynamic>),
      );

  @override
  String toString() => 'Server($name @ ${config.normalizedEndpoint})';
}
