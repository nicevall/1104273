// lib/core/constants/app_text_styles.dart
// Estilos de texto UniRide - Tipografía Poppins

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  // Constructor privado
  AppTextStyles._();

  // Familia de fuente base
  static const String _fontFamily = 'Poppins';

  // Headings
  static final TextStyle h1 = GoogleFonts.poppins(
    fontSize: 28,
    fontWeight: FontWeight.w700, // Bold
    height: 1.21, // 34/28
    color: AppColors.textPrimary,
  );

  static final TextStyle h2 = GoogleFonts.poppins(
    fontSize: 22,
    fontWeight: FontWeight.w600, // SemiBold
    height: 1.27, // 28/22
    color: AppColors.textPrimary,
  );

  static final TextStyle h3 = GoogleFonts.poppins(
    fontSize: 18,
    fontWeight: FontWeight.w500, // Medium
    height: 1.33, // 24/18
    color: AppColors.textPrimary,
  );

  // Body text
  static final TextStyle body1 = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w400, // Regular
    height: 1.5, // 24/16
    color: AppColors.textPrimary,
  );

  static final TextStyle body2 = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w400, // Regular
    height: 1.43, // 20/14
    color: AppColors.textSecondary,
  );

  // Caption y labels
  static final TextStyle caption = GoogleFonts.poppins(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    color: AppColors.textSecondary,
  );

  static final TextStyle label = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: AppColors.textSecondary,
  );

  // Botones
  static final TextStyle button = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w600, // SemiBold
    letterSpacing: 0.5,
    color: Colors.white,
  );

  static final TextStyle buttonSecondary = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: AppColors.primary,
  );

  // Links
  static final TextStyle link = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.primary,
    decoration: TextDecoration.underline,
  );

  // Input text
  static final TextStyle input = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static final TextStyle inputLabel = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static final TextStyle inputError = GoogleFonts.poppins(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.error,
  );
}
