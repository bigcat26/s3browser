import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/server_store.dart';
import '../data/models/server.dart';

/// 所有 server 列表 (持久化). UI 增删改都走这里.
class ServerListNotifier extends StateNotifier<AsyncValue<List<Server>>> {
  final ServerStore _store = ServerStore();

  ServerListNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final list = await _store.load();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> reload() => _load();

  /// 新增 server. [name] 重复时抛 [ArgumentError].
  Future<Server> add(Server s) async {
    final current = state.value ?? const <Server>[];
    if (current.any((x) => x.name == s.name)) {
      throw ArgumentError('已存在同名服务器: ${s.name}');
    }
    final next = [...current, s];
    await _store.save(next);
    state = AsyncValue.data(next);
    return s;
  }

  /// 更新 server (按 id 匹配). [name] 跟其他 server 重复时抛 [ArgumentError].
  Future<Server> update(Server s) async {
    final current = state.value ?? const <Server>[];
    if (current.any((x) => x.id != s.id && x.name == s.name)) {
      throw ArgumentError('已存在同名服务器: ${s.name}');
    }
    final next = current.map((x) => x.id == s.id ? s : x).toList();
    await _store.save(next);
    state = AsyncValue.data(next);
    return s;
  }

  /// 删除 server. 如果它是当前激活的, 由 UI 负责清掉 activeServer.
  Future<void> delete(String id) async {
    final current = state.value ?? const <Server>[];
    final next = current.where((x) => x.id != id).toList();
    await _store.save(next);
    state = AsyncValue.data(next);
  }
}

final serverListProvider =
    StateNotifierProvider<ServerListNotifier, AsyncValue<List<Server>>>(
  (ref) => ServerListNotifier(),
);
