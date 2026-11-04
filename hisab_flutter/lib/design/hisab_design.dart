/// Material themes built from the tokens, plus [HisabColors] for the tokens
/// Material has no slot for (money, sunken surface, brand roles).
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Shared tonal roles for tags, pills and banners.
enum HisabTone { neutral, brand, credit, spend }

class HisabColors extends ThemeExtension<HisabColors> {
  final Color bg;
  final Color surface;
  final Color sunken;
  final Color raised;
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Filled brand (buttons, active fills); [onBrand] sits on it.
  final Color brand;
  final Color onBrand;

  /// Brand as text or icon on [bg]/[surface].
  final Color brandText;
  final Color brandSoft;
  final Color credit;
  final Color creditSoft;

  /// Emphasis and over-budget.
  final Color spend;
  final Color spendSoft;

  /// Nearing a limit (budget bar between brand and spend).
  final Color warn;

  /// The one vibrant accent: marks, selected bars, fills. Not small text.
  final Color gold;
  final Color goldSoft;

  /// The hero card's gradient stops; white text sits on both.
  final Color heroStart;
  final Color heroEnd;

  const HisabColors({
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.raised,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.brand,
    required this.onBrand,
    required this.brandText,
    required this.brandSoft,
    required this.credit,
    required this.creditSoft,
    required this.spend,
    required this.spendSoft,
    required this.warn,
    required this.gold,
    required this.goldSoft,
    required this.heroStart,
    required this.heroEnd,
  });

  static const light = HisabColors(
    bg: HisabPalette.lightBg,
    surface: HisabPalette.lightSurface,
    sunken: HisabPalette.lightSunken,
    raised: HisabPalette.lightSurface,
    outline: HisabPalette.lightOutline,
    textPrimary: HisabPalette.lightText,
    textSecondary: HisabPalette.lightTextSecondary,
    textTertiary: HisabPalette.lightTextTertiary,
    brand: HisabPalette.brand500,
    onBrand: Color(0xFFFFFFFF),
    brandText: HisabPalette.brand600,
    brandSoft: HisabPalette.brand050,
    credit: HisabPalette.creditLight,
    creditSoft: HisabPalette.creditSoftLight,
    spend: HisabPalette.spendLight,
    spendSoft: HisabPalette.spendSoftLight,
    warn: HisabPalette.warnLight,
    gold: HisabPalette.goldLight,
    goldSoft: HisabPalette.goldSoftLight,
    heroStart: HisabPalette.heroStartLight,
    heroEnd: HisabPalette.heroEndLight,
  );

  static const dark = HisabColors(
    bg: HisabPalette.darkBg,
    surface: HisabPalette.darkSurface,
    sunken: HisabPalette.darkSunken,
    raised: HisabPalette.darkRaised,
    outline: HisabPalette.darkOutline,
    textPrimary: HisabPalette.darkText,
    textSecondary: HisabPalette.darkTextSecondary,
    textTertiary: HisabPalette.darkTextTertiary,
    brand: HisabPalette.brandDarkFill,
    onBrand: Color(0xFFFFFFFF),
    brandText: HisabPalette.brandDarkText,
    brandSoft: HisabPalette.brandSoftDark,
    credit: HisabPalette.creditDark,
    creditSoft: HisabPalette.creditSoftDark,
    spend: HisabPalette.spendDark,
    spendSoft: HisabPalette.spendSoftDark,
    warn: HisabPalette.warnDark,
    gold: HisabPalette.goldDark,
    goldSoft: HisabPalette.goldSoftDark,
    heroStart: HisabPalette.heroStartDark,
    heroEnd: HisabPalette.heroEndDark,
  );

  /// Debit amounts are plain ink; the sign carries the meaning.
  Color get debit => textPrimary;

  /// Foreground and background for a tonal role.
  ({Color fg, Color bg}) tone(HisabTone tone) => switch (tone) {
        HisabTone.neutral => (fg: textSecondary, bg: sunken),
        HisabTone.brand => (fg: brandText, bg: brandSoft),
        HisabTone.credit => (fg: credit, bg: creditSoft),
        HisabTone.spend => (fg: spend, bg: spendSoft),
      };

