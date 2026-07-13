import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/browser/browser_page.dart';
import 'features/servers/server_list_page.dart';
import 'providers/active_server_provider.dart';
import 'providers/server_list_provider.dart';
import 'providers/theme_mode_provider.dart';

void main() {
  runApp(const ProviderScope(child: S3BrowserApp()));
}

class S3BrowserApp extends ConsumerWidget {
  const S3BrowserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverListProvider);
    final active = ref.watch(activeServerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'S3 Browser',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: servers.when(
        loading: () => const _SplashScreen(),
        error: (e, _) => _ErrorScreen(error: e.toString()),
        data: (_) {
          if (active != null) return const BrowserPage();
          return const ServerListPage();
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
}

class _ErrorScreen extends StatelessWidget {
  final String error;
  const _ErrorScreen({required this.error});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '加载配置失败: $error',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
}
