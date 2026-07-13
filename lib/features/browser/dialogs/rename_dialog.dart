import 'package:flutter/material.dart';

/// 重命名对话框: 替换 [currentName] 的最后一段.
///
/// 返回新名字 (非空 + 跟 currentName 不同时), 取消或同名校验失败返回 null.
Future<String?> showRenameDialog(BuildContext context, String currentName) {
  final controller = TextEditingController(text: currentName);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) {
          final t = v.trim();
          if (t.isNotEmpty && t != currentName) {
            Navigator.pop(context, t);
          } else {
            Navigator.pop(context);
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isEmpty || v == currentName) {
              Navigator.pop(context);
            } else {
              Navigator.pop(context, v);
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
