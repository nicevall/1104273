import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/common/loading_indicator.dart';

/// Pantalla de inicio (Splash)
/// Verifica estado de autenticación y navega a pantalla correspondiente
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Verificar estado de autenticación al iniciar
    context.read<AuthBloc>().add(const CheckAuthStatusEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          // Navegar según el estado de autenticación
          if (state is Authenticated) {
            final user = state.user;

            // Si es conductor puro (no "ambos") y no tiene vehículo,
            // redirigir al registro de vehículo obligatorio
            if (user.role == 'conductor' && !user.hasVehicle) {
              context.go('/vehicle/register', extra: {
                'userId': user.userId,
                'role': user.role,
              });
              return;
            }

            // Usuario autenticado → ir a home con datos del usuario
            context.go('/home', extra: {
              'userId': user.userId,
              'userRole': user.role,
              'hasVehicle': user.hasVehicle,
            });
          } else if (state is AuthenticatedNotVerified) {
            // Usuario no verificado → ir a verificación OTP
            context.go('/register/step2', extra: {
              'userId': state.userId,
              'email': state.email,
            });
          } else if (state is Unauthenticated) {
            // No autenticado → ir a welcome
            context.go('/welcome');
          } else if (state is AuthError) {
            // Error → ir a welcome
            context.go('/welcome');
          }
        },
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo de UniRide
              _buildLogo(),
              const SizedBox(height: 48),

              // Indicador de carga
              const LoadingIndicator(
                color: Colors.white,
              ),
              const SizedBox(height: 16),

              // Texto de carga
              Text(
                'Cargando...',
                style: AppTextStyles.body2.copyWith(
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Logo de UniRide
  Widget _buildLogo() {
    return Column(
      children: [
        // Icono temporal (reemplazar con logo real)
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.directions_car,
              size: 64,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Nombre de la app
        Text(
          'UniRide',
          style: AppTextStyles.h1.copyWith(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),

        // Slogan
        Text(
          'Comparte tu viaje',
          style: AppTextStyles.body1.copyWith(
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }
}
