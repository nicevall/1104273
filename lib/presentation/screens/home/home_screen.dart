// lib/presentation/screens/home/home_screen.dart
// Pantalla Home principal - Estilo Uber
// Muestra búsqueda, historial reciente y destinos frecuentes

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/location_cache_service.dart';
import '../../../data/services/rating_service.dart';
import '../../../data/services/trips_service.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../blocs/trip/trip_event.dart';
import '../../blocs/trip/trip_state.dart';
import '../../widgets/common/map_preloader.dart';
import '../../widgets/home/role_switcher.dart';
import '../../widgets/home/search_bar_widget.dart';
import '../../widgets/home/recent_place_card.dart';
import '../../widgets/home/location_permission_banner.dart';
import '../../widgets/home/notification_permission_banner.dart';
import '../../../data/services/notification_service.dart';
import '../../widgets/driver/trip_type_options.dart';

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

  // Lista de lugares recientes (cargados desde Firestore)
  List<RecentPlace> _recentPlaces = [];

  // Key para refrescar el banner de ubicación
  final GlobalKey<State> _locationBannerKey = GlobalKey();

  // Flag para evitar doble redirect
  bool _hasCheckedActiveTrip = false;

  // Flag para evitar doble navegación (múltiples taps)
  bool _isNavigating = false;

  static const String _activeRolePrefKey = 'uniride_active_role';

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
        _activeRole = widget.userRole == 'ambos' ? 'pasajero' : widget.userRole;
      }
    } else {
      // Valor temporal hasta que se cargue de SharedPreferences
      _activeRole = widget.userRole == 'ambos' ? 'pasajero' : widget.userRole;
    }

    // Si es "ambos" y no viene activeRole explícito, restaurar rol guardado
    if (widget.userRole == 'ambos' && widget.activeRole == null) {
      _loadSavedRole();
    }

    // Cargar viajes si inicia como conductor
    if (_activeRole == 'conductor') {
      _loadDriverTrips();
    }

    // Verificar si el usuario está baneado o bloqueado
    _checkBanStatus();

    // Auto-detectar viaje activo (conductor o pasajero) al abrir la app
    _checkAndRedirectActiveTrip();

    // Solicitar permiso de notificaciones (Android 13+, solo una vez)
    NotificationService().requestPermissionIfNeeded();

    // Cargar destinos recientes del pasajero desde Firestore
    _loadRecentPlaces();
  }

  /// Carga el último rol seleccionado desde SharedPreferences
  Future<void> _loadSavedRole() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRole = prefs.getString(_activeRolePrefKey);
    if (savedRole != null && mounted) {
      // Validar que el rol guardado es válido
      if (savedRole == 'conductor' && widget.hasVehicle) {
        setState(() => _activeRole = 'conductor');
        _loadDriverTrips();
      } else if (savedRole == 'pasajero') {
        setState(() => _activeRole = 'pasajero');
      }
    }
  }

  /// Persiste el rol activo en SharedPreferences
  Future<void> _saveActiveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeRolePrefKey, role);
  }

  void _loadDriverTrips() {
    context.read<TripBloc>().add(
      LoadDriverTripsEvent(driverId: widget.userId),
    );
  }

  /// Pull-to-refresh para pasajero: recarga estado de ubicación y recientes
  Future<void> _refreshPassengerHome() async {
    await _loadRecentPlaces();
    setState(() {});
    // Pequeño delay para feedback visual del refresh indicator
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Carga destinos recientes del pasajero desde Firestore
  Future<void> _loadRecentPlaces() async {
    try {
      final destinations = await TripsService()
          .getRecentPassengerDestinations(widget.userId, limit: 5);
      if (mounted && destinations.isNotEmpty) {
        setState(() {
          _recentPlaces = destinations
              .map((d) => RecentPlace(
                    name: d['name'] as String? ?? '',
                    address: d['address'] as String? ?? '',
                    latitude: (d['latitude'] as num?)?.toDouble() ?? 0,
                    longitude: (d['longitude'] as num?)?.toDouble() ?? 0,
                  ))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error cargando destinos recientes: $e');
    }
  }

  /// Pull-to-refresh para conductor: recarga lista de viajes
  Future<void> _refreshDriverHome() async {
    _loadDriverTrips();
    // Pequeño delay para feedback visual del refresh indicator
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Verifica si el usuario está baneado o bloqueado permanentemente
  Future<void> _checkBanStatus() async {
    try {
      final user = await FirestoreService().getUser(widget.userId);
      if (user == null || !mounted) return;

      // ── Cuenta bloqueada permanentemente (3 strikes) ──
      if (user.accountBlocked) {
        _showBanDialog(
          isPermanent: true,
          strikes: user.paymentStrikes,
        );
        return;
      }

      // ── Suspensión temporal ──
      if (user.bannedUntil != null) {
        if (user.bannedUntil!.isAfter(DateTime.now())) {
          // Todavía baneado
          _showBanDialog(
            isPermanent: false,
            strikes: user.paymentStrikes,
            bannedUntil: user.bannedUntil,
          );
        } else {
          // Ban ya expiró → limpiar en Firestore
          await FirestoreService().updateUserFields(widget.userId, {
            'bannedUntil': null,
          });
        }
      }
    } catch (e) {
      debugPrint('Error al verificar ban: $e');
    }
  }

  /// Muestra un diálogo de ban/suspensión que no se puede cerrar
  void _showBanDialog({
    required bool isPermanent,
    required int strikes,
    DateTime? bannedUntil,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icono
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPermanent ? Icons.block : Icons.timer_off_rounded,
                  color: AppColors.error,
                  size: 32,
                ),
              ),
              const SizedBox(height: 12),

              // Título
              Text(
                isPermanent ? 'Cuenta bloqueada' : 'Cuenta suspendida',
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),

              // Mensaje
              Text(
                isPermanent
                    ? 'Tu cuenta ha sido bloqueada permanentemente por múltiples faltas de pago (Strike $strikes/3).\n\nContacta a soporte para más información.'
                    : 'Tu cuenta está suspendida hasta el ${DateFormat('d MMM yyyy, HH:mm', 'es').format(bannedUntil!)} por falta de pago.\n\nStrike $strikes/3.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.read<AuthBloc>().add(const LogoutEvent());
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text(
                  'Cerrar sesión',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

      // Query 4: Buscar ride_request con status 'searching' o 'reviewing' (pasajero esperando)
      final searchingReqSnap = await firestore
          .collection('ride_requests')
          .where('passengerId', isEqualTo: widget.userId)
          .where('status', whereIn: ['searching', 'reviewing'])
          .get();

      if (!mounted) return;

      if (searchingReqSnap.docs.isNotEmpty) {
        // Separar solicitudes vigentes de expiradas
        final now = Timestamp.now();
        DocumentSnapshot? activeReq;

        for (final doc in searchingReqSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final expiresAt = data['expiresAt'] as Timestamp?;

          if (expiresAt != null && expiresAt.compareTo(now) <= 0) {
            // Solicitud expirada → cancelar automáticamente
            debugPrint('🧹 Auto-cancel solicitud expirada: ${doc.id}');
            doc.reference.update({
              'status': 'cancelled',
              'completedAt': Timestamp.now(),
            });
          } else {
            // Solicitud vigente
            activeReq ??= doc;
          }
        }

        if (activeReq != null) {
          final reqData = activeReq.data() as Map<String, dynamic>;
          debugPrint('🔄 Auto-redirect pasajero: ${reqData['status']} → waiting screen');
          context.go('/trip/waiting', extra: {
            'userId': widget.userId,
            'origin': TripLocation.fromJson(reqData['origin'] as Map<String, dynamic>),
            'destination': TripLocation.fromJson(reqData['destination'] as Map<String, dynamic>),
            'pickupPoint': TripLocation.fromJson(reqData['pickupPoint'] as Map<String, dynamic>),
            'referenceNote': reqData['referenceNote'] as String?,
            'preferences': (reqData['preferences'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ?? const ['mochila'],
            'objectDescription': reqData['objectDescription'] as String?,
            'petType': reqData['petType'] as String?,
            'petSize': reqData['petSize'] as String?,
            'petDescription': reqData['petDescription'] as String?,
            'paymentMethod': reqData['paymentMethod'] as String? ?? 'Efectivo',
          });
          return;
        }
      }

      // === RESEÑAS PENDIENTES: Redirigir a calificación si hay viajes sin calificar ===
      final pendingReview = await _findPendingReview();
      if (pendingReview != null && mounted) {
        final route = pendingReview.remove('route') as String? ?? '/trip/rate';
        debugPrint('🔄 Auto-redirect: reseña pendiente → $route');
        context.go(route, extra: pendingReview);
        return;
      }

      debugPrint('🔄 Auto-redirect: no hay viajes activos');

      // Limpiar ride_requests huérfanas del pasajero (viajes que no terminaron bien)
      _cleanupOrphanedRideRequests();
    } catch (e) {
      debugPrint('❌ Error checking active trip: $e');
    }
  }

  /// Buscar reseñas pendientes según el rol activo.
  /// - Pasajero → buscar viajes donde fue dropped_off sin calificar al conductor → /trip/rate
  /// - Conductor → buscar viajes con pasajeros dropped_off sin calificar → /driver/rate-passenger
  /// Retorna {route, extra} o null si no hay pendientes.
  Future<Map<String, dynamic>?> _findPendingReview() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final ratingService = RatingService();

      if (_activeRole == 'pasajero') {
        // === PASAJERO: Buscar viajes donde fue dropped_off sin calificar al conductor ===
        final recentTrips = await firestore
            .collection('trips')
            .where('status', whereIn: ['completed', 'in_progress'])
            .limit(15)
            .get();

        for (final tripDoc in recentTrips.docs) {
          final tripData = tripDoc.data();
          final passengers = tripData['passengers'] as List<dynamic>? ?? [];

          for (final p in passengers) {
            final pMap = p as Map<String, dynamic>;
            final passengerId = pMap['userId'] as String? ?? '';
            if (passengerId != widget.userId) continue;
            if (pMap['status'] != 'dropped_off') continue;

            final hasRated = await ratingService.hasRated(tripDoc.id, widget.userId);
            if (!hasRated) {
              final driverId = tripData['driverId'] as String? ?? '';
              final fare = (pMap['price'] as num?)?.toDouble() ?? (pMap['meterFare'] as num?)?.toDouble();

              debugPrint('⭐ Reseña pendiente (pasajero→conductor): trip=${tripDoc.id}');

              // Limpiar ride_requests activas para que no bloqueen
              final rideReqs = await firestore
                  .collection('ride_requests')
                  .where('passengerId', isEqualTo: widget.userId)
                  .where('status', whereIn: ['searching', 'reviewing', 'accepted'])
                  .get();
              for (final req in rideReqs.docs) {
                await req.reference.update({
                  'status': 'completed',
                  'completedAt': Timestamp.now(),
                });
              }

              return {
                'route': '/trip/rate',
                'tripId': tripDoc.id,
                'passengerId': widget.userId,
                'driverId': driverId,
                'ratingContext': tripData['status'] == 'completed' ? 'completed' : 'cancelled',
                'fare': fare,
              };
            }
          }
        }
      } else {
        // === CONDUCTOR: Buscar viajes con pasajeros dropped_off sin calificar ===
        final recentTrips = await firestore
            .collection('trips')
            .where('driverId', isEqualTo: widget.userId)
            .where('status', whereIn: ['completed', 'in_progress'])
            .limit(15)
            .get();

        for (final tripDoc in recentTrips.docs) {
          final tripData = tripDoc.data();
          final passengers = tripData['passengers'] as List<dynamic>? ?? [];

          for (final p in passengers) {
            final pMap = p as Map<String, dynamic>;
            final passengerId = pMap['userId'] as String? ?? '';
            if (passengerId.isEmpty) continue;
            if (pMap['status'] != 'dropped_off') continue;

            // Verificar si el CONDUCTOR ya calificó a ESTE pasajero en este viaje
            // hasRated busca por tripId + raterId, pero para conductor que califica
            // múltiples pasajeros necesitamos un check más específico
            final existingRating = await firestore
                .collection('ratings')
                .where('tripId', isEqualTo: tripDoc.id)
                .where('raterId', isEqualTo: widget.userId)
                .where('ratedUserId', isEqualTo: passengerId)
                .limit(1)
                .get();

            if (existingRating.docs.isEmpty) {
              final passengerName = pMap['name'] as String? ?? '';
              final fare = (pMap['price'] as num?)?.toDouble() ?? (pMap['meterFare'] as num?)?.toDouble() ?? 0.0;

              debugPrint('⭐ Reseña pendiente (conductor→pasajero): trip=${tripDoc.id}, passenger=$passengerId');

              return {
                'route': '/driver/rate-passenger',
                'tripId': tripDoc.id,
                'driverId': widget.userId,
                'passengerId': passengerId,
                'passengerName': passengerName,
                'fare': fare,
              };
            }
          }
        }
      }

      return null; // No hay reseñas pendientes
    } catch (e) {
      debugPrint('⚠️ Error buscando reseñas pendientes: $e');
      return null;
    }
  }

  /// Limpiar ride_requests que quedaron en status activo sin viaje correspondiente
  /// Y limpiar passengers con userId vacío de trips del conductor
  Future<void> _cleanupOrphanedRideRequests() async {
    try {
      final firestore = FirebaseFirestore.instance;

      // === 1. Limpiar ride_requests huérfanas del pasajero ===
      final activeRequests = await firestore
          .collection('ride_requests')
          .where('passengerId', isEqualTo: widget.userId)
          .where('status', whereIn: ['searching', 'reviewing', 'accepted'])
          .get();

      for (final doc in activeRequests.docs) {
        final data = doc.data();
        final expiresAt = data['expiresAt'] as Timestamp?;
        final tripId = data['tripId'] as String?;

        bool shouldCancel = false;

        // Si ya expiró, cancelar
        if (expiresAt != null && expiresAt.compareTo(Timestamp.now()) <= 0) {
          shouldCancel = true;
        }

        // Si tiene tripId, verificar que el trip siga activo
        if (!shouldCancel && tripId != null && tripId.isNotEmpty) {
          final tripDoc = await firestore.collection('trips').doc(tripId).get();
          if (!tripDoc.exists) {
            shouldCancel = true;
          } else {
            final tripStatus = tripDoc.data()?['status'] as String? ?? '';
            if (tripStatus == 'completed' || tripStatus == 'cancelled') {
              shouldCancel = true;
            }
          }
        }

        if (shouldCancel) {
          await doc.reference.update({
            'status': 'cancelled',
            'completedAt': Timestamp.now(),
          });
          debugPrint('🧹 Limpieza ride_request huérfana: ${doc.id}');
        }
      }

      // === 2. Limpiar passengers con userId vacío de trips del conductor ===
      if (widget.hasVehicle) {
        await _cleanupEmptyPassengersFromTrips();
      }
    } catch (e) {
      debugPrint('⚠️ Error limpiando datos huérfanos: $e');
    }
  }

  /// Elimina passengers con userId vacío de los viajes del conductor
  Future<void> _cleanupEmptyPassengersFromTrips() async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Buscar viajes activos del conductor
      for (final status in ['active', 'in_progress']) {
        final trips = await firestore
            .collection('trips')
            .where('driverId', isEqualTo: widget.userId)
            .where('status', isEqualTo: status)
            .get();

        for (final tripDoc in trips.docs) {
          final passengers = tripDoc.data()['passengers'] as List<dynamic>? ?? [];
          final cleanPassengers = passengers.where((p) {
            final pMap = p as Map<String, dynamic>;
            final userId = pMap['userId'] as String? ?? '';
            return userId.isNotEmpty;
          }).toList();

          if (cleanPassengers.length < passengers.length) {
            final removed = passengers.length - cleanPassengers.length;
            await tripDoc.reference.update({
              'passengers': cleanPassengers,
            });
            debugPrint('🧹 Removidos $removed passengers vacíos del trip ${tripDoc.id}');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error limpiando passengers vacíos: $e');
    }
  }

  /// Maneja el tap en "Viaje Instantáneo"
  /// Verifica si ya existe uno activo y redirige apropiadamente
  Future<void> _handleInstantTripTap() async {
    // Evitar doble tap
    if (_isNavigating) return;
    _isNavigating = true;

    // Verificar si hay reseñas pendientes antes de crear viaje
    final pendingReview = await _findPendingReview();
    if (pendingReview != null && mounted) {
      _isNavigating = false;
      _showPendingReviewBlockDialog(pendingReview);
      return;
    }

    // Verificar si ya hay un viaje instantáneo activo
    final activeTrip = await TripsService().getActiveInstantTrip(widget.userId);

    if (!mounted) { _isNavigating = false; return; }

    if (activeTrip != null) {
      // Ya tiene un viaje activo, ir a la pantalla de viaje activo
      context.push('/driver/active-trip/${activeTrip.tripId}');
    } else {
      // No tiene viaje activo, crear uno nuevo
      context.push('/driver/instant-trip', extra: {
        'userId': widget.userId,
      });
    }

    Future.delayed(const Duration(seconds: 1), () {
      _isNavigating = false;
    });
  }

  Future<void> _onRoleChanged(String newRole) async {
    // 1. Si intenta cambiar a conductor y no tiene vehículo, mostrar aviso
    if (newRole == 'conductor' && !widget.hasVehicle) {
      _showVehicleRequiredDialog();
      return;
    }

    // 2. Verificar si hay viaje activo o reseña pendiente en el ROL ACTUAL
    final blocking = await _checkActiveOrPendingTrip();
    if (blocking != null && mounted) {
      _showActiveTripBlockDialog(blocking);
      return;
    }

    if (!mounted) return;

    // 3. Cambio permitido
    setState(() {
      _activeRole = newRole;
    });
    // Persistir el rol seleccionado
    _saveActiveRole(newRole);
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

  /// Verifica si el usuario tiene un viaje activo o una reseña pendiente
  /// en su rol actual. Retorna un mensaje descriptivo si hay bloqueo, o null.
  Future<String?> _checkActiveOrPendingTrip() async {
    final firestore = FirebaseFirestore.instance;
    final ratingService = RatingService();

    try {
      if (_activeRole == 'conductor') {
        // === Conductor: buscar viajes activos ===

        // 1. Trip active o in_progress
        final activeTrips = await firestore
            .collection('trips')
            .where('driverId', isEqualTo: widget.userId)
            .where('status', whereIn: ['active', 'in_progress'])
            .limit(1)
            .get();

        if (activeTrips.docs.isNotEmpty) {
          return 'Tienes un viaje activo como conductor. Finalízalo antes de cambiar de rol.';
        }

        // 2. Trip completed recientemente con reseñas pendientes
        final recentCompleted = await firestore
            .collection('trips')
            .where('driverId', isEqualTo: widget.userId)
            .where('status', isEqualTo: 'completed')
            .orderBy('completedAt', descending: true)
            .limit(5)
            .get();

        for (final tripDoc in recentCompleted.docs) {
          final tripData = tripDoc.data();
          final passengers = tripData['passengers'] as List<dynamic>? ?? [];

          for (final p in passengers) {
            final pMap = p as Map<String, dynamic>;
            if (pMap['status'] == 'dropped_off' || pMap['status'] == 'picked_up') {
              final hasRated = await ratingService.hasRated(tripDoc.id, widget.userId);
              if (!hasRated) {
                return 'Tienes una calificación pendiente. Califica a tus pasajeros antes de cambiar de rol.';
              }
            }
          }
        }
      } else {
        // === Pasajero: buscar viajes activos ===

        // 1. RideRequest searching o accepted
        final activeRequests = await firestore
            .collection('ride_requests')
            .where('passengerId', isEqualTo: widget.userId)
            .where('status', whereIn: ['searching', 'accepted'])
            .limit(1)
            .get();

        if (activeRequests.docs.isNotEmpty) {
          return 'Tienes un viaje activo como pasajero. Finalízalo antes de cambiar de rol.';
        }

        // 2. Pasajero picked_up o accepted en trip in_progress
        final inProgressTrips = await firestore
            .collection('trips')
            .where('status', isEqualTo: 'in_progress')
            .get();

        for (final tripDoc in inProgressTrips.docs) {
          final passengers = tripDoc.data()['passengers'] as List<dynamic>? ?? [];
          for (final p in passengers) {
            final pMap = p as Map<String, dynamic>;
            if (pMap['userId'] == widget.userId &&
                (pMap['status'] == 'accepted' || pMap['status'] == 'picked_up')) {
              return 'Estás en un viaje activo como pasajero. Espera a que finalice antes de cambiar de rol.';
            }
          }
        }

        // 3. Pasajero dropped_off sin calificar (reseña pendiente)
        //    Buscar en trips completados e in_progress donde sea pasajero dropped_off
        final recentTrips = await firestore
            .collection('trips')
            .where('status', whereIn: ['completed', 'in_progress'])
            .limit(10)
            .get();

        for (final tripDoc in recentTrips.docs) {
          final passengers = tripDoc.data()['passengers'] as List<dynamic>? ?? [];
          for (final p in passengers) {
            final pMap = p as Map<String, dynamic>;
            if (pMap['userId'] == widget.userId && pMap['status'] == 'dropped_off') {
              final hasRated = await ratingService.hasRated(tripDoc.id, widget.userId);
              if (!hasRated) {
                return 'Tienes una calificación pendiente. Califica al conductor antes de cambiar de rol.';
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error verificando viaje activo: $e');
      // En caso de error, permitir el cambio (no bloquear por fallo de red)
    }

    return null; // No hay bloqueo
  }

  /// Muestra diálogo informativo cuando no se puede cambiar de rol
  void _showActiveTripBlockDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.warning),
            SizedBox(width: 12),
            Expanded(child: Text('No puedes cambiar')),
          ],
        ),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Entendido'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSearchTap() async {
    // Evitar doble tap
    if (_isNavigating) return;
    _isNavigating = true;

    // Verificar si hay reseñas pendientes antes de buscar viaje
    final pendingReview = await _findPendingReview();
    if (pendingReview != null && mounted) {
      _isNavigating = false;
      _showPendingReviewBlockDialog(pendingReview);
      return;
    }

    if (!mounted) { _isNavigating = false; return; }

    // Navegar a la pantalla de planificación de viaje
    context.push('/trip/plan', extra: {
      'userId': widget.userId,
      'userRole': _activeRole,
    });

    Future.delayed(const Duration(seconds: 1), () {
      _isNavigating = false;
    });
  }

  /// Muestra diálogo cuando el usuario intenta crear viaje pero tiene reseñas pendientes
  void _showPendingReviewBlockDialog(Map<String, dynamic> pendingReview) {
    final isDriver = _activeRole == 'conductor';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.rate_review, color: AppColors.warning),
            const SizedBox(width: 12),
            const Expanded(child: Text('Reseña pendiente')),
          ],
        ),
        content: Text(
          isDriver
              ? 'Tienes pasajeros pendientes por calificar de viajes anteriores. Completa tus calificaciones antes de iniciar un nuevo viaje.'
              : 'Tienes un conductor pendiente por calificar de un viaje anterior. Completa tu calificación antes de buscar un nuevo viaje.',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
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
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    final route = pendingReview.remove('route') as String? ?? '/trip/rate';
                    context.go(route, extra: pendingReview);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Calificar ahora',
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

  Future<void> _onRecentPlaceTap(RecentPlace place) async {
    // Evitar doble tap
    if (_isNavigating) return;
    _isNavigating = true;

    // Verificar reseñas pendientes antes de buscar viaje
    final pendingReview = await _findPendingReview();
    if (pendingReview != null && mounted) {
      _isNavigating = false;
      _showPendingReviewBlockDialog(pendingReview);
      return;
    }

    if (!mounted) { _isNavigating = false; return; }

    try {
      // Intentar usar ubicación cacheada primero (instantáneo si hay caché fresco)
      final cached = LocationCacheService().cachedLocation;
      double lat;
      double lng;

      if (cached != null && cached.isFresh(maxAgeMinutes: 3)) {
        lat = cached.latitude;
        lng = cached.longitude;
      } else {
        // Si no hay caché fresco, obtener GPS con timeout corto
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 8));
        lat = pos.latitude;
        lng = pos.longitude;
      }

      if (!mounted) { _isNavigating = false; return; }

      context.push('/trip/confirm-pickup', extra: {
        'userId': widget.userId,
        'userRole': _activeRole,
        'origin': {
          'name': 'Mi ubicación',
          'latitude': lat,
          'longitude': lng,
        },
        'destination': {
          'name': place.name,
          'address': place.address,
          'latitude': place.latitude,
          'longitude': place.longitude,
        },
      });
    } catch (e) {
      // Fallback: ir a plan trip si no hay GPS
      if (!mounted) { _isNavigating = false; return; }
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

    // Resetear flag después de un breve delay para permitir navegación futura
    Future.delayed(const Duration(seconds: 1), () {
      _isNavigating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) {
          context.go('/welcome');
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // Precargador de Google Maps (invisible)
            Builder(
              builder: (context) {
                final cache = LocationCacheService();
                if (cache.hasFreshLocation) {
                  final loc = cache.cachedLocation!;
                  return MapPreloader(
                    initialPosition: LatLng(loc.latitude, loc.longitude),
                  );
                }
                return const MapPreloader();
              },
            ),
            // Contenido principal
            SafeArea(
              child: _activeRole == 'pasajero'
                  ? _buildPassengerHome()
                  : _buildDriverHome(),
            ),
          ],
        ),
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

          // Banner de notificaciones desactivadas
          NotificationPermissionBanner(
            onPermissionGranted: () => setState(() {}),
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

            const SizedBox(height: 24),

            // Link al historial de viajes
            _buildHistorialLink(),

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
            // Banner de ubicación desactivada
            LocationPermissionBanner(
              onPermissionGranted: () => setState(() {}),
            ),

            // Banner de notificaciones desactivadas
            NotificationPermissionBanner(
              onPermissionGranted: () => setState(() {}),
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

          // Opciones de tipo de viaje: Instantáneo y Planificado
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TripTypeOptions(
              onInstantTap: () => _handleInstantTripTap(),
            ),
          ),

          const SizedBox(height: 32),

            // Link al historial de viajes
            _buildHistorialLink(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorialLink() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () {
          context.push('/historial', extra: {
            'userId': widget.userId,
            'activeRole': _activeRole,
          });
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.divider, width: 1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Ver historial de viajes',
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: AppColors.primary,
              ),
            ],
          ),
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
                'activeRole': _activeRole,
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
