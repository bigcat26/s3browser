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
    // 渲染完下一帧再 requestFocus, 配合 selectAll 让用户直接覆盖
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      // 全选当前名, 移动端用户点 "重命名" 通常是想改, 不是再加字
      _ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.currentName.length,
      );
    });
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
