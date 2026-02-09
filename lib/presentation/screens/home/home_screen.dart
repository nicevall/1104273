// lib/presentation/screens/home/home_screen.dart
// Pantalla Home principal - Estilo Uber
// Muestra búsqueda, historial reciente y destinos frecuentes

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/trips_service.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../blocs/trip/trip_event.dart';
import '../../blocs/trip/trip_state.dart';
import '../../widgets/home/role_switcher.dart';
import '../../widgets/home/search_bar_widget.dart';
import '../../widgets/home/recent_place_card.dart';
import '../../widgets/home/location_permission_banner.dart';
import '../../widgets/driver/trip_type_options.dart';
import '../../widgets/driver/vehicle_info_card.dart';
import '../../widgets/driver/upcoming_trip_card.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String userRole; // 'pasajero', 'conductor', 'ambos'
  final bool hasVehicle; // true si tiene vehículo registrado
  final String? activeRole; // Rol activo inicial (para mantener contexto)

  const HomeScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.hasVehicle = false,
    this.activeRole,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Rol activo actual (para usuarios con rol "ambos")
  late String _activeRole;

  // Lista de lugares recientes (se cargará desde Firebase cuando haya historial)
  // Por ahora está vacía - solo se mostrará cuando el usuario tenga historial real
  final List<RecentPlace> _recentPlaces = [];

  // Key para refrescar el banner de ubicación
  final GlobalKey<State> _locationBannerKey = GlobalKey();

  // Flag para evitar doble redirect
  bool _hasCheckedActiveTrip = false;

  @override
  void initState() {
    super.initState();
    // Si se proporcionó un activeRole, usarlo; sino, usar la lógica por defecto
    if (widget.activeRole != null &&
        (widget.activeRole == 'conductor' || widget.activeRole == 'pasajero')) {
      // Verificar que el usuario puede usar ese rol
      if (widget.activeRole == 'conductor' && widget.hasVehicle) {
        _activeRole = 'conductor';
      } else if (widget.activeRole == 'pasajero') {
        _activeRole = 'pasajero';
      } else {
        // Fallback: Si es "ambos", inicia como pasajero por defecto
        _activeRole = widget.userRole == 'ambos' ? 'pasajero' : widget.userRole;
      }
    } else {
      // Si es "ambos", inicia como pasajero por defecto
      _activeRole = widget.userRole == 'ambos' ? 'pasajero' : widget.userRole;
    }

    // Cargar viajes si inicia como conductor
    if (_activeRole == 'conductor') {
      _loadDriverTrips();
    }

    // Auto-detectar viaje activo (conductor o pasajero) al abrir la app
    _checkAndRedirectActiveTrip();
  }

  void _loadDriverTrips() {
    context.read<TripBloc>().add(
      LoadDriverTripsEvent(driverId: widget.userId),
    );
  }

  /// Pull-to-refresh para pasajero: recarga estado de ubicación y UI
  Future<void> _refreshPassengerHome() async {
    setState(() {});
    // Pequeño delay para feedback visual del refresh indicator
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Pull-to-refresh para conductor: recarga lista de viajes
  Future<void> _refreshDriverHome() async {
    _loadDriverTrips();
    // Pequeño delay para feedback visual del refresh indicator
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Verifica si el usuario tiene un viaje activo (conductor o pasajero)
  /// y redirige automáticamente a la pantalla correspondiente.
  /// Se ejecuta al abrir la app para retomar el flujo interrumpido.
  Future<void> _checkAndRedirectActiveTrip() async {
    if (_hasCheckedActiveTrip) return;
    _hasCheckedActiveTrip = true;

    try {
      final firestore = FirebaseFirestore.instance;

      // === CONDUCTOR: Buscar viajes activos como conductor ===
      if (widget.hasVehicle) {
        // Query 1: Buscar viaje in_progress (conductor ya manejando)
        final inProgressSnap = await firestore
            .collection('trips')
            .where('driverId', isEqualTo: widget.userId)
            .where('status', isEqualTo: 'in_progress')
            .limit(1)
            .get();

        if (!mounted) return;

        if (inProgressSnap.docs.isNotEmpty) {
          final tripId = inProgressSnap.docs.first.id;
          debugPrint('🔄 Auto-redirect conductor: in_progress → GPS ($tripId)');
          context.go('/driver/active-trip/$tripId');
          return;
        }

        // Query 2: Buscar viaje active (recibiendo solicitudes)
        final activeSnap = await firestore
            .collection('trips')
            .where('driverId', isEqualTo: widget.userId)
            .where('status', isEqualTo: 'active')
            .limit(1)
            .get();

        if (!mounted) return;

        if (activeSnap.docs.isNotEmpty) {
          final tripId = activeSnap.docs.first.id;
          debugPrint('🔄 Auto-redirect conductor: active → solicitudes ($tripId)');
          context.go('/driver/active-requests/$tripId');
          return;
        }
      }

      // === PASAJERO: Buscar si ya está como pasajero picked_up en un viaje activo ===
      // Query 2.5: Buscar viajes in_progress donde este usuario sea pasajero picked_up
      // (caso: app fue matada mientras pasajero estaba en viaje con taxímetro corriendo)
      final inProgressTripsSnap = await firestore
          .collection('trips')
          .where('status', isEqualTo: 'in_progress')
          .get();

      if (!mounted) return;

      for (final tripDoc in inProgressTripsSnap.docs) {
        final tripData = tripDoc.data();
        final passengers = tripData['passengers'] as List<dynamic>? ?? [];
        for (final p in passengers) {
          final pMap = p as Map<String, dynamic>;
          if (pMap['userId'] == widget.userId &&
              (pMap['status'] == 'picked_up' || pMap['status'] == 'accepted')) {
            final destination = tripData['destination'] as Map<String, dynamic>?;
            final pickupPoint = pMap['pickupPoint'] as Map<String, dynamic>?;

            if (destination != null && pickupPoint != null) {
              debugPrint('🔄 Auto-redirect pasajero: ${pMap['status']} en viaje in_progress (${tripDoc.id})');
              context.go('/trip/tracking', extra: {
                'tripId': tripDoc.id,
                'userId': widget.userId,
                'pickupPoint': TripLocation.fromJson(pickupPoint),
                'destination': TripLocation.fromJson(destination),
              });
              return;
            }
          }
        }
      }

      // === PASAJERO: Buscar solicitudes activas como pasajero ===
      // Query 3: Buscar ride_request con status 'accepted' (pasajero aceptado por un conductor)
      final acceptedReqSnap = await firestore
          .collection('ride_requests')
          .where('passengerId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();

      if (!mounted) return;

      if (acceptedReqSnap.docs.isNotEmpty) {
        final reqDoc = acceptedReqSnap.docs.first;
        final reqData = reqDoc.data();
        final tripId = reqData['tripId'] as String?;
        if (tripId != null && tripId.isNotEmpty) {
          // Obtener datos del viaje para la pantalla de tracking
          final tripDoc = await firestore.collection('trips').doc(tripId).get();
          if (tripDoc.exists && mounted) {
            final tripData = tripDoc.data()!;
            final tripStatus = tripData['status'] as String? ?? '';

            // Si el viaje fue cancelado o completado, limpiar la solicitud y NO redirigir
            if (tripStatus == 'cancelled' || tripStatus == 'completed') {
              debugPrint('🔄 Auto-redirect pasajero: viaje $tripStatus — limpiando ride_request');
              await reqDoc.reference.update({'status': tripStatus == 'cancelled' ? 'cancelled' : 'completed'});

              // Si fue cancelado, ir directo a pantalla de reseñas
              if (tripStatus == 'cancelled' && mounted) {
                final driverId = tripData['driverId'] as String? ?? '';
                context.go('/trip/rate', extra: {
                  'tripId': tripId,
                  'passengerId': widget.userId,
                  'driverId': driverId,
                  'ratingContext': 'cancelled',
                });
                return;
              }
              // Si fue completado, seguir al home normal
            } else {
              final destination = tripData['destination'] as Map<String, dynamic>?;
              final pickupPoint = reqData['pickupPoint'] as Map<String, dynamic>?;

              if (destination != null && pickupPoint != null) {
                debugPrint('🔄 Auto-redirect pasajero: accepted → tracking ($tripId)');
                context.go('/trip/tracking', extra: {
                  'tripId': tripId,
                  'userId': widget.userId,
                  'pickupPoint': TripLocation.fromJson(pickupPoint),
                  'destination': TripLocation.fromJson(destination),
                });
                return;
              }
            }
          }
        }
      }

      // Query 4: Buscar ride_request con status 'searching' (pasajero esperando)
      final searchingReqSnap = await firestore
          .collection('ride_requests')
          .where('passengerId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'searching')
          .limit(1)
          .get();

      if (!mounted) return;

      if (searchingReqSnap.docs.isNotEmpty) {
        debugPrint('🔄 Auto-redirect pasajero: searching → pantalla principal (aún buscando)');
        // No redirigir al waiting screen porque necesita datos extra que no tenemos aquí
        // El pasajero verá la home y podrá buscar de nuevo
      }

      debugPrint('🔄 Auto-redirect: no hay viajes activos');
    } catch (e) {
      debugPrint('❌ Error checking active trip: $e');
    }
  }

  /// Maneja el tap en "Viaje Instantáneo"
  /// Verifica si ya existe uno activo y redirige apropiadamente
  Future<void> _handleInstantTripTap() async {
    // Verificar si ya hay un viaje instantáneo activo
    final activeTrip = await TripsService().getActiveInstantTrip(widget.userId);

    if (!mounted) return;

    if (activeTrip != null) {
      // Ya tiene un viaje activo, ir a la pantalla de viaje activo
      context.push('/driver/active-trip/${activeTrip.tripId}');
    } else {
      // No tiene viaje activo, crear uno nuevo
      context.push('/driver/instant-trip', extra: {
        'userId': widget.userId,
      });
    }
  }

  void _onRoleChanged(String newRole) {
    // Si intenta cambiar a conductor y no tiene vehículo, mostrar aviso
    if (newRole == 'conductor' && !widget.hasVehicle) {
      _showVehicleRequiredDialog();
      return;
    }
    setState(() {
      _activeRole = newRole;
    });
    // Cargar viajes al cambiar a conductor
    if (newRole == 'conductor') {
      _loadDriverTrips();
    }
  }

  void _showVehicleRequiredDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.directions_car, color: AppColors.primary),
            const SizedBox(width: 12),
            const Text('Vehículo requerido'),
          ],
        ),
        content: const Text(
          'Para usar el modo conductor necesitas registrar tu vehículo primero.\n\n'
          '¿Deseas registrar tu vehículo ahora?',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              // Botón Más tarde - outline gris
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Más tarde',
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Botón Registrar vehículo - turquesa sólido
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    context.push('/vehicle/register', extra: {
                      'userId': widget.userId,
                      'role': widget.userRole,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Registrar',
                    style: AppTextStyles.button.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onSearchTap() {
    // Navegar a la pantalla de planificación de viaje
    context.push('/trip/plan', extra: {
      'userId': widget.userId,
      'userRole': _activeRole,
    });
  }

  void _onScheduleLater() {
    // TODO: Implementar programación de viaje
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Programar viaje - Próximamente'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _onRecentPlaceTap(RecentPlace place) {
    // Navegar directamente al mapa con este destino
    context.push('/trip/plan', extra: {
      'userId': widget.userId,
      'userRole': _activeRole,
      'destination': {
        'name': place.name,
        'address': place.address,
        'latitude': place.latitude,
        'longitude': place.longitude,
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _activeRole == 'pasajero'
            ? _buildPassengerHome()
            : _buildDriverHome(),
      ),
    );
  }

  Widget _buildPassengerHome() {
    return RefreshIndicator(
      onRefresh: _refreshPassengerHome,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner de ubicación desactivada (estilo Uber)
            LocationPermissionBanner(
            key: _locationBannerKey,
            onPermissionGranted: () {
              // Refrescar la pantalla cuando se otorga el permiso
              setState(() {});
            },
          ),

          // Header con logo y avatar
          _buildHeader(),

          const SizedBox(height: 16),

          // Toggle de rol (solo si es "ambos")
          if (widget.userRole == 'ambos')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: RoleSwitcher(
                activeRole: _activeRole,
                onRoleChanged: _onRoleChanged,
              ),
            ),

          const SizedBox(height: 24),

          // Barra de búsqueda estilo Uber
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SearchBarWidget(
              onTap: _onSearchTap,
              onScheduleLater: _onScheduleLater,
            ),
          ),

          const SizedBox(height: 24),

          // Lugares recientes (solo si hay historial real)
          if (_recentPlaces.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentPlaces.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return RecentPlaceCard(
                    place: _recentPlaces[index],
                    onTap: () => _onRecentPlaceTap(_recentPlaces[index]),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Mensaje cuando no hay historial
          if (_recentPlaces.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.tertiary.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.explore_outlined,
                      color: AppColors.textSecondary,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sin viajes recientes',
                            style: AppTextStyles.body1.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tus destinos frecuentes aparecerán aquí',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverHome() {
    return RefreshIndicator(
      onRefresh: _refreshDriverHome,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con logo y avatar
            _buildHeader(),

          const SizedBox(height: 16),

          // Toggle de rol (solo si es "ambos")
          if (widget.userRole == 'ambos')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: RoleSwitcher(
                activeRole: _activeRole,
                onRoleChanged: _onRoleChanged,
              ),
            ),

          const SizedBox(height: 24),

          // Opciones de tipo de viaje: Instantáneo y Planificado
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TripTypeOptions(
              onInstantTap: () => _handleInstantTripTap(),
              onScheduledTap: () {
                context.push('/driver/create-trip/form', extra: {
                  'userId': widget.userId,
                });
              },
            ),
          ),

          const SizedBox(height: 20),

          // Info del vehículo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FutureBuilder<VehicleModel?>(
              future: FirestoreService().getUserVehicle(widget.userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }
                if (snapshot.hasData && snapshot.data != null) {
                  return VehicleInfoCard(vehicle: snapshot.data!);
                }
                return const SizedBox.shrink();
              },
            ),
          ),

          const SizedBox(height: 24),

          // Sección "Mis viajes programados"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Mis viajes',
              style: AppTextStyles.h3,
            ),
          ),

          const SizedBox(height: 12),

          // Lista de viajes (con auto-refresh tras cambios de estado)
          BlocListener<TripBloc, TripState>(
            listenWhen: (prev, curr) =>
                curr is TripStarted ||
                curr is TripCompleted ||
                curr is TripCancelled ||
                curr is TripCreated,
            listener: (context, state) {
              // Re-cargar viajes cuando cambia el estado de algún viaje
              _loadDriverTrips();
            },
            child: BlocBuilder<TripBloc, TripState>(
              buildWhen: (prev, curr) =>
                  curr is TripLoading ||
                  curr is DriverTripsLoaded ||
                  curr is TripError ||
                  curr is TripInitial,
              builder: (context, state) {
                if (state is TripLoading) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  );
                }

                if (state is DriverTripsLoaded) {
                  final trips = state.trips;

                  if (trips.isEmpty) {
                    return _buildEmptyTripsState();
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: trips.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final trip = trips[index];
                            return UpcomingTripCard(
                              trip: trip,
                              onTap: () {
                                if (trip.isInProgress) {
                                  // Viaje en progreso → GPS screen
                                  context.go(
                                    '/driver/active-trip/${trip.tripId}',
                                  );
                                } else if (trip.isActive) {
                                  // Buscando pasajeros → pantalla de solicitudes
                                  context.go(
                                    '/driver/active-requests/${trip.tripId}',
                                  );
                                } else {
                                  context.push(
                                    '/driver/trip/${trip.tripId}',
                                  );
                                }
                              },
                            );
                          },
                        ),
                        // TODO: Quitar este botón después del desarrollo
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Eliminar viajes'),
                                content: Text(
                                  '¿Eliminar los ${trips.length} viajes? Esta acción no se puede deshacer.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancelar'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.error,
                                    ),
                                    child: const Text('Eliminar'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              final count = await TripsService()
                                  .deleteAllDriverTrips(widget.userId);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('$count viajes eliminados'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                                _loadDriverTrips();
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_sweep, size: 16),
                          label: const Text('Eliminar todos'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (state is TripError) {
                  // Si el error es de índice o Firestore, mostrar empty state
                  if (state.error.contains('index') ||
                      state.error.contains('FAILED_PRECONDITION')) {
                    return _buildEmptyTripsState();
                  }
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'No se pudieron cargar los viajes',
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }

                // Estado inicial - mostrar empty state
                return _buildEmptyTripsState();
              },
            ),
          ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTripsState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.tertiary.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              Icons.route_outlined,
              color: AppColors.textSecondary,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No tienes viajes programados',
              style: AppTextStyles.body1.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Crea tu primer viaje y empieza a compartir gastos',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo UniRide
          Text(
            'UniRide',
            style: AppTextStyles.h1.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),

          // Avatar del usuario - Navega al perfil
          GestureDetector(
            onTap: () {
              context.push('/profile', extra: {
                'userId': widget.userId,
              });
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.tertiary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.divider,
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.person,
                color: AppColors.textSecondary,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modelo para lugares recientes
class RecentPlace {
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final IconData icon;

  RecentPlace({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.icon = Icons.access_time,
  });
}
