import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';

/// Botón personalizado con variantes primaria y secundaria
/// Sigue el sistema de diseño de UniRide
class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isPrimary;
  final IconData? icon;
  final double? width;
  final double? height;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.isPrimary = true,
    this.icon,
    this.width,
    this.height,
  });

  /// Botón primario (turquesa)
  factory CustomButton.primary({
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
    IconData? icon,
    double? width,
    double? height,
  }) {
    return CustomButton(
      text: text,
      onPressed: onPressed,
      isLoading: isLoading,
      isPrimary: true,
      icon: icon,
      width: width,
      height: height,
    );
  }

  /// Botón secundario (outline)
  factory CustomButton.secondary({
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
    IconData? icon,
    double? width,
    double? height,
  }) {
    return CustomButton(
      text: text,
      onPressed: onPressed,
      isLoading: isLoading,
      isPrimary: false,
      icon: icon,
      width: width,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttonHeight = height ?? AppDimensions.buttonHeight;
    final buttonWidth = width ?? double.infinity;

    if (isPrimary) {
      return _buildPrimaryButton(buttonHeight, buttonWidth);
    } else {
      return _buildSecondaryButton(buttonHeight, buttonWidth);
    }
  }

  /// Botón primario (relleno turquesa)
  Widget _buildPrimaryButton(double buttonHeight, double buttonWidth) {
    return SizedBox(
      height: buttonHeight,
      width: buttonWidth,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.disabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : _buildButtonContent(),
      ),
    );
  }

  /// Botón secundario (outline)
  Widget _buildSecondaryButton(double buttonHeight, double buttonWidth) {
    return SizedBox(
      height: buttonHeight,
      width: buttonWidth,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(
            color: AppColors.primary,
            width: 1.5,
          ),
          disabledForegroundColor: AppColors.disabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              )
            : _buildButtonContent(),
      ),
    );
  }

  /// Contenido del botón (texto + icono opcional)
  Widget _buildButtonContent() {
    if (icon != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTextStyles.button,
          ),
        ],
      );
    }

    return Text(
      text,
      style: AppTextStyles.button,
    );
  }
}
