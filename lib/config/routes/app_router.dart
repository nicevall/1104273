import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/auth/splash_screen.dart';
import '../../presentation/screens/auth/welcome_screen.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_step1_screen.dart';
import '../../presentation/screens/auth/register_step2_screen.dart';
import '../../presentation/screens/auth/register_step3_screen.dart';
import '../../presentation/screens/auth/register_step4_screen.dart';
import '../../presentation/screens/auth/register_step5_screen.dart';
import '../../presentation/screens/auth/register_vehicle_screen.dart';
import '../../presentation/screens/auth/registration_status_screen.dart';

/// Router de la aplicación con go_router
/// Define todas las rutas y navegación de UniRide
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  debugLogDiagnostics: true,
  routes: [
    // ==================== AUTH ROUTES ====================

    // Splash Screen
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),

    // Welcome Screen
    GoRoute(
      path: '/welcome',
      name: 'welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),

    // Login Screen
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),

    // Registration Flow
    GoRoute(
      path: '/register/step1',
      name: 'register-step1',
      builder: (context, state) => const RegisterStep1Screen(),
    ),

    GoRoute(
      path: '/register/step2',
      name: 'register-step2',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return RegisterStep2Screen(
          userId: extra?['userId'] as String? ?? '',
          email: extra?['email'] as String? ?? '',
        );
      },
    ),

    GoRoute(
      path: '/register/step3',
      name: 'register-step3',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return RegisterStep3Screen(
          userId: extra?['userId'] as String? ?? '',
        );
      },
    ),

    GoRoute(
      path: '/register/step4',
      name: 'register-step4',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return RegisterStep4Screen(
          userId: extra?['userId'] as String? ?? '',
        );
      },
    ),

    GoRoute(
      path: '/register/step5',
      name: 'register-step5',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return RegisterStep5Screen(
          userId: extra?['userId'] as String? ?? '',
          role: extra?['role'] as String? ?? 'pasajero',
        );
      },
    ),

    GoRoute(
      path: '/register/vehicle',
      name: 'register-vehicle',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return RegisterVehicleScreen(
          userId: extra?['userId'] as String? ?? '',
          role: extra?['role'] as String? ?? 'conductor',
        );
      },
    ),

    GoRoute(
      path: '/register/status',
      name: 'register-status',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return RegistrationStatusScreen(
          userId: extra?['userId'] as String? ?? '',
          role: extra?['role'] as String? ?? 'pasajero',
          hasVehicle: extra?['hasVehicle'] as bool? ?? false,
          status: extra?['status'] as String? ?? 'success',
        );
      },
    ),

    // ==================== MAIN APP ROUTES ====================
    // TODO: Implementar en próximas fases

    // Home Screen (temporal)
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (context, state) => const _TempHomeScreen(),
    ),

    // ==================== ERROR HANDLING ====================

    // 404 - Not Found
    GoRoute(
      path: '/not-found',
      name: 'not-found',
      builder: (context, state) => const _NotFoundScreen(),
    ),
  ],

  // Redirect para rutas no encontradas
  redirect: (context, state) {
    // Aquí se puede agregar lógica de protección de rutas
    // Por ejemplo: verificar si el usuario está autenticado
    return null;
  },

  // Manejo de errores de navegación
  errorBuilder: (context, state) => const _NotFoundScreen(),
);

/// Pantalla temporal de home (placeholder)
class _TempHomeScreen extends StatelessWidget {
  const _TempHomeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UniRide - Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.go('/welcome'),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.construction,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            const Text(
              'Pantalla de inicio',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Esta pantalla se implementará en las próximas fases del proyecto.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.go('/welcome'),
              child: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pantalla 404 - No encontrada
class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 80,
              color: Colors.red,
            ),
            const SizedBox(height: 24),
            const Text(
              '404',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Página no encontrada',
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.go('/welcome'),
              child: const Text('Ir al inicio'),
            ),
          ],
        ),
      ),
    );
  }
}
