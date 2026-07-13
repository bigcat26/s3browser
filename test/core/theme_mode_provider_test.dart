import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:s3browser/providers/theme_mode_provider.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeModeNotifier', () {
    Future<ProviderContainer> makeContainer() async {
      final container = ProviderContainer();
      // 多次 drain microtask + event loop, 让 _load() 真跑完
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (container.read(themeModeProvider) != ThemeMode.dark ||
            i == 19) {
          break;
        }
      }
      return container;
    }

    test('默认 = dark (没有保存值时)', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('set light 持久化', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).set(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);

      final p = await SharedPreferences.getInstance();
      expect(p.getString('s3browser.theme.v1'), 'light');
    });

    test('set system 持久化', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      await container
          .read(themeModeProvider.notifier)
          .set(ThemeMode.system);
      expect(container.read(themeModeProvider), ThemeMode.system);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('s3browser.theme.v1'), 'system');
    });

    test('启动时从 SharedPreferences 读回', () async {
      SharedPreferences.setMockInitialValues({
        's3browser.theme.v1': 'light',
      });
      final container = await makeContainer();
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('损坏值 → 回退到 dark', () async {
      SharedPreferences.setMockInitialValues({
        's3browser.theme.v1': 'garbage_value',
      });
      final container = await makeContainer();
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
