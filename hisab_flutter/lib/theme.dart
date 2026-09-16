/// Bahi-khata brand theme, mirroring HisabTheme.swift.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

class HisabTheme {
  static const khataRed = Color(0xFFA4243B);
  static const deepRed = Color(0xFF7E1B2E);
  static const kagaz = Color(0xFFF5EFE6);
  static const ink = Color(0xFF22333B);
  static const sona = Color(0xFFD9A441);
  static const hara = Color(0xFF2E6E4C);

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: khataRed,
          primary: khataRed,
          surface: kagaz,
        ),
        scaffoldBackgroundColor: kagaz,
        appBarTheme: const AppBarTheme(
          backgroundColor: kagaz,
          foregroundColor: ink,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 1,
          margin: EdgeInsets.symmetric(vertical: 6),
        ),
      );

  static Color amountColor(Direction direction) =>
      direction == Direction.debit ? khataRed : hara;

  static IconData sourceGlyph(Source source) {
    switch (source.rawValue) {
      case 'gpay':
      case 'paytm':
      case 'bhim':
        return Icons.currency_rupee;
      case 'hdfc':
      case 'idfc':
        return Icons.account_balance;
      default:
        return source.kind == SourceKind.bank
            ? Icons.account_balance
            : Icons.currency_rupee;
    }
  }
}
