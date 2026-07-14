import 'package:flutter/material.dart';

/// 移动到目标 prefix 对话框.
///
/// - [currentPrefix] 仅作默认占位
/// - 返回值自动补齐 trailing '/', 取消返回 null
Future<String?> showMoveDialog(BuildContext context, String currentPrefix) {
  return showDialog<String>(
    context: context,
    builder: (_) => _MoveDialog(currentPrefix: currentPrefix),
  );
}

/// 显式 FocusNode + addPostFrameCallback 强制唤起 IME, 跟另外两个
/// dialog 一致. 见 rename_dialog.dart 注释.
class _MoveDialog extends StatefulWidget {
  final String currentPrefix;
  const _MoveDialog({required this.currentPrefix});

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentPrefix);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String _normalize(String v) {
    final t = v.trim();
    return t.isEmpty ? t : (t.endsWith('/') ? t : '$t/');
  }

  void _submit() {
    Navigator.pop(context, _normalize(_ctrl.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('移动到'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('目标路径 (相对 bucket 根, 结尾加 /)'),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            decoration: const InputDecoration(
              hintText: 'photos/2024/',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          const Text(
            '例: photos/ → 移动到 photos/ 子目录\n'
            '空 = 移动到根目录 (慎用, 会跟现有 key 重名)',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('移动'),
        ),
      ],
    );
  }
}
