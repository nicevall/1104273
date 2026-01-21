import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../blocs/registration/registration_bloc.dart';
import '../../blocs/registration/registration_event.dart';
import '../../blocs/registration/registration_state.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/progress_bar.dart';

/// Step 4: Selección de rol
/// Usuario elige: Pasajero, Conductor o Ambos
class RegisterStep4Screen extends StatefulWidget {
  final String userId;

  const RegisterStep4Screen({
    super.key,
    required this.userId,
  });

  @override
  State<RegisterStep4Screen> createState() => _RegisterStep4ScreenState();
}

class _RegisterStep4ScreenState extends State<RegisterStep4Screen> {
  String? _selectedRole;

  /// Continuar a Step 5
  void _handleContinue() {
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un rol'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    context.read<RegistrationBloc>().add(
          RegisterStep4Event(role: _selectedRole!),
        );
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
          'Registro',
          style: AppTextStyles.h3.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: BlocConsumer<RegistrationBloc, RegistrationState>(
        listener: (context, state) {
          if (state is RegistrationStep5) {
            // Navegar a Step 5
            context.push('/register/step5', extra: {
              'userId': state.userId,
              'role': state.role,
            });
          } else if (state is RegistrationFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error),
                backgroundColor: AppColors.error,
              ),
            );
          } else if (state is RegistrationNetworkError) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sin conexión a internet'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state is RegistrationLoading && state.step == 4;

          return LoadingOverlay(
            isLoading: isLoading,
            message: 'Guardando rol...',
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.paddingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Barra de progreso
                  const ProgressBar(currentStep: 4),
                  const SizedBox(height: AppDimensions.spacingXL),

                  // Título
                  Text(
                    '¿Cómo quieres usar UniRide?',
                    style: AppTextStyles.h1,
                  ),
                  const SizedBox(height: AppDimensions.spacingS),

                  // Subtítulo
                  Text(
                    'Selecciona tu rol preferido. Podrás cambiarlo después.',
                    style: AppTextStyles.body1.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingXL),

                  // Tarjeta: Pasajero
                  _buildRoleCard(
                    role: 'pasajero',
                    icon: Icons.person,
                    title: 'Pasajero',
                    description:
                        'Busca y solicita viajes compartidos con otros estudiantes',
                    isSelected: _selectedRole == 'pasajero',
                    onTap: () {
                      setState(() {
                        _selectedRole = 'pasajero';
                      });
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacingM),

                  // Tarjeta: Conductor
                  _buildRoleCard(
                    role: 'conductor',
                    icon: Icons.drive_eta,
                    title: 'Conductor',
                    description:
                        'Ofrece viajes y comparte tu vehículo para ganar dinero',
                    isSelected: _selectedRole == 'conductor',
                    onTap: () {
                      setState(() {
                        _selectedRole = 'conductor';
                      });
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacingM),

                  // Tarjeta: Ambos
                  _buildRoleCard(
                    role: 'ambos',
                    icon: Icons.swap_horiz,
                    title: 'Ambos',
                    description:
                        'Alterna entre ser pasajero y conductor según tu necesidad',
                    isSelected: _selectedRole == 'ambos',
                    onTap: () {
                      setState(() {
                        _selectedRole = 'ambos';
                      });
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacingXL),

                  // Botón continuar
                  CustomButton.primary(
                    text: 'Continuar',
                    onPressed: isLoading ? null : _handleContinue,
                    isLoading: isLoading,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Tarjeta de selección de rol
  Widget _buildRoleCard({
    required String role,
    required IconData icon,
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppDimensions.paddingL),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.white,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Icono
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 28,
                color: isSelected ? Colors.white : AppColors.primary,
              ),
            ),
            const SizedBox(width: AppDimensions.spacingM),

            // Texto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.h3.copyWith(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Checkbox
            Icon(
              isSelected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: isSelected ? AppColors.primary : AppColors.border,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}
