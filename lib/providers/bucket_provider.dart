import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/s3_object.dart';
import 'active_server_provider.dart';

/// 当前浏览的 bucket 名. null = 还没选.
final currentBucketProvider = StateProvider<String?>((ref) {
  final s = ref.watch(activeServerProvider);
  return s?.config.defaultBucket;
});

/// 当前路径 (prefix), 空字符串 = 根.
final currentPrefixProvider = StateProvider<String>((ref) => '');

/// 文件列表排序字段.
enum SortBy { name, date, size }

/// 文件列表当前状态. 不仅存数据, 还存排序 (客户端排序, 不触发 refetch).
class ObjectListNotifier
    extends StateNotifier<AsyncValue<List<S3Object>>> {
  final Ref ref;
  SortBy _sortBy = SortBy.name;
  bool _sortAsc = true;

  ObjectListNotifier(this.ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  SortBy get sortBy => _sortBy;
  bool get sortAsc => _sortAsc;

  Future<void> refresh() async {
    final client = ref.read(s3ClientProvider);
    final bucket = ref.read(currentBucketProvider);
    if (client == null || bucket == null) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final prefix = ref.read(currentPrefixProvider);
      final list = await client.listObjects(
        bucket: bucket,
        prefix: prefix,
        delimiter: '/',
      );
      state = AsyncValue.data(_applySort(list));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 点击列头: 同列翻转方向, 异列切到该列 (默认升序)
  void setSort(SortBy by) {
    if (_sortBy == by) {
      _sortAsc = !_sortAsc;
    } else {
      _sortBy = by;
      _sortAsc = true;
    }
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(_applySort(current));
    }
  }

  List<S3Object> _applySort(List<S3Object> list) {
    final sorted = [...list];
    sorted.sort((a, b) {
      // 文件夹永远在前 (无论升序降序)
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      int cmp;
      switch (_sortBy) {
        case SortBy.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case SortBy.date:
          cmp = (a.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0));
          break;
        case SortBy.size:
          cmp = a.size.compareTo(b.size);
          break;
      }
      return _sortAsc ? cmp : -cmp;
    });
    return sorted;
  }
}

final objectListProvider =
    StateNotifierProvider<ObjectListNotifier, AsyncValue<List<S3Object>>>(
  (ref) => ObjectListNotifier(ref),
);

/// 多选状态. key = S3 full key, bool = 是否选中.
class SelectionNotifier extends StateNotifier<Set<String>> {
  SelectionNotifier() : super(<String>{});

  void toggle(String key) {
    final s = {...state};
    if (s.contains(key)) {
      s.remove(key);
    } else {
      s.add(key);
    }
    state = s;
  }

  void selectOnly(String key) {
    state = {key};
  }

  void selectAll(Iterable<String> keys) {
    state = {...state, ...keys};
  }

  void clear() {
    state = <String>{};
  }
}

final selectionProvider =
    StateNotifierProvider<SelectionNotifier, Set<String>>(
  (ref) => SelectionNotifier(),
);

/// 当前 bucket 列表.
final bucketListProvider =
    FutureProvider<List<String>>((ref) async {
  final client = ref.watch(s3ClientProvider);
  if (client == null) return const [];
  return client.listBuckets();
});
