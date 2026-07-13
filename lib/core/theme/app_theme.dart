import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens. 调色板 + 字体 + 间距. 全部集中在这里, 业务代码只引用 token.
/// 风格: "Control Tower" — 工业 / 技术 / 实用. 暗色为主, 暖色为辅, 强 accent.
class AppTheme {
  AppTheme._();

  // -------- 颜色 (暗) --------
  // 灵感: 机场控制塔 / 数据中心监控屏. 深炭灰底, 暖白字, 橙色作 active accent.
  static const _darkBg = Color(0xFF0E0E10);
  static const _darkSurface = Color(0xFF16161A);
  static const _darkSurfaceContainer = Color(0xFF1F1F23);
  static const _darkSurfaceHigh = Color(0xFF26262B);
  static const _darkBorder = Color(0xFF2A2A2E);
  static const _darkBorderStrong = Color(0xFF3A3A3F);
  static const _darkTextPrimary = Color(0xFFF5F1E8);
  static const _darkTextSecondary = Color(0xFFA8A29E);
  static const _darkTextTertiary = Color(0xFF6B6B6B);

  // -------- 颜色 (亮) --------
  // 灵感: 旧纸张 + 油墨. 暖白底, 深墨字, 橙色稍降饱和度避免刺眼.
  static const _lightBg = Color(0xFFF8F5F0);
  static const _lightSurface = Color(0xFFFFFEFC);
  static const _lightSurfaceContainer = Color(0xFFF0EBE0);
  static const _lightSurfaceHigh = Color(0xFFE8E2D5);
  static const _lightBorder = Color(0xFFD9D2C5);
  static const _lightBorderStrong = Color(0xFFB8B0A0);
  static const _lightTextPrimary = Color(0xFF1A1A1A);
  static const _lightTextSecondary = Color(0xFF6B6358);
  static const _lightTextTertiary = Color(0xFF9A9080);

  // -------- Accent --------
  // 暗色用 AWS 标准橙 #FF9900, 亮色降饱和度为 #D97100 避免在白底上太刺眼.
  static const _accent = Color(0xFFFF9900);
  static const _accentMuted = Color(0xFFB36B00);
  static const _accentLight = Color(0xFFD97100);

  // -------- 状态色 (双模式通用, 都偏 muted) --------
  static const success = Color(0xFF7FB069);
  static const warning = Color(0xFFD4A574);
  static const error = Color(0xFFE07A5F);

