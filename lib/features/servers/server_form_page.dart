import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/s3_config.dart';
import '../../core/config/server_store.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/server.dart';
import '../../data/s3_client.dart';
import '../../providers/active_server_provider.dart';
import '../../providers/server_list_provider.dart';

/// 新增 / 编辑 server 的表单. [existing]=null = 新增, 非空 = 编辑.
class ServerFormPage extends ConsumerStatefulWidget {
  final Server? existing;

  const ServerFormPage({super.key, this.existing});

  @override
  ConsumerState<ServerFormPage> createState() => _ServerFormPageState();
}

class _ServerFormPageState extends ConsumerState<ServerFormPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _endpoint = TextEditingController();
  final _region = TextEditingController(text: 'us-east-1');
  final _accessKey = TextEditingController();
  final _secretKey = TextEditingController();
  final _defaultBucket = TextEditingController();
  bool _pathStyle = true;
  bool _secure = true;
  bool _obscureSecret = true;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;
  String? _nameError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _endpoint.text = e.config.endpoint;
      _region.text = e.config.region;
      _accessKey.text = e.config.accessKey;
      _secretKey.text = e.config.secretKey;
      _defaultBucket.text = e.config.defaultBucket ?? '';
      _pathStyle = e.config.pathStyle;
      _secure = e.config.secure;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _region.dispose();
    _accessKey.dispose();
    _secretKey.dispose();
    _defaultBucket.dispose();
    super.dispose();
  }

  S3Config _buildConfig() => S3Config(
        endpoint: _endpoint.text.trim(),
        region: _region.text.trim().isEmpty ? 'us-east-1' : _region.text.trim(),
        accessKey: _accessKey.text.trim(),
        secretKey: _secretKey.text.trim(),
        defaultBucket: _defaultBucket.text.trim().isEmpty
            ? null
            : _defaultBucket.text.trim(),
        pathStyle: _pathStyle,
        secure: _secure,
      );

  void _onEndpointChanged() {
    final newCfg = _buildConfig();
    final newDefault = ServerStore().defaultName(newCfg);
    final currentName = _name.text.trim();
    if (currentName.isEmpty || _isLikelyAutoName(currentName)) {
      _name.text = newDefault;
    }
    setState(() => _nameError = null);
  }

  bool _isLikelyAutoName(String name) {
    if (name == '未命名') return true;
    if (_endpoint.text.trim().isEmpty) return false;
    final host = ServerStore().defaultName(_buildConfig());
    return name == host;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '请输入服务器名字');
      return;
    }
    final list = ref.read(serverListProvider).value ?? const <Server>[];
    final dup = list.any((s) =>
        s.name == name && (_isEdit ? s.id != widget.existing!.id : true));
    if (dup) {
      setState(() => _nameError = '已存在同名服务器: $name');
      return;
    }
    setState(() => _saving = true);
    try {
      final cfg = _buildConfig();
      if (_isEdit) {
        final updated = widget.existing!.copyWith(name: name, config: cfg);
        await ref.read(serverListProvider.notifier).update(updated);
        final active = ref.read(activeServerProvider);
        if (active != null && active.id == updated.id) {
          ref.read(activeServerProvider.notifier).set(updated);
        }
        if (mounted) Navigator.of(context).pop(updated);
      } else {
        final created = Server(
          id: ServerStore().newId(),
          name: name,
          config: cfg,
        );
        await ref.read(serverListProvider.notifier).add(created);
        ref.read(activeServerProvider.notifier).set(created);
        if (mounted) Navigator.of(context).pop(created);
      }
    } catch (e) {
      setState(() => _nameError = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final client = S3Client(_buildConfig());
      final buckets = await client.listBuckets();
      final preview = buckets.isEmpty
          ? ''
          : ': ${buckets.take(5).join(", ")}${buckets.length > 5 ? "..." : ""}';
      setState(() {
        _testResult = '✓ 连接成功, 共 ${buckets.length} 个 bucket$preview';
      });
    } catch (e) {
      setState(() {
        _testResult = '✗ $e';
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isEdit ? '编辑服务器' : '添加服务器'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _isEdit ? '保存' : '保存并进入',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 16, 40, 80),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isEdit ? 'EDIT SERVER' : 'NEW SERVER',
                    style: theme.textTheme.eyebrow?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isEdit ? widget.existing!.name : '填一份配置',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isEdit
                        ? '修改后点保存, 立即生效.'
                        : '先填名字, 然后是 endpoint / 凭证. 填完可先"测试连接"验证.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ---- Section 1: 标识 ----
                  const _SectionLabel(label: '01 / 标识'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: '服务器名字',
                      helperText: '起个易记的名字, 例如 "工作 AWS" / "家里 MinIO"',
                      prefixIcon: const Icon(Icons.label_outline, size: 18),
                      errorText: _nameError,
                    ),
                    style: theme.textTheme.bodyLarge,
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入服务器名字' : null,
                  ),
                  const SizedBox(height: 32),

                  // ---- Section 2: 连接 ----
                  const _SectionLabel(label: '02 / 连接'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _endpoint,
                    decoration: const InputDecoration(
                      labelText: 'Endpoint',
                      hintText: 's3.amazonaws.com  或  minio.local:9000',
                      prefixIcon: Icon(Icons.dns_outlined, size: 18),
                    ),
                    style: theme.textTheme.mono,
                    onChanged: (_) => _onEndpointChanged(),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入 endpoint' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _region,
                    decoration: const InputDecoration(
                      labelText: 'Region',
                      hintText: 'us-east-1',
                      prefixIcon: Icon(Icons.public, size: 18),
                    ),
                    style: theme.textTheme.mono,
                  ),
                  const SizedBox(height: 12),
                  // 协议和地址风格分两行, 避免窄屏 (手机 / 缩窗) 两个 segmented
                  // 抢同一行空间, 长 label "PATH-STYLE / VIRTUAL-HOST" 被截.
                  // 各加 eyebrow sub-label, 跟 section 大标签风格一致.
                  const _FieldLabel(label: 'PROTOCOL'),
                  const SizedBox(height: 6),
                  _SegmentedToggle<bool>(
                    value: _secure,
                    options: const [false, true],
                    labels: const ['HTTP', 'HTTPS'],
                    onChanged: (v) => setState(() => _secure = v),
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel(label: 'ADDRESS STYLE'),
                  const SizedBox(height: 6),
                  _SegmentedToggle<bool>(
                    value: _pathStyle,
                    options: const [true, false],
                    labels: const ['PATH-STYLE', 'VIRTUAL-HOST'],
                    onChanged: (v) => setState(() => _pathStyle = v),
                  ),
                  const SizedBox(height: 32),

                  // ---- Section 3: 凭证 ----
                  const _SectionLabel(label: '03 / 凭证'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accessKey,
                    decoration: const InputDecoration(
                      labelText: 'Access Key',
                      prefixIcon: Icon(Icons.key_outlined, size: 18),
                    ),
                    style: theme.textTheme.mono,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入 access key' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _secretKey,
                    obscureText: _obscureSecret,
                    decoration: InputDecoration(
                      labelText: 'Secret Key',
                      prefixIcon:
                          const Icon(Icons.lock_outline, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureSecret
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        onPressed: () => setState(
                            () => _obscureSecret = !_obscureSecret),
                      ),
                    ),
                    style: theme.textTheme.mono,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入 secret key' : null,
                  ),
                  const SizedBox(height: 32),

                  // ---- Section 4: 默认 ----
                  const _SectionLabel(label: '04 / 默认值'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _defaultBucket,
                    decoration: const InputDecoration(
                      labelText: '默认 Bucket (可选)',
                      helperText: '进入此 server 后默认打开的 bucket',
                      prefixIcon: Icon(Icons.folder_outlined, size: 18),
                    ),
                    style: theme.textTheme.mono,
                  ),
                  const SizedBox(height: 32),

                  // ---- 测试结果 ----
                  if (_testResult != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _testResult!.startsWith('✓')
                            ? AppTheme.success.withValues(alpha: 0.10)
                            : AppTheme.error.withValues(alpha: 0.10),
                        border: Border.all(
                          color: _testResult!.startsWith('✓')
                              ? AppTheme.success.withValues(alpha: 0.4)
                              : AppTheme.error.withValues(alpha: 0.4),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _testResult!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _testResult!.startsWith('✓')
                              ? AppTheme.success
                              : AppTheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ---- 操作按钮 ----
                  // 之前 flex: 2 / flex: 3 同一行, 窄屏 (手机) 时 "测试连接" 4
                  // 个字得换行. 改成上下两行, 各占满宽, 顺序: 测试在上 (辅助)
                  // / 保存 (主操作) 在下 (靠近拇指).
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.wifi_tethering, size: 16),
                    label: const Text('测试连接'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : Icon(
                            _isEdit
                                ? Icons.check
                                : Icons.arrow_forward,
                            size: 16,
                          ),
                    label: Text(
                      _isEdit ? '保存修改' : '保存并进入',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.eyebrow?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

/// 字段内的小标签 (跟 _SectionLabel 同风格但更小、无分割线).
/// 用于 segmented toggle 之类没有自带 label 的控件前面.
class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.eyebrow?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
        fontSize: 9,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _SegmentedToggle<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final List<String> labels;
  final ValueChanged<T> onChanged;

  const _SegmentedToggle({
    required this.value,
    required this.options,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: List.generate(options.length, (i) {
          final selected = options[i] == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: theme.textTheme.eyebrow?.copyWith(
                      color: selected
                          ? scheme.primary
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
