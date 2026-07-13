import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/server.dart';
import '../data/s3_client.dart';

/// 当前激活的 server. 启动时为 null — 用户从 [ServerListPage] 选一个进入.
/// 不持久化: 每次启动都从列表开始, 避免 stale credential / 上次 server 凭证失效.
class ActiveServerNotifier extends StateNotifier<Server?> {
  ActiveServerNotifier() : super(null);

  void set(Server s) => state = s;
  void clear() => state = null;
}

final activeServerProvider =
    StateNotifierProvider<ActiveServerNotifier, Server?>(
  (ref) => ActiveServerNotifier(),
);

/// 当前 S3 client (派生自 activeServer). 没有 active server 时返回 null.
final s3ClientProvider = Provider<S3Client?>((ref) {
  final s = ref.watch(activeServerProvider);
  if (s == null) return null;
  return S3Client(s.config);
});
