import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/s3_object.dart';
import '../../../providers/bucket_provider.dart';
import '../browser_page.dart' show FileAction;

/// 单个文件/文件夹行 (列表 / 网格两种模式).
///
/// 列表模式:
///   - 首列固定 checkbox (始终显示, 不依赖 select mode)
///   - 后跟 icon / name / date / size / more
///   - 点击行: navigate (folder) 或 download (file)
///   - 点击 checkbox: toggle selection
///   - 点击 more: 弹出操作菜单 (rename / move / download / delete)
///   - 行支持 hover / 选中时左侧出现 2px 橙色 accent border
class FileTile extends ConsumerStatefulWidget {
  final S3Object object;
  final bool isGrid;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(FileAction) onAction;

  const FileTile({
    super.key,
    required this.object,
    required this.isGrid,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
  });

  @override
  ConsumerState<FileTile> createState() => _FileTileState();
}

class _FileTileState extends ConsumerState<FileTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected =
        ref.watch(selectionProvider).contains(widget.object.key);
    final icon = _iconFor(widget.object);

    if (widget.isGrid) {
      return _buildGrid(context, icon, selected);
    }
    return _buildList(context, icon, selected);
  }

  // ---- 列表模式 (主用) ----
  Widget _buildList(BuildContext context, IconData icon, bool selected) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final obj = widget.object;
    final showAccent = _hover || selected;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        child: InkWell(
          // 整行可点. parent (_handleTap) 根据当前选择态决定行为:
          //   - 无选择 → navigate (folder) / download (file)
          //   - 有选择 → toggle 该行选择 (不进 folder)
          // checkbox / more button 自己有 onTap, 手势系统自动让 child 优先,
          // 不会被这里重复触发.
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTap: () => _showContextMenu(context),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  width: 2,
                  color: showAccent ? scheme.primary : Colors.transparent,
                ),
                bottom: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
            // LayoutBuilder 拿实际可用宽, 窄屏 (< 560) 把 MODIFIED 列从 130px
            // 砍到 60px + 格式从 "YYYY-MM-DD" 变 "MM-DD", 仍然显示. 之前
            // 窄屏直接砍掉整列, 用户手机上看不到修改时间 (反馈 "缺少了修改
            // 时间列"). 文件夹 / lastModified 为空 → 显示 "—" 占位, 列对齐
            // 不抖.
            child: LayoutBuilder(
              builder: (ctx, c) {
                final narrow = c.maxWidth < 560;
                final dateWidth = narrow ? 60.0 : 130.0;
                return Row(
                  children: [
                    // ---- 1: 选择 checkbox (永远显示) ----
                    SizedBox(
                      width: 18,
                      child: InkWell(
                        onTap: () => ref
                            .read(selectionProvider.notifier)
                            .toggle(obj.key),
                        borderRadius: BorderRadius.circular(2),
                        child: Padding(
                          padding: const EdgeInsets.all(1),
                          child: Icon(
                            selected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 16,
                            color: selected
                                ? scheme.primary
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ---- 2: 图标 ----
                    Icon(icon, size: 16, color: _iconColor(context, obj, selected)),
                    const SizedBox(width: 12),
                    // ---- 3: 文件名 (横向 scroll, 长名字能左右划看全) ----
                    // 用 SingleChildScrollView(horizontal) 套 Text, 自然宽
                    // 渲染; 容器宽 < 自然宽时, 横向拖动看尾部. 不影响 tap
                    // (SingleChildScrollView 不吃 tap, 只吃 drag) 也不吃
                    // 竖向滚动 (垂直 drag 透传给外层 ListView).
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        // drag 结束后不会"反弹"回起点, 保持拖到的位置
                        physics: const ClampingScrollPhysics(),
                        // 不要这个, 默认就吃 tap, 单击穿透不到行 InkWell
                        child: Text(
                          obj.name,
                          // 不带 ellipsis: scroll 没滚到底时尾部看不到, 但
                          // 用户能划, 不强制截断
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: obj.isFolder
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    // ---- 4: 修改时间 (永远显示, 窄屏压缩; folder / null → "—") ----
                    SizedBox(
                      width: dateWidth,
                      child: Text(
                        _formatDate(obj.lastModified, compact: narrow),
                        style: theme.textTheme.mono?.copyWith(
                          color: (obj.isFolder || obj.lastModified == null)
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3)
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // ---- 5: 大小 (等宽右对齐) ----
                    SizedBox(
                      width: narrow ? 60 : 72,
                      child: Text(
                        obj.isFolder ? '—' : obj.sizeHuman,
                        style: theme.textTheme.mono?.copyWith(
                          color: obj.isFolder
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3)
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ---- 6: 操作 ----
                    // 一直显示, 不依赖 hover. 之前 opacity = _hover ? 1 : 0,
                    // 手机没 hover 概念, 按钮永远看不见, 重命名/移动/删除等都
                    // 触发不了 (反馈 "少了重命名功能"). 改成 0.35 → 1.0 两档,
                    // 桌面 hover 上去有反馈, 手机端始终可见.
                    SizedBox(
                      width: 32,
                      child: InkWell(
                        onTap: () => _showContextMenu(context),
                        borderRadius: BorderRadius.circular(4),
                        child: Tooltip(
                          message: '操作',
                          child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 120),
                              opacity: _hover ? 1.0 : 0.35,
                              child: const Icon(Icons.more_horiz, size: 18),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ---- 网格模式 ----
  Widget _buildGrid(BuildContext context, IconData icon, bool selected) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final obj = widget.object;
    return Card(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: () => _showContextMenu(context),
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: _iconColor(context, obj, selected)),
              const SizedBox(height: 8),
              Text(
                obj.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              if (!obj.isFolder) ...[
                const SizedBox(height: 2),
                Text(
                  obj.sizeHuman,
                  style: theme.textTheme.mono?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _iconColor(BuildContext context, S3Object obj, bool selected) {
    if (obj.isFolder) {
      return Theme.of(context).colorScheme.primary;
    }
    if (selected) return Theme.of(context).colorScheme.primary;
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
  }

  // ---- 辅助 ----
  IconData _iconFor(S3Object obj) {
    if (obj.isFolder) return Icons.folder_outlined;
    final name = obj.name.toLowerCase();
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.avi') ||
        name.endsWith('.mkv')) {
      return Icons.movie_outlined;
    }
    if (name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.flac') ||
        name.endsWith('.aac')) {
      return Icons.audio_file_outlined;
    }
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (name.endsWith('.zip') ||
        name.endsWith('.tar') ||
        name.endsWith('.gz') ||
        name.endsWith('.7z') ||
        name.endsWith('.rar')) {
      return Icons.archive_outlined;
    }
    if (name.endsWith('.txt') || name.endsWith('.md')) {
      return Icons.description_outlined;
    }
    if (name.endsWith('.json') ||
        name.endsWith('.xml') ||
        name.endsWith('.yaml') ||
        name.endsWith('.yml') ||
        name.endsWith('.csv')) {
      return Icons.data_object;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _formatDate(DateTime? d, {bool compact = false}) {
    // compact = true 用 "MM-DD" (5 字符), 适合窄屏 60px 列
    // compact = false 用 "YYYY-MM-DD" (10 字符), 适合宽屏 130px 列
    // 传 null 或 folder (由 caller 决定传不传) → 返回 "—"
    if (d == null) return '—';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    if (compact) return '$m-$day';
    final y = d.year.toString().padLeft(4, '0');
    return '$y-$m-$day';
  }

  void _showContextMenu(BuildContext context) async {
    final picked = await showMenu<FileAction>(
      context: context,
      position: RelativeRect.fromLTRB(200, 200, 200, 200),
      items: const [
        // "多选" 已移到行首 checkbox, 不再放菜单
        PopupMenuItem(value: FileAction.rename, child: Text('重命名')),
        PopupMenuItem(value: FileAction.move, child: Text('移动')),
        PopupMenuItem(value: FileAction.download, child: Text('下载')),
        PopupMenuItem(value: FileAction.delete, child: Text('删除')),
        PopupMenuDivider(),
        // 复制操作放最后, 用 divider 跟 destructive 操作分开
        PopupMenuItem(
          value: FileAction.copyName,
          child: Row(
            children: [
              Icon(Icons.copy_outlined, size: 16),
              SizedBox(width: 10),
              Text('复制文件名'),
            ],
          ),
        ),
        PopupMenuItem(
          value: FileAction.copyPath,
          child: Row(
            children: [
              Icon(Icons.link, size: 16),
              SizedBox(width: 10),
              Text('复制完整路径'),
            ],
          ),
        ),
      ],
    );
    if (picked != null) widget.onAction(picked);
  }
}
