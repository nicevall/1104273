// lib/core/constants/app_colors.dart
// Paleta de colores UniRide - WCAG AA compliant

import 'package:flutter/material.dart';

class AppColors {
  // Constructor privado para evitar instanciación
  AppColors._();

  // Colores primarios
  static const Color primary = Color(0xFF6DCDC8); // Turquesa
  static const Color secondary = Color(0xFF1F514F); // Verde Oscuro
  static const Color tertiary = Color(0xFFEAEAEA); // Gris Claro
  static const Color quaternary = Color(0xFFE8E4E0); // Beige

  // Colores de superficie
  static const Color surface = Color(0xFFF5F5F5); // Fondo
  static const Color background = Color(0xFFFFFFFF); // Blanco

  // Colores de texto
  static const Color textPrimary = Color(0xFF1C1B1F); // Negro Suave
  static const Color textSecondary = Color(0xFF757575); // Gris Medio
  static const Color textTertiary = Color(0xFFAAAAAA); // Gris Claro

  // Estados
  static const Color success = Color(0xFF4CAF50); // Verde
  static const Color error = Color(0xFFF44336); // Rojo
  static const Color warning = Color(0xFFFFC107); // Amarillo
  static const Color info = Color(0xFF2196F3); // Azul

  // Sombras y overlays
  static const Color shadow = Color(0x1A000000); // Negro 10%
  static const Color overlay = Color(0x80000000); // Negro 50%
  static const Color divider = Color(0xFFE0E0E0); // Gris Divisor

  // Colores específicos de componentes
  static const Color inputBorder = Color(0xFFE0E0E0);
  static const Color inputFill = Color(0xFFFAFAFA);
  static const Color disabled = Color(0xFFBDBDBD);

  // Alias para compatibilidad
  static const Color border = Color(0xFFE0E0E0); // Mismo que inputBorder
}
