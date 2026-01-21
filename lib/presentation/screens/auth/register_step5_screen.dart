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

/// Step 5: Advertencia de pantalla completa
/// Muestra términos y condiciones según el rol seleccionado
class RegisterStep5Screen extends StatelessWidget {
  final String userId;
  final String role;

  const RegisterStep5Screen({
    super.key,
    required this.userId,
    required this.role,
  });

  /// Contenido según el rol
  Map<String, dynamic> get _content {
    switch (role) {
      case 'pasajero':
        return {
          'icon': Icons.info_outline,
          'title': 'Importante para pasajeros',
          'points': [
            'Solo podrás viajar con estudiantes verificados de UIDE',
            'Debes calificar a los conductores después de cada viaje',
            'El pago se realiza directamente al conductor',
            'Respeta las normas de convivencia dentro del vehículo',
            'Llega puntual a los puntos de encuentro acordados',
          ],
        };
      case 'conductor':
        return {
          'icon': Icons.drive_eta,
          'title': 'Importante para conductores',
          'points': [
            'Tu licencia de conducir será verificada por el equipo de UniRide',
            'Debes mantener tu vehículo en buen estado',
            'Es obligatorio tener SOAT vigente',
            'Debes respetar las tarifas sugeridas por la plataforma',
            'Cualquier comportamiento inapropiado puede resultar en suspensión',
            'Debes calificar a los pasajeros después de cada viaje',
          ],
        };
      case 'ambos':
        return {
          'icon': Icons.swap_horiz,
          'title': 'Importante como pasajero y conductor',
          'points': [
            'Tu licencia de conducir será verificada para poder ofrecer viajes',
            'Debes cumplir las normas tanto de pasajero como de conductor',
            'Es obligatorio mantener SOAT vigente cuando conduzcas',
            'Debes calificar a otros usuarios después de cada viaje',
            'El respeto y puntualidad son fundamentales en ambos roles',
            'Cualquier comportamiento inapropiado puede resultar en suspensión',
          ],
        };
      default:
        return {
          'icon': Icons.info_outline,
          'title': 'Información importante',
          'points': ['Error: Rol no reconocido'],
        };
    }
  }

  /// Aceptar y continuar
  void _handleAccept(BuildContext context) {
    context.read<RegistrationBloc>().add(const RegisterStep5ConfirmEvent());
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: BlocListener<RegistrationBloc, RegistrationState>(
        listener: (context, state) {
          if (state is RegistrationVehicle) {
            // Navegar a registro de vehículo
            context.go('/register/vehicle', extra: {
              'userId': state.userId,
              'role': state.role,
            });
          } else if (state is RegistrationSuccess) {
            // Ir a pantalla de estado de registro
            context.go('/register/status', extra: {
              'userId': state.userId,
              'role': state.role,
              'hasVehicle': state.hasVehicle,
              'status': 'success',
            });
          }
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.paddingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppDimensions.spacingL),

                // Icono
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      content['icon'] as IconData,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingL),

                // Título
                Text(
                  content['title'] as String,
                  style: AppTextStyles.h1.copyWith(
                    color: Colors.white,
                    fontSize: 28,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimensions.spacingXL),

                // Lista de puntos importantes
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: (content['points'] as List<String>)
                          .map((point) => _buildPoint(point))
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingL),

                // Checkbox de términos
                Container(
                  padding: const EdgeInsets.all(AppDimensions.paddingM),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius:
                        BorderRadius.circular(AppDimensions.borderRadius),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'He leído y acepto los términos y condiciones',
                          style: AppTextStyles.body2.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingL),

                // Botón aceptar
                CustomButton.primary(
                  text: 'Aceptar y continuar',
                  onPressed: () => _handleAccept(context),
                ),
                const SizedBox(height: AppDimensions.spacingM),

                // Botón cancelar
                CustomButton.secondary(
                  text: 'Cancelar registro',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('¿Cancelar registro?'),
                        content: const Text(
                          '¿Estás seguro que deseas cancelar el registro? Perderás todo el progreso.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('No'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              context.go('/welcome');
                            },
                            child: const Text(
                              'Sí, cancelar',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Item de punto importante
  Widget _buildPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body1.copyWith(
                color: Colors.white,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
