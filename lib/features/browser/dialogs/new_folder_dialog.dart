import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/active_server_provider.dart';
import '../../../providers/bucket_provider.dart';

/// 弹窗输入新文件夹名, 在 [prefix] 下创建一个 0 字节的 `name/` 对象作为 marker.
/// S3 没有真正的 folder, 这是 AWS 推荐做法.
///
/// 返回: 创建成功的文件夹 key (含尾 `/`), 用户取消或失败时 null.
class NewFolderDialog extends ConsumerStatefulWidget {
  final String prefix;
  const NewFolderDialog({super.key, required this.prefix});

  static Future<String?> show(BuildContext context, String prefix) {
    return showDialog<String>(
      context: context,
      builder: (_) => NewFolderDialog(prefix: prefix),
    );
  }

  @override
  ConsumerState<NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends ConsumerState<NewFolderDialog> {
  final _ctrl = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_form.currentState!.validate()) return;
    final name = _ctrl.text.trim();
    final key = '${widget.prefix}$name/';

    final client = ref.read(s3ClientProvider);
    final bucket = ref.read(currentBucketProvider);
    if (client == null || bucket == null) return;

    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await client.uploadBytes(
        bucket: bucket,
        key: key,
        bytes: Uint8List(0),
      );
      if (mounted) {
        ref.read(objectListProvider.notifier).refresh();
        Navigator.of(context).pop(key);
      }
    } catch (e) {
      setState(() {
        _err = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.create_new_folder_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          const Text('新建文件夹'),
        ],
      ),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.prefix.isEmpty
                  ? '在 根目录 下创建'
                  : '在 ${widget.prefix} 下创建',
              style: theme.textTheme.mono?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ctrl,
              autofocus: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '文件夹名',
                hintText: 'my-folder',
                prefixIcon: Icon(Icons.folder_outlined, size: 18),
              ),
              style: theme.textTheme.mono,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return '请输入文件夹名';
                if (s.contains('/') || s.contains('\\')) {
                  return '不能包含 / 或 \\';
                }
                if (s.startsWith('.')) return '不能以 . 开头';
                return null;
              },
            ),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE07A5F).withValues(alpha: 0.10),
                  border: Border.all(
                    color: const Color(0xFFE07A5F).withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _err!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFE07A5F),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : const Icon(Icons.add, size: 16),
          label: const Text('创建'),
        ),
      ],
    );
  }
}
