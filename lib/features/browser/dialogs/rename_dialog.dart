import 'package:flutter/material.dart';

/// 重命名对话框: 替换 [currentName] 的最后一段.
///
/// 返回新名字 (非空 + 跟 currentName 不同时), 取消或同名校验失败返回 null.
Future<String?> showRenameDialog(BuildContext context, String currentName) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(currentName: currentName),
  );
}

/// Stateful 而不是函数式 builder, 是为了拿到 [FocusNode] 的 lifecycle:
/// `autofocus: true` 在 release AOT + 部分 Android 版本上不可靠 (软键盘不弹),
/// 走 addPostFrameCallback + requestFocus 强制唤起 IME. 三个 dialog
/// 统一这套机制, 行为一致好排查.
class _RenameDialog extends StatefulWidget {
  final String currentName;
  const _RenameDialog({required this.currentName});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentName);
    // 先设好选区 (controller 初始状态), 再在焦点稳定后补设一次, 避免
    // requestFocus() 在某些平台把已有选区清空/全选覆盖掉.
    _applyBasenameSelection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      // requestFocus 的选区处理是同步的, microtask 在它之后跑 → 我们的设值生效.
      Future.microtask(_applyBasenameSelection);
    });
  }

  /// 默认只选中"文件名主体", 不选中扩展名: 用户改文件名时通常只想改名字,
  /// 后缀保留 (OS 文件管理器标准行为). 想改后缀自己把选区拉过去.
  /// 隐藏文件 (.gitignore, 前导点) / 文件夹 (尾随 '/') / 无扩展名 → 整段选中.
  void _applyBasenameSelection() {
    final name = widget.currentName;
    final dot = name.lastIndexOf('.');
    final hasExt = dot > 0 && dot < name.length - 1 && !name.endsWith('/');
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: hasExt ? dot : name.length,
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty || v == widget.currentName) {
      Navigator.pop(context);
    } else {
      Navigator.pop(context, v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        controller: _ctrl,
        focusNode: _focus,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
