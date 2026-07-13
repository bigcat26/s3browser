import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart' hide DropTarget;

import '../../core/theme/app_theme.dart';
import '../../data/models/s3_object.dart';
import '../../data/models/server.dart';
import '../../providers/active_server_provider.dart';
import '../../providers/bucket_provider.dart';
import '../../providers/server_list_provider.dart';
import '../servers/server_form_page.dart';
import '../theme_menu_button.dart';
import 'widgets/batch_action_bar.dart';
import 'widgets/drop_target.dart';
import 'widgets/file_list_header.dart';
import 'widgets/file_tile.dart';
import 'dialogs/upload_dialog.dart';
import 'dialogs/move_dialog.dart';
import 'dialogs/new_folder_dialog.dart';
import 'dialogs/rename_dialog.dart';

class BrowserPage extends ConsumerStatefulWidget {
  const BrowserPage({super.key});
  @override
  ConsumerState<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends ConsumerState<BrowserPage> {
  bool _gridView = false;
  bool _isDragHovering = false;
  // breadcrumb 横向 ScrollController: 长路径自动滚到尾部,
  // 让用户始终看到当前目录 (跟 macOS Finder / Files 行为一致).
  final ScrollController _breadcrumbController = ScrollController();

  @override
  void dispose() {
    _breadcrumbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeServerProvider);
    final bucket = ref.watch(currentBucketProvider);
    final asyncList = ref.watch(objectListProvider);
    final selected = ref.watch(selectionProvider);
    final hasSelection = selected.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        // 没选 bucket 时, AppBar 显示返回箭头 → 清除 active server 回到首页
        // (Navigator.canPop 不可靠, 这里用 bucket==null 显式判断)
        leading: bucket == null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回服务器列表',
                onPressed: () {
                  ref.read(currentBucketProvider.notifier).state = null;
                  ref.read(currentPrefixProvider.notifier).state = '';
                  ref.read(selectionProvider.notifier).clear();
                  ref.read(activeServerProvider.notifier).clear();
                },
              )
            : null,
        automaticallyImplyLeading: false,
        title: _buildTitle(active, bucket),
        actions: [
          IconButton(
            icon: Icon(_gridView ? Icons.view_list_outlined : Icons.grid_view_outlined),
            tooltip: _gridView ? '列表视图' : '网格视图',
            onPressed: () => setState(() => _gridView = !_gridView),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建文件夹',
            onPressed: bucket == null ? null : _showNewFolderDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => ref.read(objectListProvider.notifier).refresh(),
          ),
          const ThemeMenuButton(),
          // 切换服务器入口已经在 AppBar 标题里 (server 名字可点 → 弹切换 sheet),
          // 这里的 more_horiz 弹窗只一个 "切换服务器" 项, 重复了, 去掉.
        ],
      ),
      body: Column(
        children: [
          _buildBreadcrumb(),
          Expanded(
            child: _buildBody(asyncList, hasSelection, bucket),
          ),
        ],
      ),
      bottomNavigationBar: hasSelection
          ? BatchActionBar(
              selectedCount: selected.length,
              onClear: () => ref.read(selectionProvider.notifier).clear(),
              onDelete: _deleteSelected,
              onMove: _moveSelected,
              onDownload: _downloadSelected,
            )
          : const _StatusBar(),
      floatingActionButton: bucket == null
          ? null
          : FloatingActionButton(
              onPressed: _showUploadSheet,
              tooltip: '上传',
              child: const Icon(Icons.upload, size: 20),
            ),
    );
  }

  Widget _buildTitle(Server? active, String? bucket) {
    if (active == null) return const Text('S3 Browser');
    // 只显示 server, bucket 挪到 breadcrumb 第一段 (点它可换 bucket).
    // AppBar title slot 宽度有限, server+bucket 都显示在 720px 窗口下都会被截.
    return _AppBarLink(
      label: active.name,
      color: Theme.of(context).colorScheme.onSurface,
      tooltip: '切换服务器',
      onTap: _showServerSwitcher,
    );
  }

  Future<void> _showServerSwitcher() async {
    final theme = Theme.of(context);
    final servers =
        ref.read(serverListProvider).value ?? const <Server>[];
    if (servers.isEmpty) return;
    final active = ref.read(activeServerProvider);
    final messenger = ScaffoldMessenger.of(context);

    // 用 showMenu 不够灵活 (高度受限), 用 showModalBottomSheet 更稳
    final picked = await showModalBottomSheet<Server>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        '切换服务器',
                        style: theme.textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        tooltip: '添加新服务器',
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ServerFormPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '${servers.length} 已配置',
                    style: theme.textTheme.eyebrow?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: servers.length,
                    itemBuilder: (_, i) {
                      final s = servers[i];
                      final isCurrent = s.id == active?.id;
                      return ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.check_circle
                              : Icons.dns_outlined,
                          size: 18,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                        ),
                        title: Text(
                          s.name,
                          style: TextStyle(
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isCurrent
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          s.config.normalizedEndpoint,
                          style: theme.textTheme.mono?.copyWith(fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: '编辑',
                          onPressed: () {
                            // 关闭 sheet, 推 edit 表单
                            Navigator.pop(ctx);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ServerFormPage(existing: s),
                              ),
                            );
                          },
                        ),
                        onTap: () => Navigator.pop(ctx, s),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && picked.id != active?.id) {
      // 切换 server: 重置 bucket/prefix/selection, 激活新 server
      ref.read(currentBucketProvider.notifier).state = null;
      ref.read(currentPrefixProvider.notifier).state = '';
      ref.read(selectionProvider.notifier).clear();
      ref.read(activeServerProvider.notifier).set(picked);
      messenger.showSnackBar(
        SnackBar(content: Text('已切换到 ${picked.name}')),
      );
    }
  }

  Widget _buildBreadcrumb() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final prefix = ref.watch(currentPrefixProvider);
    final bucket = ref.watch(currentBucketProvider);
    final segments = prefix.split('/').where((s) => s.isNotEmpty).toList();
    // 长路径时滚到最右边, 始终让用户看到当前目录 (跟 macOS Finder 一致).
    // 每次 build 都触发, 因为 prefix/bucket 变化后整条 row 重排,
    // maxScrollExtent 会变, 必须重新 jumpTo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_breadcrumbController.hasClients) return;
      final pos = _breadcrumbController.position;
      if (pos.maxScrollExtent > 0) {
        _breadcrumbController.jumpTo(pos.maxScrollExtent);
      }
    });
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outline, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _breadcrumbController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // bucket 提到最前 (替换原来的 "/").
                  // 拆 icon + 名字两个点击区:
                  //   - icon  → 切换 bucket (弹 picker)
                  //   - 名字  → 回到当前 bucket 根目录
                  // 没选 bucket 时这一段直接隐藏, breadcrumb 显示一个 "/" 提示.
                  if (bucket != null) ...[
                    _BucketCrumb(
                      label: bucket,
                      onIconTap: _showBucketPicker,
                      onLabelTap: () {
                        ref.read(currentPrefixProvider.notifier).state = '';
                        ref.read(objectListProvider.notifier).refresh();
                      },
                    ),
                    for (var i = 0; i < segments.length; i++) ...[
                      const SizedBox(width: 4),
                      _Crumb(label: segments[i], isSegment: true, onTap: () {
                        final joined = segments.sublist(0, i + 1).join('/');
                        ref.read(currentPrefixProvider.notifier).state =
                            '$joined/';
                        ref.read(objectListProvider.notifier).refresh();
                      }),
                    ],
                  ] else
                    _Crumb(label: '/', onTap: () {
                      // 没 bucket 时点 "/" 弹 bucket picker
                      _showBucketPicker();
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _CopyPathButton(bucket: bucket, prefix: prefix),
        ],
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<S3Object>> asyncList, bool hasSelection,
      String? bucket) {
    if (bucket == null) {
      return const _NoBucketState();
    }

    return asyncList.when(
      loading: () => const _LoadingState(),
      error: (e, _) => _ErrorState(error: e.toString()),
      data: (objects) {
        if (objects.isEmpty) {
          return const _EmptyDirState();
        }
        final listWidget = _gridView
            ? _buildGrid(objects, hasSelection)
            : _buildList(objects, hasSelection);
        if (kIsWeb) return listWidget;
        return DropTarget(
          onDragEntered: () => setState(() => _isDragHovering = true),
          onDragExited: () => setState(() => _isDragHovering = false),
          onDragDone: (detail) async {
            setState(() => _isDragHovering = false);
            await _handleDrop(detail);
          },
          child: Stack(
            children: [
              listWidget,
              if (_isDragHovering)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.10),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '松开以上传',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(List<S3Object> objects, bool hasSelection) {
    return Column(
      children: [
        FileListHeader(objects: objects),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 0, bottom: 80),
            itemCount: objects.length,
            itemBuilder: (_, i) => _buildRow(objects[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(List<S3Object> objects, bool hasSelection) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.9,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: objects.length,
      itemBuilder: (_, i) => _buildRow(objects[i], isGrid: true),
    );
  }

  Widget _buildRow(S3Object obj, {bool isGrid = false}) {
    return FileTile(
      object: obj,
      isGrid: isGrid,
      onTap: () => _handleTap(obj),
      onLongPress: () {
        ref.read(selectionProvider.notifier).toggle(obj.key);
      },
      onAction: (action) => _handleAction(obj, action),
    );
  }

  // ---- 动作 ----

  void _handleTap(S3Object obj) {
    // 选择态模式: 已有任何选中 → 行身点击 = 切换该行选择, 不 navigate.
    // 避免误点行身 (想点 checkbox 实际点到空白) 直接进 folder 丢选择.
    if (ref.read(selectionProvider).isNotEmpty) {
      ref.read(selectionProvider.notifier).toggle(obj.key);
      return;
    }
    // 无选择态: 行身点击 = navigate (folder) 或 download (file).
    if (obj.isFolder) {
      ref.read(currentPrefixProvider.notifier).state = obj.key;
      ref.read(objectListProvider.notifier).refresh();
    } else {
      _downloadSingle(obj);
    }
  }

  Future<void> _handleAction(S3Object obj, FileAction action) async {
    switch (action) {
      case FileAction.delete:
        // 单个删除也走二次确认. folder 递归删尤其危险, 右键误点就可能
        // 把整棵子树干掉. 显示具体名字比 "1 个对象" 更让用户有 context.
        final hint = obj.isFolder
            ? '将删除文件夹 "${obj.name}" (含其下所有内容), 此操作不可撤销.'
            : '将删除文件 "${obj.name}", 此操作不可撤销.';
        if (!await _confirmDelete(hint)) return;
        await _deleteKeys([obj.key]);
        break;
      case FileAction.rename:
        final newName = await showRenameDialog(context, obj.name);
        if (newName == null || newName == obj.name) return;
        await _renameObject(obj, newName);
        break;
      case FileAction.move:
        await _moveKeys([obj.key]);
        break;
      case FileAction.download:
        await _downloadSingle(obj);
        break;
      case FileAction.select:
        // 菜单里没有这个 action 了, 保留 case 是为了 enum 兼容
        ref.read(selectionProvider.notifier).toggle(obj.key);
        break;
    }
  }

  Future<void> _deleteSelected() async {
    final sel = ref.read(selectionProvider);
    if (sel.isEmpty) return;
    // 区分 folder vs file 给用户更准确的提示.
    // folder 会递归删 (里面所有子文件 + 子 folder 都删), 数量远超 selection 大小.
    final objects = ref.read(objectListProvider).value ?? const <S3Object>[];
    final byKey = {for (final o in objects) o.key: o};
    final folderCount = sel.where((k) => byKey[k]?.isFolder ?? false).length;
    final fileCount = sel.length - folderCount;
    final hint = folderCount == 0
        ? '将删除 $fileCount 个文件, 此操作不可撤销.'
        : '将删除 $fileCount 个文件 + $folderCount 个文件夹 (含其下所有内容), 此操作不可撤销.';
    if (!await _confirmDelete(hint)) return;
    await _deleteKeys(sel.toList());
  }

  /// 二次确认弹窗. 抽出成 helper 复用, 保证:
  /// 1. 单个删除 (右键菜单 → 删除) 跟批量删除 (BatchActionBar) 走同一套 UI
  /// 2. 加了递归删之后, 任何 delete 路径都先弹窗, 防止误点右键 → 文件夹整个子树没了
  /// 3. 删除按钮用 error 红色, 跟 cancel 视觉上拉开差距
  Future<bool> _confirmDelete(String hint) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(hint),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteKeys(List<String> keys) async {
    final client = ref.read(s3ClientProvider);
    final bucket = ref.read(currentBucketProvider);
    if (client == null || bucket == null) return;
    // 区分 folder vs file:
    // - folder → 递归删 (list + delete 整 prefix 下所有 key + marker)
    // - file → 走原来的批量删
    // selection 只存 key, 不知道 isFolder, 从当前 objectList 查.
    final objects = ref.read(objectListProvider).value ?? const <S3Object>[];
    final byKey = {for (final o in objects) o.key: o};
    final folderKeys = <String>[];
    final fileKeys = <String>[];
    for (final k in keys) {
      if (byKey[k]?.isFolder ?? false) {
        folderKeys.add(k);
      } else {
        fileKeys.add(k);
      }
    }
    try {
      int total = 0;
      // folder 一个一个删 (每个内部 list+delete 跨页, 慢但稳, 大 folder 给点耐心)
      for (final p in folderKeys) {
        total += await client.deletePrefix(bucket: bucket, prefix: p);
      }
      if (fileKeys.isNotEmpty) {
        // fileKeys 上限 1000 (S3 限制), 多选超出要 chunk. 先简化: 1000 内一次删.
        // 大批量多选场景暂时少见, 真碰到了再分批.
        if (fileKeys.length > 1000) {
          for (final batch in _chunked(fileKeys, 1000)) {
            total += await client.deleteObjects(bucket: bucket, keys: batch);
          }
        } else {
          total += await client.deleteObjects(bucket: bucket, keys: fileKeys);
        }
      }
      ref.read(selectionProvider.notifier).clear();
      ref.read(objectListProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 $total 个对象')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  /// 把 list 切成 size 大小的 batch, 给 [S3Client.deleteObjects] 用
  /// (S3 限制单次 1000 keys).
  List<List<T>> _chunked<T>(List<T> list, int size) {
    final out = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      out.add(list.sublist(i, (i + size).clamp(0, list.length)));
    }
    return out;
  }

  Future<void> _moveSelected() async {
    final sel = ref.read(selectionProvider).toList();
    if (sel.isEmpty) return;
    await _moveKeys(sel);
  }

  Future<void> _moveKeys(List<String> keys) async {
    final dstPrefix = await showMoveDialog(
      context,
      ref.read(currentPrefixProvider),
    );
    if (dstPrefix == null) return;
    final client = ref.read(s3ClientProvider);
    final bucket = ref.read(currentBucketProvider);
    if (client == null || bucket == null) return;
    int ok = 0, fail = 0;
    for (final key in keys) {
      try {
        final name = key.split('/').last;
        final dst =
            dstPrefix.endsWith('/') ? '$dstPrefix$name' : '$dstPrefix/$name';
        await client.moveObject(bucket: bucket, srcKey: key, dstKey: dst);
        ok++;
      } catch (_) {
        fail++;
      }
    }
    ref.read(selectionProvider.notifier).clear();
    ref.read(objectListProvider.notifier).refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移动: 成功 $ok, 失败 $fail')),
      );
    }
  }

  Future<void> _renameObject(S3Object obj, String newName) async {
    final client = ref.read(s3ClientProvider);
    final bucket = ref.read(currentBucketProvider);
    if (client == null || bucket == null) return;
    final parent = obj.key.substring(0, obj.key.length - obj.name.length);
    final newKey = '$parent$newName';
    try {
      await client.moveObject(bucket: bucket, srcKey: obj.key, dstKey: newKey);
      ref.read(objectListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重命名失败: $e')),
        );
      }
    }
  }

  Future<void> _downloadSelected() async {
    final sel = ref.read(selectionProvider).toList();
    if (sel.isEmpty) return;
    for (final key in sel) {
      final obj = S3Object(
        key: key,
        name: key.split('/').last,
        size: 0,
        lastModified: null,
        etag: null,
        isFolder: false,
        prefix: key,
      );
      await _downloadSingle(obj);
    }
  }

  Future<void> _downloadSingle(S3Object obj) async {
    if (obj.isFolder) return;
    final client = ref.read(s3ClientProvider);
    final bucket = ref.read(currentBucketProvider);
    if (client == null || bucket == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = p.join(dir.path, 's3browser', bucket, obj.name);
      await client.downloadObject(
        bucket: bucket,
        key: obj.key,
        savePath: savePath,
        onProgress: (received, total) {},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已下载到 $savePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => UploadSheet(
        prefix: ref.read(currentPrefixProvider),
      ),
    );
  }

  Future<void> _handleDrop(DropDoneDetails detail) async {
    final prefix = ref.read(currentPrefixProvider);
    for (final x in detail.files) {
      final file = x.path.isNotEmpty ? File(x.path) : null;
      if (file == null || !file.existsSync()) continue;
      final key = '$prefix${x.name}';
      await _uploadFile(file, key);
    }
    ref.read(objectListProvider.notifier).refresh();
  }

  Future<void> _uploadFile(File file, String key) async {
    final client = ref.read(s3ClientProvider);
    final bucket = ref.read(currentBucketProvider);
    if (client == null || bucket == null) return;
    try {
      await client.uploadFile(
        bucket: bucket,
        key: key,
        localPath: file.path,
        onProgress: (sent, total) {},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传 $key 失败: $e')),
        );
      }
    }
  }

  Future<void> _showBucketPicker() async {
    final client = ref.read(s3ClientProvider);
    if (client == null) return;
    final buckets = await client.listBuckets();
    if (!mounted) return;
    final theme = Theme.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.colorScheme.outline),
        ),
        title: Text(
          '选择 BUCKET',
          style: theme.textTheme.eyebrow?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        children: [
          for (final b in buckets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, b),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 16),
                  const SizedBox(width: 10),
                  Text(b, style: theme.textTheme.mono),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      ref.read(currentBucketProvider.notifier).state = picked;
      ref.read(currentPrefixProvider.notifier).state = '';
      ref.read(objectListProvider.notifier).refresh();
    }
  }

  Future<void> _showNewFolderDialog() async {
    final prefix = ref.read(currentPrefixProvider);
    final key = await NewFolderDialog.show(context, prefix);
    if (key != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check, size: 16, color: AppTheme.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '已创建 $key',
                  style: Theme.of(context).textTheme.mono?.copyWith(
                        fontSize: 12,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

// ============== 状态栏 ==============

/// 底部状态栏: 不再重复显示 server/bucket/prefix (这三项已经在 AppBar 标题和
/// breadcrumb 里), 改为展示当前列表的 "状态": 对象数 + 排序 + 总大小.
///
/// 单行紧凑布局, 永远不截断, 也不挤占窗口高度.
class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final asyncList = ref.watch(objectListProvider);
    final notifier = ref.read(objectListProvider.notifier);
    final sortBy = notifier.sortBy;
    final sortAsc = notifier.sortAsc;
    final objects = asyncList.value;
    final count = objects?.length;
    // 总大小: folder.size 永远是 0, 自然不进总和
    final totalBytes = objects?.fold<int>(0, (sum, o) => sum + o.size) ?? 0;
    final hasContent = count != null;
    // 没数据 (loading 或没选 bucket) 时, 状态栏留空白 + 排序指示器.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outline, width: 1),
        ),
      ),
      child: Row(
        children: [
          // 左: 对象数 (loading 时显示 —, 避免突兀)
          _StatusItem(
            label: 'ITEMS',
            value: hasContent ? '$count' : '—',
            mono: true,
          ),
          const _StatusSeparator(),
          // 中: 当前排序 (任何时候都显示, 是用户操作的反馈)
          _StatusItem(
            label: 'SORT',
            value: '${_sortLabel(sortBy)} ${sortAsc ? "↑" : "↓"}',
          ),
          if (hasContent && totalBytes > 0) ...[
            const _StatusSeparator(),
            // 右: 总大小, 单段. 只在有真实文件时显示, 0 字节 / 纯 folder 不显示
            // (folder 自身 size=0, 全是 folder 时 totalBytes=0 容易让人误以为没加载).
            Flexible(
              child: _StatusItem(
                label: 'TOTAL',
                value: _formatBytes(totalBytes),
                mono: true,
                ellipsis: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _sortLabel(SortBy by) {
    switch (by) {
      case SortBy.name:
        return 'NAME';
      case SortBy.date:
        return 'DATE';
      case SortBy.size:
        return 'SIZE';
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _StatusItem extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final bool ellipsis;

  const _StatusItem({
    required this.label,
    required this.value,
    this.mono = false,
    this.ellipsis = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle =
        (mono ? theme.textTheme.mono : theme.textTheme.bodySmall)?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
      fontWeight: FontWeight.w500,
      fontSize: 11,
      height: 1.2, // 显式收紧行高, 避免 Material 3 默认 1.4 撑出底部
    );
    // 紧凑 label: 字号 8 + letter-spacing 0, 避免 "BUCKET/PREFIX/OBJECTS"
    // 在窄宽度 Expanded (~32-44px) 下撑爆剩余空间
    final labelStyle = TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontSize: 8,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      height: 1.2,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
    );
    return LayoutBuilder(
      builder: (ctx, c) {
        // 极窄 (< 50px) 时隐藏 label, 只显示 value, 避免 Text 的 natural
        // width (e.g. "my-bucket" ~50px) 在 Expanded 内仍被算入 Row intrinsic,
        // 触发 RenderFlex overflow
        if (c.maxWidth < 50) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: valueStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(width: 4),
            if (ellipsis)
              Expanded(
                child: Text(
                  value,
                  style: valueStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              Text(value, style: valueStyle),
          ],
        );
      },
    );
  }
}

class _StatusSeparator extends StatelessWidget {
  const _StatusSeparator();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.outline,
    );
  }
}

// ============== Breadcrumb crumb ==============

class _Crumb extends StatefulWidget {
  final String label;
  final bool isSegment;
  final VoidCallback onTap;
  const _Crumb({
    required this.label,
    required this.onTap,
    this.isSegment = false,
  });

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: _hover ? scheme.primary.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            widget.label,
            style: theme.textTheme.mono?.copyWith(
              fontSize: 12,
              color: widget.isSegment
                  ? scheme.onSurface
                  : scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bucket crumb: 拆 icon + 名字 两个独立点击区域.
///
/// 之前整块点 = 弹 bucket picker, 没法"回 bucket 根目录" (只能点最前面的 "/"
/// 或者切到别的 bucket 再切回来). 拆开后:
/// - 点 icon → 弹 bucket picker (换 bucket)
/// - 点名字 → 回到当前 bucket 根目录 (清 prefix, 跟 Finder 行为一致)
class _BucketCrumb extends StatefulWidget {
  final String label;
  final VoidCallback onIconTap;
  final VoidCallback onLabelTap;
  const _BucketCrumb({
    required this.label,
    required this.onIconTap,
    required this.onLabelTap,
  });

  @override
  State<_BucketCrumb> createState() => _BucketCrumbState();
}

class _BucketCrumbState extends State<_BucketCrumb> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      // 整个单元 hover 一起高亮, 不区分 icon / label 子区域
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.only(left: 2, right: 6, top: 3, bottom: 3),
        decoration: BoxDecoration(
          color: _hover ? scheme.primary.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon: 独立点击区域 = 换 bucket
            Tooltip(
              message: '切换 bucket',
              child: GestureDetector(
                onTap: widget.onIconTap,
                // 加大 hit area 一点, icon 13px 直接点有点小
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.folder_outlined,
                    size: 13,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
            // Label: 独立点击区域 = 回到根
            Tooltip(
              message: '回到 bucket 根目录',
              child: GestureDetector(
                onTap: widget.onLabelTap,
                child: Text(
                  widget.label,
                  style: theme.textTheme.mono?.copyWith(
                    fontSize: 12,
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============== 各种 state 占位 ==============

/// AppBar 标题里可点击的链接式文本. 包装成 TextButton 自带 ripple, hover, tooltip.
/// 不再套 MouseRegion + Tooltip + GestureDetector 三层 (那套跟 AppBar title slot
/// 约束偶尔会触发 RenderBox needs-layout 异常).
class _AppBarLink extends StatelessWidget {
  final String label;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _AppBarLink({
    required this.label,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          fontSize: 18,
        ),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

/// 复制当前完整路径 (`bucket/prefix`) 到剪贴板. 只在有 bucket 时显示.
class _CopyPathButton extends StatelessWidget {
  final String? bucket;
  final String prefix;

  const _CopyPathButton({required this.bucket, required this.prefix});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (bucket == null) return const SizedBox.shrink();

    final path = prefix.isEmpty
        ? bucket!
        : '$bucket/${prefix.endsWith('/') ? prefix.substring(0, prefix.length - 1) : prefix}';

    return Tooltip(
      message: '复制路径: $path',
      child: IconButton(
        icon: const Icon(Icons.content_copy_outlined, size: 16),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: path));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check, size: 16, color: AppTheme.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已复制 $path',
                      style: theme.textTheme.mono?.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }
}

/// 进入 server 后还没选 bucket 的状态: 直接拉 bucket 列表, 内嵌可点.
/// 取代旧版"点右上角 folder icon 选 bucket"的提示, 因为 folder icon 已被改为新建文件夹.
class _NoBucketState extends ConsumerStatefulWidget {
  const _NoBucketState();

  @override
  ConsumerState<_NoBucketState> createState() => _NoBucketStateState();
}

class _NoBucketStateState extends ConsumerState<_NoBucketState> {
  late Future<List<String>> _future;
  Server? _lastServer;

  @override
  void initState() {
    super.initState();
    _lastServer = ref.read(activeServerProvider);
    _future = _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ref.read(activeServerProvider);
    // server 切换了 (例如从 AppBar 标题切了 server), 重新拉 buckets
    if (current?.id != _lastServer?.id) {
      _lastServer = current;
      setState(() {
        _future = _load();
      });
    }
  }

  Future<List<String>> _load() async {
    final client = ref.read(s3ClientProvider);
    if (client == null) return const [];
    return client.listBuckets();
  }

  void _pick(String bucket) {
    ref.read(currentBucketProvider.notifier).state = bucket;
    ref.read(currentPrefixProvider.notifier).state = '';
    ref.read(objectListProvider.notifier).refresh();
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _ScrollableCentered(
      child: FutureBuilder<List<String>>(
        future: _future,
        builder: (ctx, snap) {
          // 头部
          final header = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BUCKETS',
                style: theme.textTheme.eyebrow?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                snap.hasData && snap.data!.isNotEmpty
                    ? '选一个\nbucket.'
                    : '没有\nbucket.',
                style: theme.textTheme.hero,
              ),
              const SizedBox(height: 16),
              Text(
                '从下面选一个进入. 也可点 AppBar 的 server 名字切换其他 server.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );

          Widget list;
          if (snap.connectionState != ConnectionState.done) {
            list = const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          } else if (snap.hasError) {
            list = _BucketListError(
              error: snap.error.toString(),
              onRetry: _refresh,
            );
          } else if (snap.data == null || snap.data!.isEmpty) {
            list = _BucketListEmpty(
              onRefresh: _refresh,
              serverName: ref.read(activeServerProvider)?.name,
              endpoint: ref.read(s3ClientProvider)?.config.normalizedEndpoint,
            );
          } else {
            final buckets = snap.data!;
            // 用 Column 不用 ListView: ListView.separated(shrinkWrap: true) 内部
            // 是 RenderShrinkWrappingViewport, 不支持返回 intrinsic dimensions,
            // 跟外层 IntrinsicHeight 冲突. 改成 Column + children, bucket 数量
            // 一般 ≤ 50 个完全够用, 整个 _ScrollableCentered 已经包了 SingleChildScrollView
            // (外层 _NoBucketState 整页可滚).
            list = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < buckets.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  _BucketRow(
                    name: buckets[i],
                    onTap: () => _pick(buckets[i]),
                  ),
                ],
              ],
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, list],
          );
        },
      ),
    );
  }
}

class _BucketRow extends StatefulWidget {
  final String name;
  final VoidCallback onTap;
  const _BucketRow({required this.name, required this.onTap});

  @override
  State<_BucketRow> createState() => _BucketRowState();
}

class _BucketRowState extends State<_BucketRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: _hover ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hover ? scheme.primary : scheme.outline,
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(7),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: _hover ? scheme.primary : scheme.onSurface
                        .withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: theme.textTheme.mono?.copyWith(
                        fontSize: 13,
                        color: _hover ? scheme.primary : scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: _hover
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BucketListError extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _BucketListError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '加载 bucket 列表失败',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error,
            style: theme.textTheme.mono?.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _BucketListEmpty extends StatelessWidget {
  final VoidCallback onRefresh;
  final String? serverName;
  final String? endpoint;

  const _BucketListEmpty({
    required this.onRefresh,
    this.serverName,
    this.endpoint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '这个 server 下没有任何 bucket',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          if (endpoint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '已连接: ${serverName ?? "?"}  @  $endpoint',
                style: theme.textTheme.mono?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          Text(
            'ListBuckets 调用成功但返回 0 个. 可能原因: '
            '(1) 该账号真的没 bucket, '
            '(2) ListAllMyBuckets 权限被 IAM 策略拒绝 (403 静默吞掉?), '
            '(3) 响应 XML 格式跟标准 S3 不一致 (custom S3 实现).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新检查'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _openServerForm(context),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('编辑/测试连接'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openServerForm(BuildContext context) {
    // 通过 ServerListPage 入口来编辑, 找名字匹配的 server
    // 这里简化: pop 整个 browser, 回到 server list, 用户点 edit
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _EmptyDirState extends StatelessWidget {
  const _EmptyDirState();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _ScrollableCentered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EMPTY',
            style: theme.textTheme.eyebrow?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text('空空如也.', style: theme.textTheme.hero),
          const SizedBox(height: 16),
          Text(
            '点右下角 "上传" 按钮, 或者直接把文件拖进来.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _ScrollableCentered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ERROR',
            style: theme.textTheme.eyebrow?.copyWith(
              color: AppTheme.error,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '加载失败',
            style: theme.textTheme.hero?.copyWith(
              color: AppTheme.error,
              fontSize: 36,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            error,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

enum FileAction { select, delete, rename, move, download }

/// 内容垂直居中, 但内容比可用高度高时, 自动垂直滚动.
/// 解决窄高窗口下空态/错误态的 bottom overflow.
class _ScrollableCentered extends StatelessWidget {
  final Widget child;
  const _ScrollableCentered({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: IntrinsicHeight(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
