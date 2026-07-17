// 本地 Downloads 视图.
//
// 用户在 BrowserPage 顶部 AppBar 点 "本地下载" 图标 → push 进来.
// 功能:
//   1. 列出 [getLocalDownloadsDir] 下的所有文件 (按修改时间倒序, 最新的在前)
//   2. 单击 (非选择模式): 调 open_file 用系统 "打开方式" 弹窗
//   3. 长按 / 三点菜单: 删除 / 复制路径 / 分享 (TODO: 分享)
//   4. 选择模式: 长按进入, 行首出现 Checkbox; AppBar 提供 全选 / 取消 /
//      删除(N) / 退出. 批量删除走二次确认, 统一刷新 + 汇总 snackbar.
//   5. 下拉刷新: 重新读盘
//   6. 空态: "还没有下载过文件" + 返回按钮
//
// 设计上跟 BrowserPage 同构 (ListView + IconButton row), 让用户肌肉记忆一致.
// 状态从异步 ObjectListProvider 换成同步 (直接读本地目录), 没有 loading
// 状态 (本地 IO 快到不需要 spinner).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;

import '../../core/format_bytes.dart';
import '../../core/local_files.dart';

class LocalDownloadsPage extends StatefulWidget {
  const LocalDownloadsPage({super.key});

  @override
  State<LocalDownloadsPage> createState() => _LocalDownloadsPageState();
}

class _LocalDownloadsPageState extends State<LocalDownloadsPage> {
  // 每次进入 / 下拉刷新都重读, 避免跟下载流程的状态不一致
  // (用户刚下完一个文件, 必须能立刻看到).
  List<FileSystemEntity> _files = const [];
  bool _loading = true;
  Object? _error;

  // 选择模式: 进入后行首显示 Checkbox, 点击切换选中.
  bool _selectionMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dir = await getLocalDownloadsDir();
      // 用 listSync() 不用 dir.list().toList(), 原因:
      // 1. 下载目录一般 < 1000 文件, listSync IO < 10ms, 不会卡 UI
      // 2. dir.list() 是 Stream, 在 widget test 里要 tester.runAsync 才能
      //    resolve, 用 sync 版测试也容易
      // 3. Flutter test framework 对真实 Stream / 异步 IO 处理不友好
      //    (tester.pump 走 fake-async, 但 dart:io 的 event 不走 fake-async).
      final entries = dir.listSync();
      // 只列文件 (跳过子目录, 防止 "Downloads 里有 Downloads" 这种 edge case)
      // 按修改时间倒序, 最新的下载最上面
      final onlyFiles = entries.whereType<File>().toList()
        ..sort((a, b) {
          final am = a.statSync().modified;
          final bm = b.statSync().modified;
          return bm.compareTo(am);
        });
      if (mounted) {
        // 刷新后清掉已不存在的选中项, 避免悬空 key.
        final livePaths = onlyFiles.map((f) => f.path).toSet();
        _selected.removeWhere((path) => !livePaths.contains(path));
        setState(() {
          _files = onlyFiles;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
      // 全取消时自动退出选择模式, 回到浏览态.
      if (_selected.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _files.length) {
        _selected.clear();
        _selectionMode = false;
      } else {
        _selected.addAll(_files.map((f) => f.path));
      }
    });
  }

  Future<void> _openFile(File file) async {
    // open_file: Android Intent.ACTION_VIEW, iOS UIDocumentInteractionController.
    // 返回 OpenResult (type + message), 不是 Exception. 失败时 type 是
    // fileType / noAppToOpen 等, message 给人看.
    final result = await OpenFile.open(file.path);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法打开: ${result.message}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _deleteFile(File file) async {
    // 提前抓 messenger + errorColor, 避免 await 后 use_build_context_synchronously
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await file.delete();
      messenger.showSnackBar(
        SnackBar(content: Text('已删除: ${p.basename(file.path)}')),
      );
      _refresh();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('删除失败: $e'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _copyPath(File file) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: file.path));
    messenger.showSnackBar(
      SnackBar(
        content: Text('已复制路径: ${file.path}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmAndDelete(File file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('将删除 "${p.basename(file.path)}", 此操作不可撤销.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteFile(file);
  }

  /// 批量删除: 二次确认后逐个删, 统一刷新 + 汇总 snackbar.
  Future<void> _confirmAndDeleteSelected() async {
    final count = _selected.length;
    if (count == 0) return;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('将删除选中的 $count 个文件, 此操作不可撤销.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    int success = 0;
    int failed = 0;
    for (final path in List<String>.from(_selected)) {
      try {
        File(path).deleteSync();
        success++;
      } catch (e) {
        failed++;
      }
    }
    if (!mounted) return;
    _exitSelectionMode();
    if (failed == 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('已删除 $success 个文件')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('已删除 $success 个, $failed 个失败'),
          backgroundColor: errorColor,
        ),
      );
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 选择模式下不显示返回箭头的默认 pop 行为由 leading 控制.
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: '退出选择',
                onPressed: _exitSelectionMode,
              )
            : null,
        title: _selectionMode
            ? Text('已选 ${_selected.length} / ${_files.length}')
            : const Text('本地下载'),
        actions: _buildAppBarActions(),
      ),
      body: _buildBody(),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (_selectionMode) {
      final allSelected = _selected.length == _files.length && _files.isNotEmpty;
      return [
        IconButton(
          icon: allSelected
              ? const Icon(Icons.deselect)
              : const Icon(Icons.select_all),
          tooltip: allSelected ? '取消全选' : '全选',
          onPressed: _toggleSelectAll,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除选中',
          onPressed: _selected.isEmpty ? null : _confirmAndDeleteSelected,
        ),
      ];
    }
    return [
      IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: '刷新',
        onPressed: _refresh,
      ),
    ];
  }

