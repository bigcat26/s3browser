import 'package:desktop_drop/desktop_drop.dart' as dd;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 跨平台拖拽包装器.
///
/// - 桌面端 (macOS/Windows/Linux): 包装 [dd.DropTarget]
/// - Web / 移动端: 直接返回 [child]
///
/// 注意: 之所以用 `as dd` 别名, 是因为 `package:desktop_drop` 内部也有一个 `DropTarget` 类,
/// 会跟外部自定义的 `DropTarget` 冲突. 别名后只通过 `dd.DropTarget` 引用, 避免歧义.
class DropTarget extends StatelessWidget {
  final Widget child;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final void Function(dd.DropDoneDetails) onDragDone;

  const DropTarget({
    super.key,
    required this.child,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDragDone,
  });

  @override
  Widget build(BuildContext context) {
    // Web / iOS / Android: 拖拽协议不同, 直接 pass-through
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      return child;
    }
    return dd.DropTarget(
      onDragEntered: (_) => onDragEntered(),
      onDragExited: (_) => onDragExited(),
      onDragDone: onDragDone,
      child: child,
    );
  }
}