  // -------- 字体 --------
  // Display: Bricolage Grotesque — 字符感强, 现代, 区别于通用 sans
  // Body: IBM Plex Sans — 工业感, 跟 Plex Mono 配套
  // Mono: IBM Plex Mono — 文件大小 / endpoint / key / 状态文字
  static TextTheme _textTheme(Brightness b) {
    final base = b == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;
    final display = GoogleFonts.bricolageGrotesqueTextTheme(base);
    final body = GoogleFonts.ibmPlexSansTextTheme(base);
    final mono = GoogleFonts.ibmPlexMonoTextTheme(base);
    return TextTheme(
      displayLarge: display.displayLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -1.5,
      ),
      displayMedium: display.displayMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -1.0,
      ),
      displaySmall: display.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      headlineLarge: display.headlineLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: display.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleLarge: body.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleMedium: body.titleMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      titleSmall: body.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
      bodyLarge: body.bodyLarge,
      bodyMedium: body.bodyMedium,
      bodySmall: body.bodySmall?.copyWith(
        letterSpacing: 0.2,
      ),
      labelLarge: body.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
      labelMedium: mono.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: mono.labelSmall?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
      ),
    );
  }

  // -------- 颜色方案 (供 ThemeData 引用) --------
  static ColorScheme _darkScheme() => const ColorScheme(
        brightness: Brightness.dark,
        primary: _accent,
        onPrimary: _darkBg,
        secondary: _accentMuted,
        onSecondary: _darkTextPrimary,
        surface: _darkSurface,
        onSurface: _darkTextPrimary,
        surfaceContainerHighest: _darkSurfaceContainer,
        surfaceContainerHigh: _darkSurfaceHigh,
        outline: _darkBorder,
        outlineVariant: _darkBorderStrong,
        error: error,
        onError: _darkTextPrimary,
      );

  static ColorScheme _lightScheme() => const ColorScheme(
        brightness: Brightness.light,
        primary: _accentLight,
        onPrimary: Color(0xFFFFFFFF),
        secondary: _accentMuted,
        onSecondary: _lightTextPrimary,
        surface: _lightSurface,
        onSurface: _lightTextPrimary,
        surfaceContainerHighest: _lightSurfaceContainer,
        surfaceContainerHigh: _lightSurfaceHigh,
        outline: _lightBorder,
        outlineVariant: _lightBorderStrong,
        error: error,
        onError: Color(0xFFFFFFFF),
      );

  // -------- 公开的 ThemeData --------
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness b) {
    final scheme = b == Brightness.dark ? _darkScheme() : _lightScheme();
    final textTheme = _textTheme(b);
    final isDark = b == Brightness.dark;
    final bg = isDark ? _darkBg : _lightBg;
    final surface = isDark ? _darkSurface : _lightSurface;
    final border = isDark ? _darkBorder : _lightBorder;
    final textPrimary =
        isDark ? _darkTextPrimary : _lightTextPrimary;
    final textSecondary =
        isDark ? _darkTextSecondary : _lightTextSecondary;

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      textTheme: textTheme,
      iconTheme: IconThemeData(color: textSecondary, size: 20),
      primaryIconTheme: IconThemeData(color: scheme.primary, size: 20),
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        toolbarHeight: 56,
        shape: Border(bottom: BorderSide(color: border, width: 1)),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: textPrimary, size: 20),
        actionsIconTheme: IconThemeData(color: textPrimary, size: 20),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: error, width: 1.5),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        helperStyle: textTheme.bodySmall?.copyWith(color: textSecondary),
        errorStyle:
            textTheme.bodySmall?.copyWith(color: error, fontFeatures: const []),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return scheme.primary;
          return isDark ? _darkTextTertiary : _lightTextTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.35);
          }
          return border;
        }),
        trackOutlineColor:
            WidgetStateProperty.all(Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: border, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textPrimary,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        extendedTextStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: 1),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border, width: 1),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? _darkSurfaceHigh : _lightSurfaceHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border, width: 1),
        ),
        elevation: 0,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: border,
        circularTrackColor: border,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? _darkSurfaceHigh : _lightSurfaceHigh,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: textPrimary),
        preferBelow: true,
      ),
    );
  }
}

/// 业务代码常用的语义化颜色 / 文本样式快捷访问.
extension AppColors on ColorScheme {
  Color get bg => brightness == Brightness.dark
      ? const Color(0xFF0E0E10)
      : const Color(0xFFF8F5F0);
  Color get surfaceContainer =>
      brightness == Brightness.dark
          ? const Color(0xFF1F1F23)
          : const Color(0xFFF0EBE0);
  Color get textTertiary => brightness == Brightness.dark
      ? const Color(0xFF6B6B6B)
      : const Color(0xFF9A9080);
}

extension AppTextStyles on TextTheme {
  /// 等宽小字, 用于文件大小 / endpoint / key 预览 / 状态码.
  TextStyle? get mono => GoogleFonts.ibmPlexMono(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: bodySmall?.color,
      );

  /// 用于 eyebrow / section label (ALL CAPS, 字距大, 字号小).
  TextStyle? get eyebrow => GoogleFonts.ibmPlexMono(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.4,
        color: bodySmall?.color,
      );

  /// Display, 用于空状态大字标语.
  TextStyle? get hero => GoogleFonts.bricolageGrotesque(
        fontSize: 56,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.5,
        height: 1.05,
        color: displaySmall?.color,
      );
}