  Widget _buildBody() {
    if (_loading && _files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                '无法访问 Downloads 文件夹',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '$_error',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open_outlined,
                size: 64,
                color: Theme.of(context).hintColor,
              ),
              const SizedBox(height: 12),
              Text(
                '还没有下载过文件',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '在 S3 浏览器里点文件菜单 → 下载, 文件会出现在这里.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _files.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (_, i) => _FileRow(
          file: _files[i] as File,
          selectionMode: _selectionMode,
          selected: _selected.contains(_files[i].path),
          onTap: () {
            if (_selectionMode) {
              _toggleSelect(_files[i].path);
            } else {
              _openFile(_files[i] as File);
            }
          },
          onLongPress: () {
            if (!_selectionMode) {
              _enterSelectionMode();
              _toggleSelect(_files[i].path);
            } else {
              _toggleSelect(_files[i].path);
            }
          },
          onDelete: () => _confirmAndDelete(_files[i] as File),
          onCopyPath: () => _copyPath(_files[i] as File),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final File file;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onCopyPath;

  const _FileRow({
    required this.file,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onCopyPath,
  });

  @override
  Widget build(BuildContext context) {
    final stat = file.statSync();
    final name = p.basename(file.path);
    return ListTile(
      leading: selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => onTap(),
            )
          : _fileIcon(name),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${formatBytesShort(stat.size)}  ·  ${_formatTime(stat.modified)}',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).hintColor,
        ),
      ),
      trailing: selectionMode
          ? null
          : PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: '更多',
              onSelected: (v) {
                switch (v) {
                  case 'open':
                    onTap();
                    break;
                  case 'copy':
                    onCopyPath();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('打开')),
                PopupMenuItem(value: 'copy', child: Text('复制路径')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  /// 按扩展名选 icon. 没匹配上走 generic insert_drive_file.
  Widget _fileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    IconData icon;
    Color? color;
    switch (ext) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
      case '.svg':
      case '.bmp':
        icon = Icons.image_outlined;
        color = Colors.purple;
        break;
      case '.mp4':
      case '.mov':
      case '.avi':
      case '.mkv':
        icon = Icons.movie_outlined;
        color = Colors.red;
        break;
      case '.mp3':
      case '.wav':
      case '.flac':
      case '.aac':
        icon = Icons.audiotrack_outlined;
        color = Colors.orange;
        break;
      case '.pdf':
        icon = Icons.picture_as_pdf_outlined;
        color = Colors.red;
        break;
      case '.zip':
      case '.tar':
      case '.gz':
      case '.7z':
      case '.rar':
        icon = Icons.archive_outlined;
        color = Colors.brown;
        break;
      case '.txt':
      case '.md':
        icon = Icons.article_outlined;
        color = Colors.blueGrey;
        break;
      case '.doc':
      case '.docx':
        icon = Icons.description_outlined;
        color = Colors.blue;
        break;
      case '.xls':
      case '.xlsx':
        icon = Icons.table_chart_outlined;
        color = Colors.green;
        break;
      case '.apk':
        icon = Icons.android_outlined;
        color = Colors.green;
        break;
      default:
        icon = Icons.insert_drive_file_outlined;
    }
    return Icon(icon, color: color);
  }

  String _formatTime(DateTime t) {
    // 简化: 跟本地时区 (stat.modified 是 UTC), 显示 "今天 HH:mm" 或
    // "YYYY-MM-DD HH:mm". 短就行, 不调 intl (避免再加依赖).
    final local = t.toLocal();
    final now = DateTime.now();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return '今天 $hh:$mm';
    }
    final yyyy = local.year.toString();
    final mo = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '$yyyy-$mo-$dd $hh:$mm';
  }
}
