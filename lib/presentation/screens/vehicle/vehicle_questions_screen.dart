import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../widgets/common/custom_button.dart';

/// Pantalla de preguntas iniciales sobre el vehículo
/// Pregunta 1: ¿De quién es el vehículo?
/// Pregunta 2: ¿Quién va a conducir?
class VehicleQuestionsScreen extends StatefulWidget {
  final String userId;
  final String role;
  final bool isPostLogin; // true si viene del home después de iniciar sesión

  const VehicleQuestionsScreen({
    super.key,
    required this.userId,
    required this.role,
    this.isPostLogin = false,
  });

  @override
  State<VehicleQuestionsScreen> createState() => _VehicleQuestionsScreenState();
}

class _VehicleQuestionsScreenState extends State<VehicleQuestionsScreen> {
  String? _vehicleOwnership; // 'mio', 'familiar', 'amigo'
  String? _driverRelation;   // 'yo', 'familiar', 'amigo'

  bool get _canContinue => _vehicleOwnership != null && _driverRelation != null;

  void _handleContinue() {
    if (!_canContinue) return;

    context.push('/register/vehicle/matricula', extra: {
      'userId': widget.userId,
      'role': widget.role,
      'vehicleOwnership': _vehicleOwnership,
      'driverRelation': _driverRelation,
      'isPostLogin': widget.isPostLogin,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Registro de vehículo',
          style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Contenido scrollable
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimensions.paddingL),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título
                    Text(
                      'Antes de comenzar...',
                      style: AppTextStyles.h1,
                    ),
                    const SizedBox(height: AppDimensions.spacingS),
                    Text(
                      'Necesitamos saber algunos datos sobre el vehículo',
                      style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppDimensions.spacingL),

                    // Pregunta 1: Propiedad del vehículo
                    _buildQuestion(
                      icon: Icons.directions_car,
                      question: '¿De quién es el vehículo?',
                      options: [
                        _OptionItem(value: 'mio', label: 'Mío', icon: Icons.person),
                        _OptionItem(value: 'familiar', label: 'De un familiar', icon: Icons.family_restroom),
                        _OptionItem(value: 'amigo', label: 'De un amigo', icon: Icons.people),
                      ],
                      selectedValue: _vehicleOwnership,
                      onChanged: (value) => setState(() => _vehicleOwnership = value),
                    ),
                    const SizedBox(height: AppDimensions.spacingL),

                    // Pregunta 2: Quién conduce
                    _buildQuestion(
                      icon: Icons.airline_seat_recline_normal,
                      question: '¿Quién va a conducir?',
                      options: [
                        _OptionItem(value: 'yo', label: 'Yo mismo', icon: Icons.person),
                        _OptionItem(value: 'familiar', label: 'Un familiar', icon: Icons.family_restroom),
                        _OptionItem(value: 'amigo', label: 'Un amigo', icon: Icons.people),
                      ],
                      selectedValue: _driverRelation,
                      onChanged: (value) => setState(() => _driverRelation = value),
                    ),
                  ],
                ),
              ),
            ),

            // Sección inferior fija
            Padding(
              padding: const EdgeInsets.all(AppDimensions.paddingL),
              child: Column(
                children: [
                  // Nota informativa
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.paddingM),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
                      border: Border.all(color: AppColors.info.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.info, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'A continuación tomarás fotos de la matrícula, licencia y el vehículo para verificación.',
                            style: AppTextStyles.caption.copyWith(color: AppColors.info),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingM),

                  // Botón continuar
                  CustomButton.primary(
                    text: 'Continuar',
                    onPressed: _canContinue ? _handleContinue : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion({
    required IconData icon,
    required String question,
    required List<_OptionItem> options,
    required String? selectedValue,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                question,
                style: AppTextStyles.h3,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.spacingM),
        ...options.map((option) => _buildOptionTile(
          option: option,
          isSelected: selectedValue == option.value,
          onTap: () => onChanged(option.value),
        )),
      ],
    );
  }

  Widget _buildOptionTile({
    required _OptionItem option,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingS),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        child: Container(
          padding: const EdgeInsets.all(AppDimensions.paddingM),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.background,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  option.icon,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  option.label,
                  style: AppTextStyles.body1.copyWith(
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: AppColors.primary, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionItem {
  final String value;
  final String label;
  final IconData icon;

  const _OptionItem({
    required this.value,
    required this.label,
    required this.icon,
  });
}