  @override
  HisabColors copyWith({
    Color? bg,
    Color? surface,
    Color? sunken,
    Color? raised,
    Color? outline,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? brand,
    Color? onBrand,
    Color? brandText,
    Color? brandSoft,
    Color? credit,
    Color? creditSoft,
    Color? spend,
    Color? spendSoft,
    Color? warn,
    Color? gold,
    Color? goldSoft,
    Color? heroStart,
    Color? heroEnd,
  }) =>
      HisabColors(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        sunken: sunken ?? this.sunken,
        raised: raised ?? this.raised,
        outline: outline ?? this.outline,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        brand: brand ?? this.brand,
        onBrand: onBrand ?? this.onBrand,
        brandText: brandText ?? this.brandText,
        brandSoft: brandSoft ?? this.brandSoft,
        credit: credit ?? this.credit,
        creditSoft: creditSoft ?? this.creditSoft,
        spend: spend ?? this.spend,
        spendSoft: spendSoft ?? this.spendSoft,
        warn: warn ?? this.warn,
        gold: gold ?? this.gold,
        goldSoft: goldSoft ?? this.goldSoft,
        heroStart: heroStart ?? this.heroStart,
        heroEnd: heroEnd ?? this.heroEnd,
      );

  @override
  HisabColors lerp(HisabColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return HisabColors(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      sunken: mix(sunken, other.sunken),
      raised: mix(raised, other.raised),
      outline: mix(outline, other.outline),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      brand: mix(brand, other.brand),
      onBrand: mix(onBrand, other.onBrand),
      brandText: mix(brandText, other.brandText),
      brandSoft: mix(brandSoft, other.brandSoft),
      credit: mix(credit, other.credit),
      creditSoft: mix(creditSoft, other.creditSoft),
      spend: mix(spend, other.spend),
      spendSoft: mix(spendSoft, other.spendSoft),
      warn: mix(warn, other.warn),
      gold: mix(gold, other.gold),
      goldSoft: mix(goldSoft, other.goldSoft),
      heroStart: mix(heroStart, other.heroStart),
      heroEnd: mix(heroEnd, other.heroEnd),
    );
  }
}

extension HisabContext on BuildContext {
  /// The active [HisabColors]; falls back to light outside a Hisab theme.
  HisabColors get hisab =>
      Theme.of(this).extension<HisabColors>() ?? HisabColors.light;
}

class HisabDesign {
  static ThemeData light() => _theme(Brightness.light, HisabColors.light);

  static ThemeData dark() => _theme(Brightness.dark, HisabColors.dark);

  static const _textTheme = TextTheme(
    displayLarge: HisabType.display,
    displayMedium: HisabType.display,
    displaySmall: HisabType.display,
    headlineLarge: HisabType.headline,
    headlineMedium: HisabType.headline,
    headlineSmall: HisabType.titleLg,
    titleLarge: HisabType.title,
    titleMedium: HisabType.title,
    titleSmall: HisabType.label,
    bodyLarge: HisabType.body,
    bodyMedium: HisabType.body,
    bodySmall: HisabType.caption,
    labelLarge: HisabType.button,
    labelMedium: HisabType.label,
    labelSmall: HisabType.micro,
  );

  static ThemeData _theme(Brightness brightness, HisabColors c) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: HisabPalette.brand500,
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.onBrand,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: c.brandText,
      secondaryContainer: c.brandSoft,
      onSecondaryContainer: c.brandText,
      // Errors are orange: brand red never means "wrong".
      error: c.spend,
      onError: isDark ? HisabPalette.lightText : c.onBrand,
      errorContainer: c.spendSoft,
      onErrorContainer: c.spend,
      surface: c.bg,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.raised,
      surfaceContainerHighest: c.sunken,
      surfaceTint: Colors.transparent,
      outline: c.textTertiary,
      outlineVariant: c.outline,
      inverseSurface: isDark ? HisabPalette.darkText : HisabPalette.lightText,
      onInverseSurface: isDark ? HisabPalette.lightText : HisabPalette.darkText,
      inversePrimary:
          isDark ? HisabPalette.brand600 : HisabPalette.brandDarkText,
    );
    const buttonShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(HisabRadius.r12)));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: _textTheme,
      scaffoldBackgroundColor: c.bg,
      extensions: [c],
      // Five tabs at the platform's 15pt wrap "Transactions"; 12pt fits.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.brandSoft,
        labelTextStyle: WidgetStatePropertyAll(
            HisabType.caption.copyWith(fontWeight: FontWeight.w500, color: c.textPrimary)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HisabRadius.r16),
          side: BorderSide(color: c.outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 44),
          shape: buttonShape,
          textStyle: HisabType.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          shape: buttonShape,
          textStyle: HisabType.button,
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 36),
          shape: buttonShape,
          textStyle: HisabType.button,
          foregroundColor: c.brandText,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.4),
        showDragHandle: true,
        dragHandleSize: const Size(36, 4),
        dragHandleColor: c.textTertiary,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(HisabRadius.r28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle:
            HisabType.body.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(HisabRadius.r12))),
      ),
    );
  }
}
