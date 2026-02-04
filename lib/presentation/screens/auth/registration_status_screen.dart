import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../widgets/common/custom_button.dart';

/// Pantalla de estado de registro
/// Muestra 3 estados dinámicos: success, error, network
class RegistrationStatusScreen extends StatelessWidget {
  final String userId;
  final String role;
  final bool hasVehicle;
  final String status; // 'success', 'error', 'network'

  const RegistrationStatusScreen({
    super.key,
    required this.userId,
    required this.role,
    required this.hasVehicle,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'success':
        return _buildSuccessState(context);
      case 'error':
        return _buildErrorState(context);
      case 'network':
        return _buildNetworkErrorState(context);
      default:
        return _buildSuccessState(context);
    }
  }

  /// Estado: Registro exitoso
  Widget _buildSuccessState(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.success,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icono de éxito
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXL),

              // Título
              Text(
                '¡Registro exitoso!',
                style: AppTextStyles.h1.copyWith(
                  color: Colors.white,
                  fontSize: 32,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.spacingM),

              // Mensaje según rol y vehículo
              Text(
                _getSuccessMessage(),
                style: AppTextStyles.body1.copyWith(
                  color: Colors.white.withOpacity(0.9),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.spacingXL),

              // Información adicional
              if (hasVehicle) ...[
                Container(
                  padding: const EdgeInsets.all(AppDimensions.paddingM),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius:
                        BorderRadius.circular(AppDimensions.borderRadius),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tu vehículo será verificado en máximo 24 horas. Te notificaremos cuando esté aprobado.',
                          style: AppTextStyles.body2.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingL),
              ],

              const Spacer(),

              // Botón ir a inicio
              CustomButton(
                text: 'Ir a inicio',
                onPressed: () => context.go('/home', extra: {
                  'userId': userId,
                  'userRole': role,
                }),
                isPrimary: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Estado: Error en el registro
  Widget _buildErrorState(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.error,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icono de error
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  size: 80,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXL),

              // Título
              Text(
                'Algo salió mal',
                style: AppTextStyles.h1.copyWith(
                  color: Colors.white,
                  fontSize: 32,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.spacingM),

              // Mensaje
              Text(
                'Ocurrió un error durante el registro. Por favor, intenta nuevamente más tarde.',
                style: AppTextStyles.body1.copyWith(
                  color: Colors.white.withOpacity(0.9),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.spacingXL),

              // Información de contacto
              Container(
                padding: const EdgeInsets.all(AppDimensions.paddingM),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius:
                      BorderRadius.circular(AppDimensions.borderRadius),
                ),
                child: Column(
                  children: [
                    Text(
                      'Si el problema persiste, contacta a soporte:',
                      style: AppTextStyles.body2.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'soporte@uniride.app',
                      style: AppTextStyles.body2.copyWith(
                        color: Colors.white,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimensions.spacingL),

              const Spacer(),

              // Botón intentar de nuevo
              CustomButton(
                text: 'Intentar de nuevo',
                onPressed: () => context.go('/register/step1'),
                isPrimary: false,
              ),
              const SizedBox(height: AppDimensions.spacingM),

              // Botón volver
              TextButton(
                onPressed: () => context.go('/welcome'),
                child: Text(
                  'Volver al inicio',
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
    );
  }

  /// Estado: Error de red
  Widget _buildNetworkErrorState(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warning,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icono de sin conexión
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off,
                  size: 80,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXL),

              // Título
              Text(
                'Sin conexión',
                style: AppTextStyles.h1.copyWith(
                  color: Colors.white,
                  fontSize: 32,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.spacingM),

              // Mensaje
              Text(
                'No pudimos completar tu registro porque no hay conexión a internet. Verifica tu conexión y vuelve a intentarlo.',
                style: AppTextStyles.body1.copyWith(
                  color: Colors.white.withOpacity(0.9),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.spacingXL),

              // Consejos
              Container(
                padding: const EdgeInsets.all(AppDimensions.paddingM),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius:
                      BorderRadius.circular(AppDimensions.borderRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verifica que:',
                      style: AppTextStyles.body2.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildCheckItem('WiFi o datos móviles estén activados'),
                    _buildCheckItem('Tengas buena señal'),
                    _buildCheckItem('No estés en modo avión'),
                  ],
                ),
              ),
              const SizedBox(height: AppDimensions.spacingL),

              const Spacer(),

              // Botón reintentar
              CustomButton(
                text: 'Reintentar',
                onPressed: () => context.go('/register/step1'),
                isPrimary: false,
              ),
              const SizedBox(height: AppDimensions.spacingM),

              // Botón volver
              TextButton(
                onPressed: () => context.go('/welcome'),
                child: Text(
                  'Volver al inicio',
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
    );
  }

  /// Item de checklist
  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.check,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body2.copyWith(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Obtener mensaje de éxito según rol
  String _getSuccessMessage() {
    if (role == 'pasajero') {
      return 'Tu cuenta de pasajero está lista. Ya puedes buscar y reservar viajes compartidos con otros estudiantes de UIDE.';
    } else if (role == 'conductor' && hasVehicle) {
      return 'Tu cuenta de conductor ha sido creada. Una vez que verifiquemos tu vehículo, podrás empezar a ofrecer viajes.';
    } else if (role == 'ambos' && hasVehicle) {
      return 'Tu cuenta dual está lista. Podrás buscar viajes como pasajero de inmediato. Como conductor, podrás ofrecer viajes una vez que verifiquemos tu vehículo.';
    } else {
      return 'Tu cuenta ha sido creada exitosamente. Bienvenido a UniRide.';
    }
  }
}
