import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 选中时显示在底部的批量操作栏. 顶替普通状态栏的位置 (跟 status bar 切换).
///
/// 布局: 左侧 badge + 文字 (允许 flex 缩), Spacer 推到右边 actions.
/// 不再套 LayoutBuilder + ConstrainedBox + IntrinsicHeight + 横向 scroll
/// 模式 (Spacer 在 unbounded maxWidth 容器会撑无限, IntrinsicHeight 算
/// intrinsic width 失败 → 整条 layout 链 NEEDS-LAYOUT).
class BatchActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onDownload;

  const BatchActionBar({
    super.key,
    required this.selectedCount,
    required this.onClear,
    required this.onDelete,
    required this.onMove,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        border: Border(
          top: BorderSide(color: scheme.primary, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '$selectedCount 选',
                  style: theme.textTheme.eyebrow?.copyWith(
                    color: scheme.onPrimary,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '已选 $selectedCount 项',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              _BatchAction(
                icon: Icons.download_outlined,
                label: '下载',
                onPressed: selectedCount > 0 ? onDownload : null,
              ),
              const SizedBox(width: 2),
              _BatchAction(
                icon: Icons.drive_file_move_outlined,
                label: '移动',
                onPressed: selectedCount > 0 ? onMove : null,
              ),
              const SizedBox(width: 2),
              _BatchAction(
                icon: Icons.delete_outline,
                label: '删除',
                onPressed: selectedCount > 0 ? onDelete : null,
                danger: true,
              ),
              const SizedBox(width: 2),
              _BatchAction(
                icon: Icons.close,
                label: '取消',
                onPressed: onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  const _BatchAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger
        ? AppTheme.error
        : theme.colorScheme.onSurface.withValues(alpha: 0.8);
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon,
          size: 16,
          color: onPressed == null ? color.withValues(alpha: 0.3) : color),
      label: Text(
        label,
        style: TextStyle(
          color: onPressed == null ? color.withValues(alpha: 0.3) : color,
          fontSize: 13,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
