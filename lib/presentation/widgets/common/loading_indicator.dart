import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Indicador de carga personalizado
/// Muestra un CircularProgressIndicator con mensaje opcional
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final Color? color;
  final double size;

  const LoadingIndicator({
    super.key,
    this.message,
    this.color,
    this.size = 40,
  });

  /// Loading indicator centrado en pantalla completa
  factory LoadingIndicator.fullScreen({
    String? message,
    Color? color,
  }) {
    return LoadingIndicator(
      message: message,
      color: color,
      size: 48,
    );
  }

  /// Loading indicator pequeño inline
  factory LoadingIndicator.small({Color? color}) {
    return LoadingIndicator(
      color: color,
      size: 24,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              color: color ?? AppColors.primary,
              strokeWidth: 3,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Loading overlay que se superpone a la pantalla
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? message;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: LoadingIndicator.fullScreen(
              message: message,
            ),
          ),
      ],
    );
  }
}
