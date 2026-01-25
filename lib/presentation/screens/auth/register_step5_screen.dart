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
class RegisterStep5Screen extends StatefulWidget {
  final String userId;
  final String role;

  const RegisterStep5Screen({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  State<RegisterStep5Screen> createState() => _RegisterStep5ScreenState();
}

class _RegisterStep5ScreenState extends State<RegisterStep5Screen> {
  bool _acceptedTerms = false;

  /// Contenido según el rol - Adaptado para Ecuador
  Map<String, dynamic> get _content {
    switch (widget.role) {
      case 'pasajero':
        return {
          'icon': Icons.person,
          'title': 'Confirmar rol: Solo Pasajero',
          'warning': 'Esta elección es PERMANENTE. Solo podrás solicitar viajes, NO podrás ofrecer viajes como conductor.',
          'points': [
            'Solo podrás viajar con estudiantes verificados de UIDE Ecuador',
            'NO podrás registrar un vehículo ni ofrecer viajes',
            'Debes calificar a los conductores después de cada viaje',
            'El pago se realiza en efectivo o transferencia bancaria directamente al conductor',
            'Respeta las normas de convivencia dentro del vehículo',
            'Llega puntual a los puntos de encuentro acordados',
            'UniRide no se responsabiliza por objetos olvidados en los vehículos',
            'En caso de emergencia, contacta al ECU 911',
          ],
          'changeRoleNote': 'Si deseas cambiar tu rol en el futuro, deberás contactar a soporte técnico de UniRide.',
        };
      case 'conductor':
        return {
          'icon': Icons.drive_eta,
          'title': 'Confirmar rol: Solo Conductor',
          'warning': 'Esta elección es PERMANENTE. Solo podrás ofrecer viajes, NO podrás solicitar viajes como pasajero.',
          'points': [
            'Debes tener licencia de conducir tipo B vigente emitida por la ANT',
            'Tu licencia será verificada por el equipo de UniRide',
            'NO podrás solicitar viajes como pasajero',
            'Es obligatorio tener matrícula vehicular y revisión técnica vigentes',
            'Tu vehículo debe estar en buen estado mecánico y de aseo',
            'Debes respetar las tarifas sugeridas por la plataforma',
            'El pago se recibe en efectivo o transferencia bancaria',
            'Cualquier comportamiento inapropiado resulta en suspensión permanente',
            'Debes calificar a los pasajeros después de cada viaje',
          ],
          'changeRoleNote': 'Si deseas cambiar tu rol en el futuro, deberás contactar a soporte técnico de UniRide.',
        };
      case 'ambos':
        return {
          'icon': Icons.swap_horiz,
          'title': 'Confirmar rol: Pasajero y Conductor',
          'warning': 'Esta elección es PERMANENTE. Podrás alternar entre solicitar y ofrecer viajes.',
          'points': [
            'Debes tener licencia de conducir tipo B vigente emitida por la ANT',
            'Tu licencia será verificada para poder ofrecer viajes',
            'Es obligatorio tener matrícula vehicular y revisión técnica vigentes',
            'Debes cumplir las normas tanto de pasajero como de conductor',
            'Debes calificar a otros usuarios después de cada viaje',
            'El pago se realiza en efectivo o transferencia bancaria',
            'El respeto y puntualidad son fundamentales en ambos roles',
            'Cualquier comportamiento inapropiado resulta en suspensión permanente',
          ],
          'changeRoleNote': 'Si deseas cambiar tu rol en el futuro, deberás contactar a soporte técnico de UniRide.',
        };
      default:
        return {
          'icon': Icons.info_outline,
          'title': 'Información importante',
          'warning': '',
          'points': ['Error: Rol no reconocido'],
          'changeRoleNote': '',
        };
    }
  }

  /// Aceptar y continuar
  void _handleAccept() {
    context.read<RegistrationBloc>().add(const RegisterStep5ConfirmEvent());
  }

  /// Volver al paso anterior (selección de rol)
  void _handleGoBack() {
    context.read<RegistrationBloc>().add(const GoBackEvent());
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleGoBack();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: BlocListener<RegistrationBloc, RegistrationState>(
          listener: (context, state) {
            if (state is RegistrationStep4) {
              // Volver a la pantalla de selección de rol
              context.go('/register/step4', extra: {
                'userId': state.userId,
              });
            } else if (state is RegistrationVehicle) {
              // Navegar a nuevo flujo de registro de vehículo (preguntas primero)
              context.go('/register/vehicle/questions', extra: {
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
                // Botón volver
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: _handleGoBack,
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 28,
                    ),
                    tooltip: 'Volver a selección de rol',
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingS),

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
                Center(
                  child: Text(
                    content['title'] as String,
                    style: AppTextStyles.h1.copyWith(
                      color: Colors.white,
                      fontSize: 24,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingM),

                // Advertencia de permanencia (destacada)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppDimensions.paddingM),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          content['warning'] as String,
                          style: AppTextStyles.body2.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingL),

                // Lista de puntos importantes
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Condiciones:',
                          style: AppTextStyles.h3.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spacingS),
                        ...(content['points'] as List<String>)
                            .map((point) => _buildPoint(point))
                            .toList(),
                        const SizedBox(height: AppDimensions.spacingM),
                        // Nota sobre cambio de rol
                        Container(
                          padding: const EdgeInsets.all(AppDimensions.paddingS),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.white70,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  content['changeRoleNote'] as String,
                                  style: AppTextStyles.caption.copyWith(
                                    color: Colors.white70,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingM),

                // Checkbox de términos (interactivo)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _acceptedTerms = !_acceptedTerms;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(AppDimensions.paddingM),
                    decoration: BoxDecoration(
                      color: _acceptedTerms
                          ? Colors.white.withOpacity(0.2)
                          : Colors.white.withOpacity(0.1),
                      borderRadius:
                          BorderRadius.circular(AppDimensions.borderRadius),
                      border: Border.all(
                        color: _acceptedTerms
                            ? Colors.white
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _acceptedTerms
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
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
                ),
                const SizedBox(height: AppDimensions.spacingL),

                // Botón aceptar (gris cuando deshabilitado, blanco cuando habilitado)
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
                    border: Border.all(
                      color: _acceptedTerms ? Colors.white : Colors.grey.shade600,
                      width: 2,
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: _acceptedTerms ? _handleAccept : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _acceptedTerms ? Colors.white : Colors.grey.shade700,
                      foregroundColor: AppColors.primary,
                      disabledBackgroundColor: Colors.grey.shade700,
                      disabledForegroundColor: Colors.grey.shade400,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.borderRadius - 2),
                      ),
                    ),
                    child: Text(
                      'Aceptar y continuar',
                      style: AppTextStyles.button.copyWith(
                        color: _acceptedTerms ? AppColors.primary : Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingM),

                // Botón cancelar (rojo)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
                      ),
                    ),
                    child: Text(
                      'Cancelar registro',
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
