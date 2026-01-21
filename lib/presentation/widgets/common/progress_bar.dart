import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';

/// Barra de progreso para el flujo de registro
/// Muestra paso actual de 5 (ej: 2/5)
class ProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final bool showText;

  const ProgressBar({
    super.key,
    required this.currentStep,
    this.totalSteps = 5,
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    final progress = currentStep / totalSteps;

    return Column(
      children: [
        // Texto del progreso
        if (showText)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Paso $currentStep de $totalSteps',
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: AppTextStyles.label.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        if (showText) const SizedBox(height: AppDimensions.spacingXS),

        // Barra de progreso
        ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Indicador de pasos con círculos
/// Muestra visualmente en qué paso está el usuario
class StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const StepIndicator({
    super.key,
    required this.currentStep,
    this.totalSteps = 5,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        totalSteps,
        (index) {
          final step = index + 1;
          final isActive = step == currentStep;
          final isCompleted = step < currentStep;

          return Row(
            children: [
              _buildStepCircle(
                step: step,
                isActive: isActive,
                isCompleted: isCompleted,
              ),
              if (index < totalSteps - 1) _buildConnector(isCompleted),
            ],
          );
        },
      ),
    );
  }

  /// Círculo de paso individual
  Widget _buildStepCircle({
    required int step,
    required bool isActive,
    required bool isCompleted,
  }) {
    Color circleColor;
    Color textColor;

    if (isCompleted) {
      circleColor = AppColors.primary;
      textColor = Colors.white;
    } else if (isActive) {
      circleColor = AppColors.primary;
      textColor = Colors.white;
    } else {
      circleColor = AppColors.border;
      textColor = AppColors.textSecondary;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: circleColor,
        shape: BoxShape.circle,
        border: isActive
            ? Border.all(
                color: AppColors.primary,
                width: 2,
              )
            : null,
      ),
      child: Center(
        child: isCompleted
            ? const Icon(
                Icons.check,
                size: 18,
                color: Colors.white,
              )
            : Text(
                '$step',
                style: AppTextStyles.label.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  /// Conector entre círculos
  Widget _buildConnector(bool isCompleted) {
    return Container(
      width: 24,
      height: 2,
      color: isCompleted ? AppColors.primary : AppColors.border,
    );
  }
}
