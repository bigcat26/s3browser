import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/s3_object.dart';
import '../../../providers/bucket_provider.dart';

/// 文件列表的列头. 仅在列表视图显示, 网格视图不显示.
///
/// 布局跟 [FileTile] 列表模式对齐, 但首列是 select-all checkbox,
/// 其余列点击可排序 (显示箭头指示当前排序).
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: scheme.outline, width: 1),
        ),
      ),
      child: Row(
        children: [
          // ---- 1: 全选 checkbox (3 态都点击: all → clear, partial/none → selectAll) ----
          SizedBox(
            width: 18,
            child: InkWell(
              onTap: allKeys.isEmpty
                  ? null
                  : () {
                      if (allSelected) {
                        sel.clear();
                      } else {
                        sel.selectAll(allKeys);
                      }
                    },
              child: allSelected
                  ? Icon(
                      Icons.check_box,
                      size: 16,
                      color: scheme.primary,
                    )
                  : partialSelected
                      ? Icon(
                          Icons.indeterminate_check_box,
                          size: 16,
                          color: scheme.primary,
                        )
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
          // ---- 2: 名称 (排序) ----
          Expanded(
            child: _HeaderCell(
              label: 'NAME',
              sortBy: SortBy.name,
              active: sortBy,
              asc: sortAsc,
              onTap: () => notifier.setSort(SortBy.name),
            ),
          ),
          // ---- 3: 修改时间 (排序) ----
          if (objects.any((o) => !o.isFolder && o.lastModified != null))
            SizedBox(
              width: 130,
              child: _HeaderCell(
                label: 'MODIFIED',
                sortBy: SortBy.date,
                active: sortBy,
                asc: sortAsc,
                onTap: () => notifier.setSort(SortBy.date),
                align: TextAlign.end,
              ),
            ),
          const SizedBox(width: 16),
          // ---- 4: 大小 (排序) ----
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
          const SizedBox(width: 12),
          // ---- 5: 操作列 (空头) ----
          const SizedBox(width: 32),
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
