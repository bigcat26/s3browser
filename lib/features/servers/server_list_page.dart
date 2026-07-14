import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/server.dart';
import '../../data/s3_client.dart';
import '../../providers/active_server_provider.dart';
import '../../providers/server_list_provider.dart';
import '../theme_menu_button.dart';
import 'server_form_page.dart';

/// 首页: 列出所有已配置的服务器. 点击进入浏览器; 右上 / 长按菜单管理.
class ServerListPage extends ConsumerWidget {
  const ServerListPage({super.key});

  Future<void> _openForm(BuildContext context, {Server? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServerFormPage(existing: existing),
      ),
    );
  }

  Future<void> _enter(BuildContext context, WidgetRef ref, Server s) async {
    ref.read(activeServerProvider.notifier).set(s);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, Server s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器?'),
        content: Text('"${s.name}" 的凭证会从本机清除.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final active = ref.read(activeServerProvider);
    if (active?.id == s.id) {
      ref.read(activeServerProvider.notifier).clear();
    }
    await ref.read(serverListProvider.notifier).delete(s.id);
  }

  Future<void> _testConnection(BuildContext context, Server s) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('正在测试连接…'),
        duration: Duration(seconds: 1),
      ),
    );
    try {
      final client = S3Client(s.config);
      final buckets = await client.listBuckets();
      messenger.showSnackBar(SnackBar(
        content: Text('✓ ${s.name} · ${buckets.length} 个 bucket'),
        backgroundColor: const Color(0xFF1F3322),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('✗ ${s.name} · $e'),
        backgroundColor: const Color(0xFF3A1F1F),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(serverListProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: const [
          ThemeMenuButton(),
          SizedBox(width: 8),
        ],
      ),
      body: serversAsync.when(
        loading: () => const _LoadingView(),
        error: (e, _) => _ErrorView(error: e.toString()),
        data: (servers) {
          if (servers.isEmpty) {
            return _EmptyState(onAdd: () => _openForm(context));
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _PageHeader(count: servers.length),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                sliver: SliverList.separated(
                  itemCount: servers.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, i) => _ServerCard(
                    server: servers[i],
                    index: i,
                    onEnter: () => _enter(context, ref, servers[i]),
                    onEdit: () => _openForm(context, existing: servers[i]),
                    onDelete: () => _delete(context, ref, servers[i]),
                    onTest: () => _testConnection(context, servers[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      // FAB 只在有 server 时显示. 空态自带 "添加第一个服务器" 大按钮,
      // 再叠 FAB 重复, 视觉噪声. 有 server 时 FAB 作为 "+ 再加一个" 入口.
      floatingActionButton: serversAsync.maybeWhen(
        data: (servers) => servers.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加服务器'),
              ),
        orElse: () => null,
      ),
    );
  }
}

// ============== Header ==============

class _PageHeader extends StatelessWidget {
  final int count;
  const _PageHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SERVERS',
            style: theme.textTheme.eyebrow?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                '控制塔',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: 40,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.outline,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$count  ACTIVE',
                    style: theme.textTheme.eyebrow?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '选择一个服务器进入. 凭证本地保存, 不上传.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ============== Server Card ==============

class _ServerCard extends StatefulWidget {
  final Server server;
  final int index;
  final VoidCallback onEnter;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTest;

  const _ServerCard({
    required this.server,
    required this.index,
    required this.onEnter,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
  });

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.server;
    final scheme = theme.colorScheme;
    // 不再显示 access key 前几位, 安全起见 (陌生人瞥到也无所谓, 但别养成习惯)
    final protocol = s.config.secure ? 'HTTPS' : 'HTTP';
    final style = s.config.pathStyle ? 'PATH' : 'VHOST';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hover ? scheme.primary : scheme.outline,
            width: _hover ? 1.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            children: [
              // hover 时左侧出现 3px 橙色 accent
              AnimatedPositioned(
                duration: const Duration(milliseconds: 140),
                left: 0,
                top: 0,
                bottom: 0,
                width: _hover ? 3 : 0,
                child: Container(color: scheme.primary),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onEnter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 8, 18),
                    child: Row(
                      children: [
                        // 序号
                        SizedBox(
                          width: 32,
                          child: Text(
                            (widget.index + 1).toString().padLeft(2, '0'),
                            style: theme.textTheme.mono?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.35),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        // 主信息
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Line 1: name (独占, 不跟 tags 抢)
                              Text(
                                s.name,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              // Line 2: URL endpoint
                              Text(
                                s.config.normalizedEndpoint,
                                style: theme.textTheme.mono?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.75),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              // Line 3: tags (Wrap 自动换行, region 也是 tag)
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _Badge(
                                    label: protocol,
                                    color: s.config.secure
                                        ? AppTheme.success
                                        : AppTheme.warning,
                                  ),
                                  _Badge(label: style, color: scheme.primary),
                                  _Badge(
                                    label: s.config.region,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    outlined: true,
                                  ),
                                  if (s.config.defaultBucket != null)
                                    _Badge(
                                      label: s.config.defaultBucket!,
                                      color: scheme.primary,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _CardMenu(
                          onTest: widget.onTest,
                          onEdit: widget.onEdit,
                          onDelete: widget.onDelete,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMenu extends StatelessWidget {
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CardMenu({
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '管理',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (v) {
        switch (v) {
          case 'test':
            onTest();
            break;
          case 'edit':
            onEdit();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (_) => [
        _popupItem('test', Icons.wifi_tethering, '测试连接'),
        _popupItem('edit', Icons.edit_outlined, '编辑'),
        PopupMenuDivider(),
        _popupItem('delete', Icons.delete_outline, '删除', danger: true),
      ],
    );
  }

  PopupMenuItem<String> _popupItem(
      String value, IconData icon, String label, {bool danger = false}) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: danger ? const Color(0xFFE07A5F) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool outlined;

  const _Badge({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.15),
        border: Border.all(
          color: outlined
              ? color.withValues(alpha: 0.4)
              : color.withValues(alpha: 0.4),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'IBM Plex Mono',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

// ============== Empty / Loading / Error ==============

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (ctx, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: IntrinsicHeight(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NO SERVERS YET',
                        style: theme.textTheme.eyebrow?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '空荡的\n控制台.',
                        style: theme.textTheme.hero,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '添加第一个 S3 兼容的对象存储, 开始浏览 / 上传 / 下载文件.\n'
                        '支持 AWS S3, MinIO, 阿里 OSS, 腾讯 COS, 以及任何兼容 S3 协议的服务.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.65),
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: onAdd,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('添加第一个服务器'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Text(
          '加载失败: $error',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        ),
      ),
    );
  }
}
