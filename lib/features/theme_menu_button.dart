import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../providers/theme_mode_provider.dart';

/// 主题切换按钮 + 弹出菜单. 在 AppBar 中用, 点开是 light/dark/system 三选.
///
/// 当前选中项前面有 check 标记.
class ThemeMenuButton extends ConsumerWidget {
  const ThemeMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return PopupMenuButton<ThemeMode>(
      tooltip: '主题',
      icon: Icon(_iconFor(mode)),
      onSelected: (m) => ref.read(themeModeProvider.notifier).set(m),
      itemBuilder: (popupCtx) {
        return [
          _item(popupCtx, ThemeMode.light, mode, Icons.light_mode_outlined, '浅色', 'LIGHT'),
          _item(popupCtx, ThemeMode.dark, mode, Icons.dark_mode_outlined, '深色', 'DARK'),
          _item(popupCtx, ThemeMode.system, mode, Icons.brightness_auto_outlined, '跟随系统', 'AUTO'),
        ];
      },
    );
  }

  static IconData _iconFor(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }

  static PopupMenuItem<ThemeMode> _item(
    BuildContext ctx,
    ThemeMode value,
    ThemeMode current,
    IconData icon,
    String label,
    String tag,
  ) {
    final selected = value == current;
    return PopupMenuItem<ThemeMode>(
      value: value,
      child: Row(
        children: [
          Icon(
            selected ? Icons.check : icon,
            size: 16,
            color: selected ? Theme.of(ctx).colorScheme.primary : null,
          ),
          const SizedBox(width: 10),
          Text(label),
          const Spacer(),
          Text(
            tag,
            style: Theme.of(ctx).textTheme.eyebrow?.copyWith(
                  fontSize: 9,
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.45),
                ),
          ),
        ],
      ),
    );
  }
}
