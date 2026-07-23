import 'package:flutter/material.dart';

class DColors {
  DColors._();

  // App theme colors
  static const Color primary = Color(0xFF004368);
  static const Color primarySecondary = Color(0xFFECF4FA);

  // Body text colors
  static const Color textPrimary = Color(0xFF7B7B7B);
  static const Color textSecondary = Color(0xFF004368);
  static const Color textWhite = Colors.white;
  static const Color popUpBody = Color(0xFF494F55);

  // Card text colors
  static const Color cardTextPrimary = Color(0xFF181818);
  static const Color cardTextSecondary = Color(0xFF004368);

  // Background colors
  static const Color light = Color(0xFFF6F6F6);
  static const Color dark = Color(0xFF272727);

  // Background container colors
  static const Color lightContainer = Color(0xFFF6F6F6);
  static Color darkContainer = DColors.white.withValues(alpha: 0.1);

  // Button colors
  static const Color buttonPrimary = Color(0xFF004368);
  static const Color textButtonPrimary = Color(0xE035707D);
  static const Color buttonSecondary = Color(0xFF6C757D);
  static const Color buttonDisabled = Color(0xFFC4C4C4);

  // Border colors
  static const Color borderPrimary = Color(0xFFD9D9D9);
  static const Color borderSecondary = Color(0xFFE6E6E6);

  // Error and validation colors
  static const Color error = Color(0xFF004368);
  static const Color success = Color(0xFF388E3C);
  static const Color warning = Color(0xFFF57C00);
  static const Color info = primary;

  // Snackbar colors
  static const Color sSuccessBackground = Color(0xFFD6F0E0);
  static const Color sInfoBackground = Color(0xFFDFE7F6);
  static const Color sErrorBackground = Color(0xFFF9E1E5);

  static const Color sSuccessStroke = Color(0xFF4FBB7A);
  static const Color sInfoStroke = primary;
  static const Color sErrorStroke = Color(0xFFFF233A);

  // Neutral shades
  static const Color black = Color(0xFF0A0A0A);
  static const Color darkerGrey = Color(0xFF4F4F4F);
  static const Color darkGrey = Color(0xFF939393);
  static const Color grey = Color(0xFFE0E0E0);
  static const Color softGrey = Color(0xFFF4F4F4);
  static const Color lightGrey = Color(0xFFF9F9F9);
  static const Color white = Color(0xFFFFFFFF);

  // Face attendance colors
  static const Color fBlack = Color(0xFF1B1B1B);
  static const Color fborder = Color(0xFF668EA4);
}
