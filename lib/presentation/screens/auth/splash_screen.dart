import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/services/location_cache_service.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/common/loading_indicator.dart';

/// Pantalla de inicio (Splash)
/// Verifica estado de autenticación y navega a pantalla correspondiente
/// Para usuarios autenticados con permisos de ubicación:
/// 1. Pre-carga la ubicación GPS
/// 2. Pre-carga el SDK de Google Maps con los tiles de la zona del usuario
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Estado de carga para mostrar mensajes apropiados
  String _loadingMessage = 'Cargando...';
  bool _isLoadingLocation = false;

  // Para pre-cargar el mapa
  bool _shouldPreloadMap = false;
  LatLng? _userLocation;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    // Verificar estado de autenticación al iniciar
    context.read<AuthBloc>().add(const CheckAuthStatusEvent());
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  /// Verifica si el usuario tiene permisos de ubicación Y el GPS está activo
  Future<bool> _hasLocationPermissionAndService() async {
    try {
      // Verificar permiso
      final permissionStatus = await Permission.location.status;
      if (!permissionStatus.isGranted) {
        return false;
      }

      // Verificar si el GPS está habilitado
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      return serviceEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Carga la ubicación, pre-carga el mapa y navega al home
  Future<void> _loadLocationAndNavigate(Authenticated state) async {
    final user = state.user;

    // Si es conductor puro (no "ambos") y no tiene vehículo,
    // redirigir al registro de vehículo obligatorio (sin esperar ubicación)
    if (user.role == 'conductor' && !user.hasVehicle) {
      if (mounted) {
        context.go('/vehicle/register', extra: {
          'userId': user.userId,
          'role': user.role,
        });
      }
      return;
    }

    // Verificar si tiene permisos y GPS activo
    final hasLocationAccess = await _hasLocationPermissionAndService();

    if (hasLocationAccess) {
      // Tiene permisos y GPS → cargar ubicación antes de navegar
      if (mounted) {
        setState(() {
          _isLoadingLocation = true;
          _loadingMessage = 'Obteniendo tu ubicación...';
        });
      }

      // Esperar a que se cargue la ubicación (con timeout de 10 segundos)
      CachedLocation? location;
      try {
        location = await LocationCacheService()
            .getLocation()
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // Si falla o timeout, continuar de todos modos
      }

      // Si obtuvimos ubicación, pre-cargar el mapa
      if (location != null && mounted) {
        setState(() {
          _loadingMessage = 'Preparando el mapa...';
          _userLocation = LatLng(location!.latitude, location.longitude);
          _shouldPreloadMap = true;
        });

        // Esperar un poco para que el mapa se inicialice y cargue tiles
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    } else {
      // No tiene permisos o GPS apagado → iniciar en background y continuar
      LocationCacheService().initializeLocation();
    }

    // Navegar al home
    if (mounted) {
      context.go('/home', extra: {
        'userId': user.userId,
        'userRole': user.role,
        'hasVehicle': user.hasVehicle,
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) async {
          // Navegar según el estado de autenticación
          if (state is Authenticated) {
            // Para usuarios autenticados, intentar cargar ubicación primero
            await _loadLocationAndNavigate(state);
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
        child: Stack(
          children: [
            // Mapa invisible para pre-cargar el SDK y tiles de la zona del usuario
            if (_shouldPreloadMap && _userLocation != null)
              Positioned(
                top: -100,
                left: -100,
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _userLocation!,
                          zoom: 15, // Zoom típico para ver calles
                        ),
                        onMapCreated: _onMapCreated,
                        // Deshabilitar todas las interacciones
                        zoomControlsEnabled: false,
                        zoomGesturesEnabled: false,
                        scrollGesturesEnabled: false,
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        myLocationButtonEnabled: false,
                        myLocationEnabled: false,
                        compassEnabled: false,
                        mapToolbarEnabled: false,
                        liteModeEnabled: false,
                      ),
                    ),
                  ),
                ),
              ),

            // Contenido del splash
            Center(
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

                  // Texto de carga (dinámico)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _loadingMessage,
                      key: ValueKey(_loadingMessage),
                      style: AppTextStyles.body2.copyWith(
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ),

                  // Indicador adicional cuando carga ubicación
                  if (_isLoadingLocation) ...[
                    const SizedBox(height: 8),
                    Icon(
                      Icons.location_on,
                      color: Colors.white.withOpacity(0.6),
                      size: 20,
                    ),
                  ],
                ],
              ),
            ),
          ],
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
