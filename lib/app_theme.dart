import 'package:flutter/material.dart';

class AppTheme {
  static const _base = Color(0xFF0B0D12);
  static const _navy = Color(0xFF10131A);
  static const _violet = Color(0xFF14121A);
  static const _panel = Color(0xFF151820);
  static const _line = Color(0xFF303442);
  static const _text = Color(0xFFE9ECF2);
  static const _secondaryText = Color(0xFFAAB0BE);
  static const _accent = Color(0xFFB5A4D4);
  static const _action = Color(0xFF4C4268);
  static const _radius = BorderRadius.all(Radius.circular(8));

  static const darkBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_navy, _base, _violet],
  );

  static final dark = _build(
    ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _accent,
      onPrimary: _base,
      primaryContainer: _action,
      onPrimaryContainer: _text,
      secondaryContainer: const Color(0xFF302D3C),
      onSecondaryContainer: const Color(0xFFE1DBED),
      surface: _panel,
      surfaceDim: _base,
      surfaceContainerLowest: _base,
      surfaceContainerLow: _navy,
      surfaceContainer: _panel,
      surfaceContainerHigh: const Color(0xFF1E212A),
      surfaceContainerHighest: const Color(0xFF272A34),
      onSurface: _text,
      onSurfaceVariant: _secondaryText,
      outline: const Color(0xFF737B8B),
      outlineVariant: _line,
      error: const Color(0xFFF1ADB0),
      onError: const Color(0xFF351518),
    ),
  );

  static final light = _build(
    ColorScheme.fromSeed(seedColor: const Color(0xFF63557F)),
  );

  static ThemeData _build(ColorScheme scheme) {
    final theme = ThemeData(useMaterial3: true, colorScheme: scheme);
    final border = RoundedRectangleBorder(borderRadius: _radius);
    final outline = BorderSide(color: scheme.outline);
    final focus = BorderSide(color: scheme.primary, width: 2);
    final field = OutlineInputBorder(
      borderRadius: _radius,
      borderSide: outline,
    );
    final text = theme.textTheme;
    return theme.copyWith(
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodySmall: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: scheme.surface,
        elevation: 0,
        shape: border.copyWith(side: BorderSide(color: scheme.outlineVariant)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        selectedTileColor: scheme.secondaryContainer,
        selectedColor: scheme.onSecondaryContainer,
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(borderSide: focus),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              shape: border,
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) return focus;
            return states.contains(WidgetState.disabled) ? null : outline;
              }),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: border).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) return focus;
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: scheme.outlineVariant);
            }
            return outline;
          }),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: border),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: border.copyWith(side: BorderSide(color: scheme.outline)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        shape: border.copyWith(side: BorderSide(color: scheme.outlineVariant)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: _radius,
          border: Border.all(color: scheme.outline),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onSurface),
      ),
    );
  }
}
