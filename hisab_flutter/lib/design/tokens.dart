/// Hisab design tokens: colour, spacing, radius, type and motion. Values come
/// from the UI research spec (IDFC FIRST, Swiggy, Zomato Sushi); contrast
/// ratios in comments are against the page background unless noted.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Raw colours. Read them through [HisabColors] (`context.hisab`) in widgets;
/// this class is the single place a hex value lives.
abstract final class HisabPalette {
  // Brand ramp.
  static const brand050 = Color(0xFFFDF1EF);
  static const brand100 = Color(0xFFFBE0DC);
  static const brand200 = Color(0xFFF5BDB6);
  static const brand300 = Color(0xFFEE8E84);
  static const brand500 = Color(0xFFB8312A); // white text 5.98:1
  static const brand600 = Color(0xFF9B2620);
  static const brand900 = Color(0xFF3A0F0D);
  static const brandDarkFill = Color(0xFFC93A32); // white text 5.08:1
  static const brandDarkText = Color(0xFFFF8A7D); // 8.09:1 on darkBg

  // Light neutrals.
  static const lightBg = Color(0xFFFAF7F4);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSunken = Color(0xFFF2EEEA);
  static const lightOutline = Color(0xFFE7E1DC);
  static const lightText = Color(0xFF1C1A1B);
  static const lightTextSecondary = Color(0xFF5E5A5B);
  static const lightTextTertiary = Color(0xFF8A8586); // 3.6:1, decorative only

  // Dark neutrals. Dark fills sit lighter than the surface, so sunken shares
  // the raised value.
  static const darkBg = Color(0xFF151314);
  static const darkSurface = Color(0xFF1E1B1C);
  static const darkRaised = Color(0xFF2A2627);
  static const darkSunken = darkRaised;
  static const darkOutline = Color(0xFF3A3536);
  static const darkText = Color(0xFFF5F1EF);
  static const darkTextSecondary = Color(0xFFB7B1B2);
  static const darkTextTertiary = Color(0xFF8A8586);

  // Money. Debit is neutral ink with a "-" sign, never brand red.
  static const creditLight = Color(0xFF0F7A43); // 5.4:1
  static const creditDark = Color(0xFF5FD38D); // 9.1:1
  static const spendLight = Color(0xFFB34100); // 5.7:1
  static const spendDark = Color(0xFFFFA36B); // 8.7:1
  static const warnLight = Color(0xFFB7791F);
  static const warnDark = Color(0xFFF2C14E);

  // Tonal backgrounds: the tone at 10-16% over the surface.
  static const brandSoftDark = Color(0xFF422D2B);
  static const creditSoftLight = Color(0xFFE6F2EB);
  static const creditSoftDark = Color(0xFF28382E);
  static const spendSoftLight = Color(0xFFF7ECE6);
  static const spendSoftDark = Color(0xFF423129);

  /// Monogram hues for merchant avatars, picked per category or by name.
  static const avatarHues = [
    Color(0xFFC2410C),
    Color(0xFF1D4ED8),
    Color(0xFF7C3AED),
    Color(0xFF0F766E),
    Color(0xFF15803D),
    Color(0xFFBE185D),
    Color(0xFFA16207),
    Color(0xFF475569),
  ];
}

/// Spacing scale in logical pixels.
abstract final class HisabSpace {
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;

  /// Page side padding.
  static const double gutter = 16;
}

/// Corner radii in logical pixels.
abstract final class HisabRadius {
  static const double r4 = 4;
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r28 = 28;
  static const double pill = 999;
}

/// Type scale (size/weight/line height). No font family: the platform font
/// renders everything; amounts add tabular figures on top.
abstract final class HisabType {
  static const display = TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      height: 44 / 40,
      letterSpacing: 0);
  static const headline = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 32 / 28,
      letterSpacing: 0);
  static const titleLg = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 26 / 20,
      letterSpacing: 0);
  static const title = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 22 / 17,
      letterSpacing: 0);
  static const body = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 22 / 15,
      letterSpacing: 0);
  static const label = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 18 / 13,
      letterSpacing: 0);
  static const caption = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 16 / 12,
      letterSpacing: 0);
  static const micro = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      height: 12 / 10,
      letterSpacing: 0);

  /// Button labels: body size at title weight.
  static const button = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 20 / 15,
      letterSpacing: 0);

  static const tabular = [FontFeature.tabularFigures()];
}

/// Durations and the one easing curve.
abstract final class HisabMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const shimmer = Duration(milliseconds: 1000);
  static const curve = Curves.easeOutCubic;
}
