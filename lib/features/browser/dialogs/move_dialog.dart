import 'package:flutter/material.dart';

/// 移动到目标 prefix 对话框.
///
/// - [currentPrefix] 仅作默认占位
/// - 返回值自动补齐 trailing '/', 取消返回 null
Future<String?> showMoveDialog(BuildContext context, String currentPrefix) {
  final controller = TextEditingController(text: currentPrefix);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('移动到'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('目标路径 (相对 bucket 根, 结尾加 /)'),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'photos/2024/',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              final t = v.trim();
              Navigator.pop(
                context,
                t.isEmpty ? t : (t.endsWith('/') ? t : '$t/'),
              );
            },
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
          onPressed: () {
            final v = controller.text.trim();
            Navigator.pop(
              context,
              v.isEmpty ? v : (v.endsWith('/') ? v : '$v/'),
            );
          },
          child: const Text('移动'),
        ),
      ],
    ),
  );
}
