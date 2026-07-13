import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 's3_config.dart';
import '../../data/models/server.dart';

/// 多服务器持久化. SharedPreferences 一把 key 存整个 `List<Server>`.
///
/// 历史兼容: 旧版 (v1) 把单个 S3Config 编码成 query-string 形式塞在
/// `s3browser.config.v1` 里. 第一次加载 v2 列表为空时, 检测这个 key,
/// 解码后包装成 [Server] 导入, 删除旧 key.
class ServerStore {
  static const _serversKey = 's3browser.servers.v2';
  static const _legacyKey = 's3browser.config.v1';
  static const _uuid = Uuid();

  Future<List<Server>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_serversKey);
    if (raw == null || raw.isEmpty) {
      // 尝试迁移 v1
      final migrated = await _tryMigrateLegacy(p);
      return migrated;
    }
    try {
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      return list
          .map((e) => Server.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      // 数据坏了 — 清掉重来
      await p.remove(_serversKey);
      return [];
    }
  }

  Future<void> save(List<Server> servers) async {
    final p = await SharedPreferences.getInstance();
    final encoded = jsonEncode(servers.map((s) => s.toJson()).toList());
    await p.setString(_serversKey, encoded);
  }

  /// 生成新 server id (uuid v4).
  String newId() => _uuid.v4();

  /// 旧 v1 格式解码 + 包装为 Server. 失败或不存在返回 null.
  ///
  /// v1 把所有值 URL-encode 成 string, 但 [S3Config.fromJson] 期望 `pathStyle` /
  /// `secure` 是 bool. 这里做类型转换.
  S3Config? _decodeLegacy(String raw) {
    try {
      final stringMap = <String, dynamic>{};
      for (final pair in raw.split('&')) {
        if (pair.isEmpty) continue;
        final i = pair.indexOf('=');
        if (i < 0) continue;
        final k = pair.substring(0, i);
        final v = Uri.decodeComponent(pair.substring(i + 1));
        stringMap[k] = v == 'null' ? null : v;
      }
      // 转成 S3Config.fromJson 期望的类型
      final typed = <String, dynamic>{
        'endpoint': stringMap['endpoint'] as String?,
        'region': stringMap['region'] as String? ?? 'us-east-1',
        'accessKey': stringMap['accessKey'] as String?,
        'secretKey': stringMap['secretKey'] as String?,
        'defaultBucket': stringMap['defaultBucket'] as String?,
        'pathStyle': stringMap['pathStyle'] == 'true',
        'secure': stringMap['secure'] == 'true',
      };
      return S3Config.fromJson(typed);
    } catch (_) {
      return null;
    }
  }

  /// 从 [S3Config.endpoint] 提取 host:port 作为默认名.
  /// 例: `s3.amazonaws.com`, `minio.local:9000`, `localhost:9000`.
  /// 包含端口以便区分同 host 不同端口的 server (如本地多个 MinIO 实例).
  String defaultName(S3Config cfg) {
    var e = cfg.endpoint.trim();
    if (e.isEmpty) return '未命名';
    if (!e.startsWith('http://') && !e.startsWith('https://')) {
      e = 'https://$e';
    }
    final uri = Uri.tryParse(e);
    if (uri == null) return cfg.endpoint;
    final host = uri.host;
    if (host.isEmpty) return cfg.endpoint;
    // authority = host:port (有端口时); 标准端口 80/443 时省略
    if (uri.hasPort &&
        uri.port != 80 &&
        uri.port != 443) {
      return '$host:${uri.port}';
    }
    return host;
  }

  Future<List<Server>> _tryMigrateLegacy(SharedPreferences p) async {
    final legacyRaw = p.getString(_legacyKey);
    if (legacyRaw == null || legacyRaw.isEmpty) return [];
    final cfg = _decodeLegacy(legacyRaw);
    if (cfg == null) {
      // 旧数据损坏, 顺手清掉
      await p.remove(_legacyKey);
      return [];
    }
    final s = Server(
      id: newId(),
      name: defaultName(cfg),
      config: cfg,
    );
    await save([s]);
    await p.remove(_legacyKey);
    return [s];
  }
}
