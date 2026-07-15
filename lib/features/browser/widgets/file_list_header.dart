import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/s3_object.dart';
import '../../../providers/bucket_provider.dart';

/// 文件列表的列头. 仅在列表视图显示, 网格视图不显示.
///
/// 布局跟 [FileTile] 列表模式的两行对齐:
///   - 第一行: 全选 checkbox + NAME (排序)
///   - 第二行: MODIFIED (左, 排序) ... SIZE (右, 排序)
/// 两行都可点击排序 (显示箭头指示当前排序). 把列头拆成两行是为了跟正文
/// 副标题行 (修改时间左 / 大小右) 的左右位置对齐, 视觉上一一对应.
class FileListHeader extends ConsumerWidget {
  final List<S3Object> objects;

  const FileListHeader({super.key, required this.objects});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notifier = ref.read(objectListProvider.notifier);
    final sortBy = notifier.sortBy;
    final sortAsc = notifier.sortAsc;
    final selected = ref.watch(selectionProvider);
    final allKeys = objects.map((o) => o.key).toList();
    final allSelected =
        allKeys.isNotEmpty && allKeys.every((k) => selected.contains(k));
    final partialSelected =
        !allSelected && allKeys.any((k) => selected.contains(k));
    final sel = ref.read(selectionProvider.notifier);

    // 行首缩进: checkbox(18) + gap(12) + icon(16) + gap(12) = 58,
    // 让第二行的 MODIFIED 跟正文 name 左对齐.
    const leadIndent = 58.0;
    // 行尾缩进: gap(12) + actions(32) = 44,
    // 让第二行的 SIZE 跟正文 size 右对齐.
    const tailIndent = 44.0;

    final selectAll = allKeys.isEmpty
        ? null
        : () {
            if (allSelected) {
              sel.clear();
            } else {
              sel.selectAll(allKeys);
            }
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: scheme.outline, width: 1),
        ),
      ),
      child: Column(
        children: [
          // ---- 第一行: 全选 + NAME ----
          Row(
            children: [
              SizedBox(
                width: 18,
                child: InkWell(
                  onTap: selectAll,
                  child: allSelected
                      ? Icon(Icons.check_box, size: 16, color: scheme.primary)
                      : partialSelected
                          ? Icon(Icons.indeterminate_check_box,
                              size: 16, color: scheme.primary)
                          : Icon(
                              Icons.check_box_outline_blank,
                              size: 16,
                              color: allKeys.isEmpty
                                  ? scheme.onSurface.withValues(alpha: 0.2)
                                  : scheme.onSurface.withValues(alpha: 0.5),
                            ),
                ),
              ),
              const SizedBox(width: 12),
              // 图标列 (空, 跟 body 对齐)
              const SizedBox(width: 16),
              const SizedBox(width: 12),
              Expanded(
                child: _HeaderCell(
                  label: 'NAME',
                  sortBy: SortBy.name,
                  active: sortBy,
                  asc: sortAsc,
                  onTap: () => notifier.setSort(SortBy.name),
                ),
              ),
              // 操作列 (空头, 跟 body 对齐)
              const SizedBox(width: 32),
            ],
          ),
          const SizedBox(height: 2),
          // ---- 第二行: MODIFIED (左) ... SIZE (右) ----
          Row(
            children: [
              const SizedBox(width: leadIndent),
              Expanded(
                child: _HeaderCell(
                  label: 'MODIFIED',
                  sortBy: SortBy.date,
                  active: sortBy,
                  asc: sortAsc,
                  onTap: () => notifier.setSort(SortBy.date),
                  align: TextAlign.start,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: _HeaderCell(
                  label: 'SIZE',
                  sortBy: SortBy.size,
                  active: sortBy,
                  asc: sortAsc,
                  onTap: () => notifier.setSort(SortBy.size),
                  align: TextAlign.end,
                ),
              ),
              const SizedBox(width: tailIndent),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final SortBy sortBy;
  final SortBy active;
  final bool asc;
  final VoidCallback onTap;
  final TextAlign align;

  const _HeaderCell({
    required this.label,
    required this.sortBy,
    required this.active,
    required this.asc,
    required this.onTap,
    this.align = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = sortBy == active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: align == TextAlign.end
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.eyebrow?.copyWith(
                  fontSize: 10,
                  color: isActive
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 4),
                Icon(
                  asc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 10,
                  color: scheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
