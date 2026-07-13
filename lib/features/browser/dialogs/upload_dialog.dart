import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/active_server_provider.dart';
import '../../../providers/bucket_provider.dart';

/// 上传底部弹窗: 选择文件 / 新建文件夹 (S3 通过空 key marker 实现).
class UploadSheet extends ConsumerStatefulWidget {
  final String prefix;
  const UploadSheet({super.key, required this.prefix});

  @override
  ConsumerState<UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends ConsumerState<UploadSheet> {
  bool _busy = false;
  final _newFolderCtrl = TextEditingController();

  @override
  void dispose() {
    _newFolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null) return;
      final client = ref.read(s3ClientProvider);
      final bucket = ref.read(currentBucketProvider);
      if (client == null || bucket == null) return;

      var ok = 0;
      var fail = 0;
      for (final f in result.files) {
        if (f.path == null) continue;
        final key = '${widget.prefix}${f.name}';
        try {
          await client.uploadFile(
            bucket: bucket,
            key: key,
            localPath: f.path!,
          );
          ok++;
        } catch (e) {
          fail++;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('上传 ${f.name} 失败: $e')),
            );
          }
        }
      }
      if (mounted) {
        ref.read(objectListProvider.notifier).refresh();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传: 成功 $ok, 失败 $fail')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createFolder() async {
    final name = _newFolderCtrl.text.trim();
    if (name.isEmpty) return;
    if (name.contains('/') || name.contains('\\')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件夹名不能包含 /')),
      );
      return;
    }

    final client = ref.read(s3ClientProvider);
    final bucket = ref.read(currentBucketProvider);
    if (client == null || bucket == null) return;
    final key = '${widget.prefix}$name/';

    setState(() => _busy = true);
    try {
      // S3 没有真正的 folder, 上传一个 0 字节的 object 作为 marker
      await client.uploadBytes(
        bucket: bucket,
        key: key,
        bytes: Uint8List(0),
      );
      if (mounted) {
        ref.read(objectListProvider.notifier).refresh();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '上传到 ${widget.prefix.isEmpty ? "根目录" : widget.prefix}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('选择文件上传'),
              subtitle: const Text('支持多选, 大于 5MB 自动分片'),
              onTap: _busy ? null : _pickFiles,
              trailing: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
            ),
            const Divider(),
            const Text('新建文件夹 (S3 通过空 key marker 实现)'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newFolderCtrl,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      hintText: 'my-folder',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _createFolder,
                  child: const Text('创建'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
