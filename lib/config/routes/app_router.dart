import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/trip_model.dart';
import '../../presentation/screens/auth/splash_screen.dart';
import '../../presentation/screens/auth/welcome_screen.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/forgot_password_screen.dart';
import '../../presentation/screens/auth/register_step1_screen.dart';
import '../../presentation/screens/auth/register_step2_screen.dart';
import '../../presentation/screens/auth/register_step3_screen.dart';
import '../../presentation/screens/auth/register_step4_screen.dart';
import '../../presentation/screens/auth/register_step5_screen.dart';
import '../../presentation/screens/auth/register_vehicle_screen.dart';
import '../../presentation/screens/auth/registration_status_screen.dart';
import '../../presentation/screens/vehicle/vehicle_questions_screen.dart';
import '../../presentation/screens/vehicle/vehicle_matricula_screen.dart';
import '../../presentation/screens/vehicle/vehicle_license_screen.dart';
import '../../presentation/screens/vehicle/vehicle_photo_screen.dart';
import '../../presentation/screens/vehicle/vehicle_summary_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/home/activity_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/trip/plan_trip_screen.dart';
import '../../presentation/screens/trip/map_route_screen.dart';
import '../../presentation/screens/trip/trip_preferences_screen.dart';
import '../../presentation/screens/trip/confirm_pickup_screen.dart';
import '../../presentation/screens/trip/pick_location_screen.dart';
import '../../presentation/screens/trip/searching_drivers_screen.dart';
import '../../presentation/screens/trip/trip_results_screen.dart';
import '../../presentation/screens/driver/instant_trip_screen.dart';
import '../../presentation/screens/driver/driver_active_requests_screen.dart';
import '../../presentation/screens/driver/passenger_request_detail_screen.dart';
import '../../presentation/screens/driver/accept_passenger_screen.dart';
import '../../presentation/screens/driver/driver_active_trip_screen.dart';
import '../../presentation/screens/trip/passenger_waiting_screen.dart';
import '../../presentation/screens/trip/passenger_tracking_screen.dart';
import '../../presentation/screens/trip/rate_driver_screen.dart';

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
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return LoginScreen(
          prefillEmail: extra?['prefillEmail'] as String?,
        );
      },
    ),

    // Forgot Password Screen
    GoRoute(
      path: '/forgot-password',
      name: 'forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
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

    // ==================== VEHICLE REGISTRATION FLOW ====================

    // Vehicle Questions (Step 1)
    GoRoute(
      path: '/register/vehicle/questions',
      name: 'register-vehicle-questions',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return VehicleQuestionsScreen(
          userId: extra?['userId'] as String? ?? '',
          role: extra?['role'] as String? ?? 'conductor',
        );
      },
    ),

    // Vehicle Matricula (Step 2)
    GoRoute(
      path: '/register/vehicle/matricula',
      name: 'register-vehicle-matricula',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return VehicleMatriculaScreen(
          userId: extra?['userId'] as String? ?? '',
          role: extra?['role'] as String? ?? 'conductor',
          vehicleOwnership: extra?['vehicleOwnership'] as String? ?? '',
          driverRelation: extra?['driverRelation'] as String? ?? '',
        );
      },
    ),

    // Vehicle License (Step 3)
    GoRoute(
      path: '/register/vehicle/license',
      name: 'register-vehicle-license',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return VehicleLicenseScreen(
          userId: extra?['userId'] as String? ?? '',
          role: extra?['role'] as String? ?? 'conductor',
          vehicleOwnership: extra?['vehicleOwnership'] as String? ?? '',
          driverRelation: extra?['driverRelation'] as String? ?? '',
          matriculaPhotoPath: extra?['matriculaPhoto'] as String? ?? '',
          vehicleData: (extra?['vehicleData'] as Map<String, String>?) ?? {},
        );
      },
    ),

    // Vehicle Photo (Step 4)
    GoRoute(
      path: '/register/vehicle/photo',
      name: 'register-vehicle-photo',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return VehiclePhotoScreen(
          userId: extra?['userId'] as String? ?? '',
          role: extra?['role'] as String? ?? 'conductor',
          vehicleOwnership: extra?['vehicleOwnership'] as String? ?? '',
          driverRelation: extra?['driverRelation'] as String? ?? '',
          matriculaPhotoPath: extra?['matriculaPhoto'] as String? ?? '',
          licensePhotoPath: extra?['licensePhoto'] as String? ?? '',
          licenseData: extra?['licenseData'] as Map<String, dynamic>?,
          vehicleData: (extra?['vehicleData'] as Map<String, String>?) ?? {},
        );
      },
    ),

    // Vehicle Summary (Step 5)
    GoRoute(
      path: '/register/vehicle/summary',
      name: 'register-vehicle-summary',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return VehicleSummaryScreen(
          userId: extra?['userId'] as String? ?? '',
          role: extra?['role'] as String? ?? 'conductor',
          vehicleOwnership: extra?['vehicleOwnership'] as String? ?? '',
          driverRelation: extra?['driverRelation'] as String? ?? '',
          matriculaPhotoPath: extra?['matriculaPhoto'] as String? ?? '',
          licensePhotoPath: extra?['licensePhoto'] as String? ?? '',
          licenseData: extra?['licenseData'] as Map<String, dynamic>?,
          vehicleData: (extra?['vehicleData'] as Map<String, String>?) ?? {},
          vehiclePhotoPath: extra?['vehiclePhoto'] as String? ?? '',
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

    // Home Screen (sin bottom navigation)
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return HomeScreen(
          userId: extra?['userId'] as String? ?? '',
          userRole: extra?['userRole'] as String? ?? 'pasajero',
          hasVehicle: extra?['hasVehicle'] as bool? ?? false,
          activeRole: extra?['activeRole'] as String?,
        );
      },
    ),

    // Historial de viajes
    GoRoute(
      path: '/historial',
      name: 'historial',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ActivityScreen(
          userId: extra?['userId'] as String? ?? '',
          activeRole: extra?['activeRole'] as String? ?? 'pasajero',
        );
      },
    ),

    // Profile Screen - Accesible desde el avatar en HomeScreen
    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ProfileScreen(
          userId: extra?['userId'] as String? ?? '',
        );
      },
    ),

    // ==================== VEHICLE REGISTRATION (POST-LOGIN) ====================

    // Vehicle Registration Entry - Redirige al flujo de registro de vehículo
    GoRoute(
      path: '/vehicle/register',
      name: 'vehicle-register',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return VehicleQuestionsScreen(
          userId: extra?['userId'] as String? ?? '',
          role: extra?['role'] as String? ?? 'conductor',
          isPostLogin: true,
        );
      },
    ),

    // ==================== TRIP ROUTES (FASE 2) ====================

    // Plan Trip Screen - Buscar destino
    GoRoute(
      path: '/trip/plan',
      name: 'trip-plan',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return PlanTripScreen(
          userId: extra?['userId'] as String? ?? '',
          userRole: extra?['userRole'] as String? ?? 'pasajero',
          preselectedDestination: extra?['destination'] as Map<String, dynamic>?,
        );
      },
    ),

    // Map Route Screen - Mapa con origen/destino
    GoRoute(
      path: '/trip/map',
      name: 'trip-map',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return MapRouteScreen(
          userId: extra?['userId'] as String? ?? '',
          userRole: extra?['userRole'] as String? ?? 'pasajero',
          origin: extra?['origin'] as Map<String, dynamic>? ?? {},
          destination: extra?['destination'] as Map<String, dynamic>? ?? {},
        );
      },
    ),

    // Pick Location Screen - Elegir ubicación en el mapa
    GoRoute(
      path: '/trip/pick-location',
      name: 'trip-pick-location',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return PickLocationScreen(
          userId: extra?['userId'] as String? ?? '',
          userRole: extra?['userRole'] as String? ?? 'pasajero',
          originLatitude: extra?['originLatitude'] as double? ?? -3.9931,
          originLongitude: extra?['originLongitude'] as double? ?? -79.2042,
          originAddress: extra?['originAddress'] as String? ?? '',
        );
      },
    ),

    // Trip Preferences Screen - Detalles de recogida
    GoRoute(
      path: '/trip/preferences',
      name: 'trip-preferences',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return TripPreferencesScreen(
          userId: extra?['userId'] as String? ?? '',
          currentPreference: extra?['currentPreference'] as String?,
          currentDescription: extra?['currentDescription'] as String?,
        );
      },
    ),

    // Confirm Pickup Screen - Confirmar punto de recogida
    GoRoute(
      path: '/trip/confirm-pickup',
      name: 'trip-confirm-pickup',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ConfirmPickupScreen(
          userId: extra?['userId'] as String? ?? '',
          userRole: extra?['userRole'] as String? ?? 'pasajero',
          origin: extra?['origin'] as Map<String, dynamic>? ?? {},
          destination: extra?['destination'] as Map<String, dynamic>? ?? {},
          preference: extra?['preference'] as String? ?? 'mochila',
          preferenceDescription: extra?['preferenceDescription'] as String? ?? '',
          petType: extra?['petType'] as String?,
          petSize: extra?['petSize'] as String?,
          petDescription: extra?['petDescription'] as String?,
          paymentMethod: extra?['paymentMethod'] as String? ?? 'Efectivo',
        );
      },
    ),

    // Searching Drivers Screen - Pantalla de búsqueda de conductores
    GoRoute(
      path: '/trip/search-results',
      name: 'trip-search-results',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return SearchingDriversScreen(
          userId: extra?['userId'] as String? ?? '',
          userRole: extra?['userRole'] as String? ?? 'pasajero',
          origin: extra?['origin'] as Map<String, dynamic>? ?? {},
          destination: extra?['destination'] as Map<String, dynamic>? ?? {},
          pickupLocation: extra?['pickupLocation'] as Map<String, dynamic>? ?? {},
          preference: extra?['preference'] as String? ?? 'mochila',
          preferenceDescription: extra?['preferenceDescription'] as String? ?? '',
          paymentMethod: extra?['paymentMethod'] as String? ?? 'Efectivo',
        );
      },
    ),

    // ==================== DRIVER ROUTES (FASE 2) ====================

    // Instant Trip - Disponibilidad inmediata
    GoRoute(
      path: '/driver/instant-trip',
      name: 'driver-instant-trip',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return InstantTripScreen(
          userId: extra?['userId'] as String? ?? '',
        );
      },
    ),

    // Driver Active Trip - Pantalla principal del viaje activo
    GoRoute(
      path: '/driver/active-trip/:tripId',
      name: 'driver-active-trip',
      builder: (context, state) {
        final tripId = state.pathParameters['tripId'] ?? '';
        return DriverActiveTripScreen(tripId: tripId);
      },
    ),

    // Driver Active Requests - Lista de solicitudes de pasajeros
    GoRoute(
      path: '/driver/active-requests/:tripId',
      name: 'driver-active-requests',
      builder: (context, state) {
        final tripId = state.pathParameters['tripId'] ?? '';
        return DriverActiveRequestsScreen(tripId: tripId);
      },
    ),

    // Passenger Request Detail - Detalle de solicitud de pasajero (legacy)
    GoRoute(
      path: '/driver/request-detail/:tripId/:passengerId',
      name: 'driver-request-detail',
      builder: (context, state) {
        final tripId = state.pathParameters['tripId'] ?? '';
        final passengerId = state.pathParameters['passengerId'] ?? '';
        return PassengerRequestDetailScreen(
          tripId: tripId,
          passengerId: passengerId,
        );
      },
    ),

    // Accept Passenger - Ver y aceptar solicitud de pasajero (nuevo flujo)
    GoRoute(
      path: '/driver/passenger-request/:tripId/:requestId',
      name: 'driver-passenger-request',
      builder: (context, state) {
        final tripId = state.pathParameters['tripId'] ?? '';
        final requestId = state.pathParameters['requestId'] ?? '';
        return AcceptPassengerScreen(
          tripId: tripId,
          requestId: requestId,
        );
      },
    ),

    // Passenger Waiting - Pasajero esperando conductor
    GoRoute(
      path: '/trip/waiting',
      name: 'trip-waiting',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return PassengerWaitingScreen(
          userId: extra?['userId'] as String? ?? '',
          origin: extra?['origin'] as TripLocation,
          destination: extra?['destination'] as TripLocation,
          pickupPoint: extra?['pickupPoint'] as TripLocation,
          referenceNote: extra?['referenceNote'] as String?,
          preferences: (extra?['preferences'] as List<String>?) ?? const ['mochila'],
          objectDescription: extra?['objectDescription'] as String?,
          petType: extra?['petType'] as String?,
          petSize: extra?['petSize'] as String?,
          petDescription: extra?['petDescription'] as String?,
          paymentMethod: extra?['paymentMethod'] as String? ?? 'Efectivo',
        );
      },
    ),

    // Passenger Tracking - Seguimiento en tiempo real del conductor
    GoRoute(
      path: '/trip/tracking',
      name: 'trip-tracking',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return PassengerTrackingScreen(
          tripId: extra?['tripId'] as String? ?? '',
          userId: extra?['userId'] as String? ?? '',
          pickupPoint: extra?['pickupPoint'] as TripLocation,
          destination: extra?['destination'] as TripLocation,
        );
      },
    ),

    // Trip Results - Resultados de búsqueda (pasajero)
    GoRoute(
      path: '/trip/results',
      name: 'trip-results',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return TripResultsScreen(
          trips: extra?['trips'] as List<TripModel>? ?? [],
          userId: extra?['userId'] as String? ?? '',
          pickupPoint: extra?['pickupPoint'] as TripLocation?,
          referenceNote: extra?['referenceNote'] as String?,
          preferences: (extra?['preferences'] as List<String>?) ?? const ['mochila'],
          objectDescription: extra?['objectDescription'] as String?,
          petDescription: extra?['petDescription'] as String?,
        );
      },
    ),

    // Rate Driver - Calificar al conductor
    GoRoute(
      path: '/trip/rate',
      name: 'trip-rate',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return RateDriverScreen(
          tripId: extra?['tripId'] as String? ?? '',
          passengerId: extra?['passengerId'] as String? ?? '',
          driverId: extra?['driverId'] as String? ?? '',
          ratingContext: extra?['ratingContext'] as String? ?? 'completed',
          fare: extra?['fare'] as double?,
        );
      },
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
