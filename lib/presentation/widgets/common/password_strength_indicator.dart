import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/validators.dart';

/// Indicador visual de fortaleza de contraseña
/// Muestra barra de color y texto (Débil/Media/Fuerte)
class PasswordStrengthIndicator extends StatelessWidget {
  final String password;
  final bool showRequirements;

  const PasswordStrengthIndicator({
    super.key,
    required this.password,
    this.showRequirements = true,
  });

  @override
  Widget build(BuildContext context) {
    final strength = Validators.calculatePasswordStrength(password);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Barra de fortaleza
        _buildStrengthBar(strength),
        const SizedBox(height: AppDimensions.spacingXS),

        // Texto de fortaleza
        _buildStrengthText(strength),

        // Requisitos (opcional)
        if (showRequirements && password.isNotEmpty) ...[
          const SizedBox(height: AppDimensions.spacingS),
          _buildRequirements(),
        ],
      ],
    );
  }

  /// Barra de color según fortaleza
  Widget _buildStrengthBar(PasswordStrength strength) {
    Color barColor;
    double progress;

    switch (strength) {
      case PasswordStrength.weak:
        barColor = AppColors.error;
        progress = 0.33;
        break;
      case PasswordStrength.medium:
        barColor = AppColors.warning;
        progress = 0.66;
        break;
      case PasswordStrength.strong:
        barColor = AppColors.success;
        progress = 1.0;
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
      child: LinearProgressIndicator(
        value: password.isEmpty ? 0 : progress,
        minHeight: 6,
        backgroundColor: AppColors.border,
        valueColor: AlwaysStoppedAnimation<Color>(barColor),
      ),
    );
  }

  /// Texto descriptivo de fortaleza
  Widget _buildStrengthText(PasswordStrength strength) {
    String text;
    Color color;

    switch (strength) {
      case PasswordStrength.weak:
        text = 'Contraseña débil';
        color = AppColors.error;
        break;
      case PasswordStrength.medium:
        text = 'Contraseña media';
        color = AppColors.warning;
        break;
      case PasswordStrength.strong:
        text = 'Contraseña fuerte';
        color = AppColors.success;
        break;
    }

    if (password.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Icon(
          _getStrengthIcon(strength),
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTextStyles.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Icono según fortaleza
  IconData _getStrengthIcon(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.weak:
        return Icons.cancel;
      case PasswordStrength.medium:
        return Icons.warning;
      case PasswordStrength.strong:
        return Icons.check_circle;
    }
  }

  /// Lista de requisitos con checkmarks
  Widget _buildRequirements() {
    final hasMinLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));
    final hasSpecialChar = password.contains(RegExp(r'[@#$%&*!?\-_]'));
    final hasInvalidChars = Validators.hasInvalidSpecialChars(password);
    final invalidChars = hasInvalidChars ? Validators.getInvalidChars(password) : [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Requisitos:',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        _buildRequirement('Mínimo 8 caracteres', hasMinLength),
        _buildRequirement('Una letra mayúscula', hasUppercase),
        _buildRequirement('Una letra minúscula', hasLowercase),
        _buildRequirement('Un número', hasNumber),
        _buildRequirement('Un caracter especial (@#\$%&*!?-_)', hasSpecialChar),

        // Advertencia de caracteres no permitidos
        if (hasInvalidChars) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.error.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning,
                  size: 14,
                  color: AppColors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Caracteres no permitidos: ${invalidChars.join(", ")}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Item de requisito individual
  Widget _buildRequirement(String text, bool isMet) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: isMet ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTextStyles.caption.copyWith(
              color: isMet ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}
