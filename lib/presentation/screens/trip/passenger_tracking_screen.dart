// lib/presentation/screens/trip/passenger_tracking_screen.dart
// Pantalla de tracking en tiempo real para el pasajero
// Muestra al conductor moviéndose en el mapa estilo Uber

import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/car_marker_generator.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/trips_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/google_directions_service.dart';
import '../../../data/services/chat_service.dart';
import '../../../data/services/pricing_service.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/models/chat_message.dart';
import '../../widgets/chat/chat_bottom_sheet.dart';

class PassengerTrackingScreen extends StatefulWidget {
  final String tripId;
  final String userId;
  final TripLocation pickupPoint;
  final TripLocation destination;

  const PassengerTrackingScreen({
    super.key,
    required this.tripId,
    required this.userId,
    required this.pickupPoint,
    required this.destination,
  });

  @override
  State<PassengerTrackingScreen> createState() =>
      _PassengerTrackingScreenState();
}

class _PassengerTrackingScreenState extends State<PassengerTrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Servicios
  final _tripsService = TripsService();
  final _firestoreService = FirestoreService();
  final _directionsService = GoogleDirectionsService();
  final _chatService = ChatService();

  // Mapa
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Circle> _circles = {};

  // Viaje y conductor
  TripModel? _currentTrip;
  UserModel? _driverUser;
  VehicleModel? _driverVehicle;
  String _driverId = ''; // Capturado temprano para uso en diálogos
  StreamSubscription<TripModel?>? _tripSubscription;

  // Posición del conductor (para animación suave)
  LatLng? _driverPosition;
  LatLng? _previousDriverPosition;

  // Estado del pasajero
  String _passengerStatus = 'accepted'; // accepted, picked_up, dropped_off
  bool _isPickedUp = false;

  // Taxímetro (leído de Firestore, NO calculado localmente)
  double? _meterFare;
  double? _meterDistanceKm;
  double? _meterWaitMinutes;
  bool? _isNightTariff;
  DateTime? _pickedUpAt;
  double? _discountPercent;
  double? _fareBeforeDiscount;

  // Animación
  late AnimationController _markerAnimController;
  late Animation<double> _markerAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ETA (Google Directions API)
  double? _distanceToPassenger; // metros
  String _etaText = 'Calculando...';
  String _distanceText = '';
  DateTime? _lastEtaUpdate;
  bool _isCalculatingEta = false;
  static const _etaUpdateInterval = Duration(seconds: 30);

  // Timer de espera (cuando el conductor llega al pickup)
  bool _driverArrivedAtPickup = false;
  Timer? _waitCountdownTimer;
  int _waitSecondsRemaining = 0;
  int _totalWaitSeconds = 0;

  // Ícono del carro para marker del conductor
  BitmapDescriptor? _carIcon;

  // === Performance: cache bearing + throttle marker setState ===
  double _cachedBearing = 0;
  DateTime? _lastMarkerUpdate;

  // === Protección: detección de conductor desconectado ===
  static const int _locationWarningSeconds = 120;  // 2 min → banner amarillo
  static const int _locationCriticalSeconds = 300;  // 5 min → diálogo cancelar
  bool _driverLocationStale = false;
  bool _driverLocationCritical = false;
  Timer? _staleLocationCheckTimer;
  bool _criticalDialogShown = false;

  // === Mensajes no leídos ===
  int _unreadMessageCount = 0;
  int _lastSeenDriverMessageCount = 0;
  StreamSubscription<List<ChatMessage>>? _chatSubscription;

  // === Abrir chat desde notificación ===
  StreamSubscription<Map<String, String>>? _openChatSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // NO suprimir notificaciones aquí — el pasajero necesita saber
    // que el conductor llegó y recibir mensajes mientras espera en pickup.
    // La supresión se activa cuando el pasajero sube al carro (picked_up).
    _initAnimations();
    _loadCarIcon();
    _initPickupCircle();
    _startTripStream();
    _startStaleLocationCheck();
    _startUnreadMessageStream();
    _listenForChatOpen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('▶️ Pasajero: app en primer plano — resincronizando');

      // Re-suscribir al stream del viaje si se desconectó
      if (_tripSubscription == null) {
        _startTripStream();
      }

      // Recalibrar timer de espera con datos de Firestore
      if (_currentTrip != null && !_isPickedUp) {
        _syncWaitTimerFromFirestore(_currentTrip!);
      }

      // Actualizar ETA con posición actual del conductor
      _updateETA();

      // Forzar refresh de UI
      if (mounted) setState(() {});
    }
  }

  void _initPickupCircle() {
    _circles = {
      Circle(
        circleId: const CircleId('pickup_zone'),
        center: LatLng(widget.pickupPoint.latitude, widget.pickupPoint.longitude),
        radius: 50, // metros — mismo radio de activación del timer
        fillColor: AppColors.primary.withOpacity(0.12),
        strokeColor: AppColors.primary.withOpacity(0.4),
        strokeWidth: 2,
      ),
    };
  }

  void _initAnimations() {
    _markerAnimController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
    _markerAnimation = CurvedAnimation(
      parent: _markerAnimController,
      curve: Curves.easeInOut,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadCarIcon() async {
    final icon = await CarMarkerGenerator.generate();
    if (icon != null) {
      _carIcon = icon;
      debugPrint('🚗 [Pasajero] Ícono 3D de carro generado exitosamente');
      // Forzar refresh de markers para que el ícono nuevo se aplique
      if (mounted) {
        if (_driverPosition != null) {
          _updateMarkersWithPosition(_driverPosition!);
        } else {
          setState(() {});
        }
      }
    } else {
      debugPrint('⚠️ No se pudo generar ícono 3D, usando default');
    }
  }

  void _startTripStream() {
    _tripSubscription = _tripsService
        .getTripStream(widget.tripId)
        .listen(_onTripUpdate);
  }

  void _onTripUpdate(TripModel? trip) {
    if (trip == null || !mounted) return;

    final previousTrip = _currentTrip;
    _currentTrip = trip;

    // Capturar driverId temprano (para diálogos de rating/cancel)
    if (_driverId.isEmpty && trip.driverId.isNotEmpty) {
      _driverId = trip.driverId;
      // Inicializar chat cuando se captura el conductor
      _chatService.initializeChat(
        tripId: widget.tripId,
        passengerId: widget.userId,
        driverId: trip.driverId,
      );
    }

    // Cargar info del conductor una sola vez
    if (_driverUser == null) {
      _loadDriverInfo(trip.driverId);
    }

    // Actualizar posición del conductor
    if (trip.driverLatitude != null && trip.driverLongitude != null) {
      final newPos = LatLng(trip.driverLatitude!, trip.driverLongitude!);

      // Resetear detección de conductor desconectado al recibir GPS fresco
      if (_driverLocationStale || _driverLocationCritical) {
        setState(() {
          _driverLocationStale = false;
          _driverLocationCritical = false;
          _criticalDialogShown = false;
        });
      }

      if (_driverPosition != null && _driverPosition != newPos) {
        _previousDriverPosition = _driverPosition;
        _driverPosition = newPos;
        _animateDriverMarker();
      } else if (_driverPosition == null) {
        _driverPosition = newPos;
        _updateMarkers();
        _calculateRouteToPickup();
      }

      // Calcular distancia y ETA
      _updateETA();
    }

    // Detectar/resincronizar timer de espera con Firestore (fuente de verdad)
    if (!_isPickedUp) {
      _syncWaitTimerFromFirestore(trip);
    }

    // Detectar estado del pasajero y leer taxímetro
    final myPassenger = trip.passengers.where((p) => p.userId == widget.userId);
    if (myPassenger.isNotEmpty) {
      final passenger = myPassenger.first;

      // Leer datos del taxímetro de Firestore (fuente de verdad = conductor)
      if (passenger.meterFare != null) {
        _meterFare = passenger.meterFare;
        _meterDistanceKm = passenger.meterDistanceKm;
        _meterWaitMinutes = passenger.meterWaitMinutes;
        _isNightTariff = passenger.isNightTariff;
        _pickedUpAt = passenger.pickedUpAt;
        _discountPercent = passenger.discountPercent;
        _fareBeforeDiscount = passenger.fareBeforeDiscount;
      }

      // Cuando es dropped_off, el price final está congelado
      if (passenger.status == 'dropped_off' && passenger.price > 0) {
        _meterFare = passenger.price;
      }

      if (passenger.status != _passengerStatus) {
        setState(() {
          _passengerStatus = passenger.status;
          _isPickedUp = passenger.status == 'picked_up' ||
              passenger.status == 'dropped_off';
        });

        // Recalcular ruta cuando sube al carro
        if (passenger.status == 'picked_up') {
          _calculateRouteToDestination();
        }

        // Mostrar resumen cuando bajan al pasajero
        if (passenger.status == 'dropped_off') {
          _showDropOffSummary(passenger);
        }

        // Si el conductor marca como no_show → ir a rating
        if (passenger.status == 'no_show') {
          _tripSubscription?.cancel();
          _waitCountdownTimer?.cancel();
          _navigateToRating('cancelled');
          return;
        }
      }
    }

    // Viaje completado
    if (trip.status == 'completed') {
      _tripSubscription?.cancel();
      _showCompletedDialog();
    }

    // Viaje cancelado → ir directo a pantalla de reseñas
    if (trip.status == 'cancelled') {
      _tripSubscription?.cancel();
      _navigateToRating('cancelled');
    }

    // Fix P4: Eliminado setState(() {}) redundante que causaba rebuild extra
  }

  Future<void> _loadDriverInfo(String driverId) async {
    try {
      final user = await _firestoreService.getUser(driverId);
      if (mounted) {
        setState(() => _driverUser = user);
      }
      // Cargar vehículo del conductor
      if (_currentTrip != null && _currentTrip!.vehicleId.isNotEmpty) {
        final vehicle = await _firestoreService.getVehicle(_currentTrip!.vehicleId);
        if (mounted) {
          setState(() => _driverVehicle = vehicle);
        }
      }
    } catch (e) {
      debugPrint('Error cargando info conductor: $e');
    }
  }

  void _animateDriverMarker() {
    // Fix P3: Cachear bearing UNA sola vez al inicio de cada animación
    if (_previousDriverPosition != null && _driverPosition != null) {
      _cachedBearing = _calculateBearing(_previousDriverPosition!, _driverPosition!);
    }

    // Remover listener anterior para evitar acumulación de listeners
    _markerAnimController.removeListener(_onMarkerAnimTick);
    _markerAnimController.reset();
    _markerAnimController.addListener(_onMarkerAnimTick);
    _markerAnimController.forward();

    // Mover cámara mostrando conductor + pickup dinámicamente
    if (_driverPosition != null) {
      _fitCameraToDriverAndPickup();
    }
  }

  void _onMarkerAnimTick() {
    if (!mounted) return;

    final prev = _previousDriverPosition;
    final curr = _driverPosition;
    if (prev == null || curr == null) return;

    final t = _markerAnimation.value;
    final interpolated = LatLng(
      prev.latitude + (curr.latitude - prev.latitude) * t,
      prev.longitude + (curr.longitude - prev.longitude) * t,
    );

    // Fix P1: Solo actualizar marker, NO cámara (cámara se movió arriba)
    _updateMarkersWithPosition(interpolated);
  }

  void _updateMarkers() {
    if (_driverPosition == null) return;
    _updateMarkersWithPosition(_driverPosition!);

    // Centrar cámara mostrando conductor + pickup
    _fitCameraToDriverAndPickup();
  }

  /// Ajusta la cámara para mostrar conductor y punto de recogida
  void _fitCameraToDriverAndPickup() {
    if (_driverPosition == null || _mapController == null) return;

    final pickupLat = widget.pickupPoint.latitude;
    final pickupLng = widget.pickupPoint.longitude;
    final driverLat = _driverPosition!.latitude;
    final driverLng = _driverPosition!.longitude;

    final bounds = LatLngBounds(
      southwest: LatLng(
        driverLat < pickupLat ? driverLat : pickupLat,
        driverLng < pickupLng ? driverLng : pickupLng,
      ),
      northeast: LatLng(
        driverLat > pickupLat ? driverLat : pickupLat,
        driverLng > pickupLng ? driverLng : pickupLng,
      ),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );
  }

  void _updateMarkersWithPosition(LatLng driverPos) {
    // Fix P2: Throttle — máximo 10 actualizaciones/seg (cada 100ms)
    final now = DateTime.now();
    if (_lastMarkerUpdate != null &&
        now.difference(_lastMarkerUpdate!).inMilliseconds < 100) return;
    _lastMarkerUpdate = now;

    // Fix P3: Usar bearing cacheado en vez de recalcular cada frame
    final newMarkers = <Marker>{
      // Marker del conductor (carro con ícono personalizado)
      Marker(
        markerId: const MarkerId('driver'),
        position: driverPos,
        icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        rotation: _cachedBearing,
        flat: true,
        infoWindow: InfoWindow(
          title: _driverUser?.firstName ?? 'Conductor',
        ),
      ),

      // Marker de pickup
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(
          widget.pickupPoint.latitude,
          widget.pickupPoint.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: InfoWindow(
          title: 'Tu recogida',
          snippet: widget.pickupPoint.name,
        ),
      ),

      // Marker de destino
      Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(
          widget.destination.latitude,
          widget.destination.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Destino',
          snippet: widget.destination.name,
        ),
      ),
    };

    if (mounted) {
      setState(() => _markers = newMarkers);
    }
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final fromLat = from.latitude * math.pi / 180;
    final toLat = to.latitude * math.pi / 180;

    final x = math.sin(dLon) * math.cos(toLat);
    final y = math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(dLon);

    return (math.atan2(x, y) * 180 / math.pi + 360) % 360;
  }

  // ============================================================
  // RUTAS Y ETA
  // ============================================================

  Future<void> _calculateRouteToPickup() async {
    if (_driverPosition == null) return;

    try {
      final route = await _directionsService.getRoute(
        originLat: _driverPosition!.latitude,
        originLng: _driverPosition!.longitude,
        destLat: widget.pickupPoint.latitude,
        destLng: widget.pickupPoint.longitude,
      );

      if (route != null && mounted) {
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route_to_pickup'),
              points: route.polylinePoints,
              color: AppColors.primary,
              width: 5,
            ),
          };
        });
      }
    } catch (e) {
      debugPrint('Error calculando ruta a pickup: $e');
    }
  }

  Future<void> _calculateRouteToDestination() async {
    if (_driverPosition == null) return;

    try {
      final route = await _directionsService.getRoute(
        originLat: _driverPosition!.latitude,
        originLng: _driverPosition!.longitude,
        destLat: widget.destination.latitude,
        destLng: widget.destination.longitude,
      );

      if (route != null && mounted) {
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route_to_dest'),
              points: route.polylinePoints,
              color: AppColors.success,
              width: 5,
            ),
          };
        });
      }
    } catch (e) {
      debugPrint('Error calculando ruta a destino: $e');
    }
  }

  void _updateETA() {
    if (_driverPosition == null) return;

    final targetLat = _isPickedUp
        ? widget.destination.latitude
        : widget.pickupPoint.latitude;
    final targetLng = _isPickedUp
        ? widget.destination.longitude
        : widget.pickupPoint.longitude;

    // Distancia en línea recta (para detección de cercanía)
    final distance = Geolocator.distanceBetween(
      _driverPosition!.latitude,
      _driverPosition!.longitude,
      targetLat,
      targetLng,
    );
    _distanceToPassenger = distance;

    // Throttle: calcular ETA con Google Directions API cada 30s
    final now = DateTime.now();
    if (_isCalculatingEta) return;
    if (_lastEtaUpdate != null &&
        now.difference(_lastEtaUpdate!) < _etaUpdateInterval) return;

    _isCalculatingEta = true;
    _lastEtaUpdate = now;

    _directionsService.getRoute(
      originLat: _driverPosition!.latitude,
      originLng: _driverPosition!.longitude,
      destLat: targetLat,
      destLng: targetLng,
    ).then((route) {
      if (route != null && mounted) {
        setState(() {
          _etaText = route.durationText;
          _distanceText = route.distanceText;
        });
      }
    }).catchError((e) {
      debugPrint('Error calculando ETA: $e');
    }).whenComplete(() {
      _isCalculatingEta = false;
    });
  }

  // ============================================================
  // DIÁLOGOS
  // ============================================================

  void _showCompletedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '¡Viaje completado!',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Has llegado a tu destino. ¡Buen viaje!',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (_meterFare != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Tarifa: \$${_meterFare!.toStringAsFixed(2)}',
                    style: AppTextStyles.h3.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  if (_discountPercent != null && _discountPercent! > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '-${(_discountPercent! * 100).round()}% grupo',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/trip/rate', extra: {
                  'tripId': widget.tripId,
                  'passengerId': widget.userId,
                  'driverId': _driverId,
                  'ratingContext': 'completed',
                  'fare': _meterFare,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Calificar conductor'),
            ),
          ),
        ],
      ),
    );
  }

  /// Navegar directamente a la pantalla de reseñas
  /// Se usa tanto para cancelación como para completado
  void _navigateToRating(String ratingContext) {
    // Limpiar la ride_request para que no vuelva a redirigir
    _cleanupRideRequest(ratingContext == 'cancelled' ? 'cancelled' : 'completed');

    if (mounted) {
      context.go('/trip/rate', extra: {
        'tripId': widget.tripId,
        'passengerId': widget.userId,
        'driverId': _driverId,
        'ratingContext': ratingContext,
      });
    }
  }

  /// Limpia el status de la ride_request del pasajero
  Future<void> _cleanupRideRequest(String newStatus) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('ride_requests')
          .where('passengerId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({'status': newStatus});
      }
    } catch (e) {
      debugPrint('Error limpiando ride_request: $e');
    }
  }

  void _showCancelledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Viaje cancelado'),
        content: const Text(
          'El conductor ha cancelado el viaje. Disculpa las molestias.',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.go('/home');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Ir al inicio'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.go('/trip/rate', extra: {
                      'tripId': widget.tripId,
                      'passengerId': widget.userId,
                      'driverId': _driverId,
                      'ratingContext': 'cancelled',
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Calificar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDropOffSummary(TripPassenger passenger) {
    final fare = passenger.price > 0 ? passenger.price : (_meterFare ?? 0);
    final distance = passenger.meterDistanceKm ?? _meterDistanceKm ?? 0;
    final isNight = passenger.isNightTariff ?? false;
    final discount = passenger.discountPercent ?? _discountPercent ?? 0.0;
    final beforeDiscount = passenger.fareBeforeDiscount ?? _fareBeforeDiscount;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actionsAlignment: MainAxisAlignment.center,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.success,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Has llegado',
              style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Tu viaje ha finalizado',
              style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),

            // Badge tarifa
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isNight
                    ? Colors.indigo.withValues(alpha: 0.1)
                    : Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                    size: 14,
                    color: isNight ? Colors.indigo : Colors.amber.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tarifa ${isNight ? 'Nocturna' : 'Diurna'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isNight ? Colors.indigo : Colors.amber.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Descuento grupal (si aplica)
            if (discount > 0 && beforeDiscount != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Desc. grupo (${(discount * 100).round()}%)',
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '-\$${(beforeDiscount - fare).toStringAsFixed(2)}',
                    style: AppTextStyles.body2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TOTAL A PAGAR',
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '\$${fare.toStringAsFixed(2)}',
                  style: AppTextStyles.h2.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Detalles
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Distancia',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${distance.toStringAsFixed(1)} km',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            // Método de pago
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.tertiary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    passenger.paymentMethod == 'Efectivo'
                        ? Icons.payments_outlined
                        : Icons.account_balance_outlined,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    passenger.paymentMethod,
                    style: AppTextStyles.body2.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.go('/trip/rate', extra: {
                      'tripId': widget.tripId,
                      'passengerId': widget.userId,
                      'driverId': _driverId,
                      'ratingContext': 'completed',
                      'fare': passenger.price > 0 ? passenger.price : _meterFare,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Calificar conductor',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TIMER DE ESPERA DEL PASAJERO (conductor llegó al pickup)
  // ============================================================

  /// Sincroniza el timer de espera con Firestore (fuente de verdad = conductor).
  /// Se llama en CADA _onTripUpdate para mantener sincronización.
  ///
  /// El conductor escribe `waitingStartedAt` con `FieldValue.serverTimestamp()`,
  /// así ambos dispositivos calculan el elapsed basándose en el reloj del servidor.
  /// El timer local solo maneja el conteo visual entre updates de Firestore (~3s).
  /// Cada vez que llega un update, se recalibra silenciosamente.
  void _syncWaitTimerFromFirestore(TripModel trip) {
    // Si el conductor NO ha iniciado timer → asegurar que el overlay esté oculto
    if (trip.waitingStartedAt == null) {
      if (_driverArrivedAtPickup) {
        _waitCountdownTimer?.cancel();
        setState(() {
          _driverArrivedAtPickup = false;
          _waitSecondsRemaining = 0;
        });
      }
      return;
    }

    // El conductor SÍ inició timer → calcular tiempo restante desde Firestore
    final maxWait = trip.maxWaitMinutes ?? 3;
    final totalSecs = maxWait * 60;
    final elapsed = DateTime.now().difference(trip.waitingStartedAt!).inSeconds;
    final remaining = (totalSecs - elapsed).clamp(0, totalSecs);

    if (!_driverArrivedAtPickup) {
      // Primera vez: mostrar overlay e iniciar timer local
      debugPrint('⏱️ Timer pasajero iniciado: ${remaining}s restantes de ${maxWait}min');
      setState(() {
        _driverArrivedAtPickup = true;
        _totalWaitSeconds = totalSecs;
        _waitSecondsRemaining = remaining;
      });
      _startLocalCountdown();
    } else {
      // Ya estaba corriendo: recalibrar silenciosamente (sin reiniciar timer)
      // Esto corrige drift entre dispositivos en cada update de Firestore (~3s)
      _waitSecondsRemaining = remaining;
      _totalWaitSeconds = totalSecs;
    }
  }

  /// Timer local que solo hace el conteo visual segundo a segundo.
  /// Se recalibra cada vez que llega un update de Firestore.
  void _startLocalCountdown() {
    _waitCountdownTimer?.cancel();
    _waitCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isPickedUp) {
        timer.cancel();
        setState(() => _driverArrivedAtPickup = false);
        return;
      }
      if (_waitSecondsRemaining > 0) {
        setState(() => _waitSecondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  /// Color del timer: turquesa → amarillo → rojo (gradiente suave)
  Color get _waitTimerColor {
    if (_totalWaitSeconds == 0) return AppColors.primary;
    final ratio = _waitSecondsRemaining / _totalWaitSeconds;

    if (ratio > 0.5) {
      // turquesa → amarillo (100% a 50%)
      final t = (ratio - 0.5) / 0.5; // 1.0 → 0.0
      return Color.lerp(AppColors.warning, AppColors.primary, t)!;
    } else {
      // amarillo → rojo (50% a 0%)
      final t = ratio / 0.5; // 1.0 → 0.0
      return Color.lerp(AppColors.error, AppColors.warning, t)!;
    }
  }

  String get _waitTimerText {
    final m = _waitSecondsRemaining ~/ 60;
    final s = _waitSecondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Escuchar eventos de abrir chat desde notificaciones tocadas
  void _listenForChatOpen() {
    _openChatSub = NotificationService().onOpenChatRequested.listen((data) {
      final tripId = data['tripId'] ?? '';
      if (tripId != widget.tripId || !mounted) return;

      debugPrint('🔔 Pasajero: abriendo chat desde notificación');

      ChatBottomSheet.show(
        context,
        tripId: widget.tripId,
        passengerId: widget.userId,
        currentUserId: widget.userId,
        currentUserRole: 'pasajero',
        isActive: _passengerStatus == 'accepted',
        otherUserName: _driverUser != null
            ? '${_driverUser!.firstName} ${_driverUser!.lastName}'
            : 'Conductor',
      );
    });
  }

  @override
  void dispose() {
    _openChatSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _waitCountdownTimer?.cancel();
    _staleLocationCheckTimer?.cancel();
    _chatSubscription?.cancel();
    _tripSubscription?.cancel();
    _markerAnimController.dispose();
    _pulseController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  /// Interceptar botón back nativo de Android
  @override
  Future<bool> didPopRoute() async {
    debugPrint('🔙 didPopRoute interceptado en PassengerTrackingScreen');
    _showExitConfirmation();
    return true;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          // No permitir salir fácilmente, solo con el botón
          _showExitConfirmation();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Mapa de fondo
            _buildMap(),

            // Overlay superior con estado
            _buildTopOverlay(),

            // Banner de conductor desconectado
            if (_driverLocationStale && !_driverArrivedAtPickup)
              _buildStaleLocationBanner(),

            // Card inferior con info del conductor (incluye timer de espera)
            _buildBottomCard(),
          ],
        ),
      ),
    );
  }

  void _showExitConfirmation() {
    if (!_isPickedUp) {
      // PRE-PICKUP: Cancelar viaje (el pasajero aún no subió)
      _showCancelTripDialog();
    } else {
      // POST-PICKUP: Confirmar cancelación → pagar tarifa mínima
      _showCancelWithMinimumFareDialog();
    }
  }

  /// Pre-pickup: diálogo para cancelar el viaje antes de subir
  void _showCancelTripDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar viaje?'),
        content: const Text(
          'Se cancelará tu solicitud y podrás buscar otro viaje.',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Quedarme'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    // Cancelar suscripción y timers
                    _tripSubscription?.cancel();
                    _waitCountdownTimer?.cancel();
                    _chatSubscription?.cancel();
                    // Actualizar status del pasajero en el trip
                    try {
                      await _tripsService.updatePassengerStatus(
                        widget.tripId,
                        widget.userId,
                        'cancelled',
                      );
                    } catch (e) {
                      debugPrint('Error cancelando pasajero en trip: $e');
                    }
                    // Limpiar ride_request
                    await _cleanupRideRequest('cancelled');
                    if (mounted) context.go('/home');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancelar viaje'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Post-pickup: cancelar viaje en curso → pagar tarifa mínima
  void _showCancelWithMinimumFareDialog() {
    final minimumFare = PricingService().getCurrentMinimumFare();
    final isNight = PricingService().isNightTime();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar viaje en curso?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ya estás en el vehículo. Si cancelas, deberás pagar la tarifa mínima de carrera.',
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.attach_money, color: AppColors.warning, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    'Tarifa mínima: \$${minimumFare.toStringAsFixed(2)}',
                    style: AppTextStyles.body1.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.warning,
                    ),
                  ),
                  if (isNight) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.nightlight_round, size: 14, color: AppColors.warning),
                  ],
                ],
              ),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Seguir viaje'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    _tripSubscription?.cancel();
                    _waitCountdownTimer?.cancel();
                    _chatSubscription?.cancel();
                    // Cancelar pasajero en el trip
                    try {
                      await _tripsService.updatePassengerStatus(
                        widget.tripId,
                        widget.userId,
                        'cancelled',
                      );
                    } catch (e) {
                      debugPrint('Error cancelando pasajero en trip: $e');
                    }
                    await _cleanupRideRequest('cancelled');
                    // Navegar a rating con contexto de tarifa mínima
                    if (mounted) {
                      context.go('/trip/rate', extra: {
                        'tripId': widget.tripId,
                        'passengerId': widget.userId,
                        'driverId': _driverId,
                        'ratingContext': 'cancelled',
                        'fare': minimumFare,
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancelar y pagar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PROTECCIÓN: Detección de conductor desconectado
  // ============================================================

  void _startStaleLocationCheck() {
    _staleLocationCheckTimer?.cancel();
    _staleLocationCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkDriverLocationStaleness(),
    );
  }

  void _checkDriverLocationStaleness() {
    if (!mounted || _currentTrip == null) return;

    // Solo durante viaje activo
    if (_currentTrip!.status != 'in_progress') return;

    final updatedAt = _currentTrip!.driverLocationUpdatedAt;
    if (updatedAt == null) return;

    final secondsSinceUpdate = DateTime.now().difference(updatedAt).inSeconds;

    final wasStale = _driverLocationStale;

    setState(() {
      _driverLocationStale = secondsSinceUpdate >= _locationWarningSeconds;
      _driverLocationCritical = secondsSinceUpdate >= _locationCriticalSeconds;
    });

    // Mostrar diálogo crítico una sola vez
    if (_driverLocationCritical && !_criticalDialogShown) {
      _criticalDialogShown = true;
      _showDriverDisconnectedDialog();
    }

    // Reset flag cuando el conductor reconecta
    if (!_driverLocationStale && wasStale) {
      _criticalDialogShown = false;
    }
  }

  // ============================================================
  // MENSAJES NO LEÍDOS
  // ============================================================

  void _startUnreadMessageStream() {
    _chatSubscription = _chatService
        .getMessagesStream(widget.tripId, widget.userId)
        .listen((messages) {
      if (!mounted) return;
      // Contar mensajes del conductor (no del pasajero)
      final totalDriverMessages =
          messages.where((m) => m.senderRole == 'conductor').length;
      final unread = totalDriverMessages - _lastSeenDriverMessageCount;
      if (unread != _unreadMessageCount) {
        setState(() {
          _unreadMessageCount = unread < 0 ? 0 : unread;
        });
      }
    });
  }

  /// Resetear contador de mensajes no leídos (al abrir el chat)
  void _markMessagesAsRead() {
    // Al abrir el chat, marcamos todos los mensajes del conductor como leídos
    _lastSeenDriverMessageCount += _unreadMessageCount;
    setState(() => _unreadMessageCount = 0);
  }

  Widget _buildStaleLocationBanner() {
    final color = _driverLocationCritical ? AppColors.error : AppColors.warning;
    final text = _driverLocationCritical
        ? 'Conductor sin conexión por varios minutos'
        : 'La ubicación del conductor no se actualiza';

    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              _driverLocationCritical
                  ? Icons.wifi_off
                  : Icons.signal_wifi_statusbar_connected_no_internet_4,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDriverDisconnectedDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.wifi_off, color: AppColors.error),
            SizedBox(width: 12),
            Expanded(child: Text('Conductor sin conexión')),
          ],
        ),
        content: const Text(
          'No se ha recibido la ubicación del conductor por varios minutos. '
          'Puede ser un problema de conexión temporal.\n\n'
          'Si el problema persiste, puedes cancelar el viaje.',
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
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Seguir esperando'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _tripSubscription?.cancel();
                    _waitCountdownTimer?.cancel();
                    _staleLocationCheckTimer?.cancel();
                    _cleanupRideRequest('cancelled');
                    if (mounted) context.go('/home');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Cancelar viaje'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final initialTarget = _driverPosition ??
        LatLng(widget.pickupPoint.latitude, widget.pickupPoint.longitude);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: initialTarget,
        zoom: 15,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        if (_driverPosition != null) {
          _updateMarkers();
        }
      },
      markers: _markers,
      polylines: _polylines,
      circles: _circles,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      padding: const EdgeInsets.only(bottom: 220),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.6),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Row(
              children: [
                // Botón atrás
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _showExitConfirmation,
                ),

                const Spacer(),

                // Badge de estado
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _isPickedUp ? AppColors.success : AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, size: 8, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        _isPickedUp ? 'EN VIAJE' : 'EN CAMINO',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Botón centrar en conductor + pickup
                IconButton(
                  icon: const Icon(Icons.my_location, color: Colors.white),
                  onPressed: _fitCameraToDriverAndPickup,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomCard() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                const SizedBox(height: 16),

                // ETA prominente
                _buildEtaSection(),

                const SizedBox(height: 16),

                // Info conductor + vehículo
                _buildDriverRow(),

                const SizedBox(height: 12),

                // Destino (solo post-pickup)
                if (_isPickedUp) ...[
                  _buildDestinationRow(),
                  const SizedBox(height: 8),
                ],
                // Botón de chat (siempre visible, pre y post-pickup)
                _buildChatButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingOverlay() {
    final minutes = _waitSecondsRemaining ~/ 60;
    final seconds = _waitSecondsRemaining % 60;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icono animado
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _waitTimerColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.hourglass_top,
                      size: 40,
                      color: _waitTimerColor,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'El conductor te espera',
                  style: AppTextStyles.h3,
                ),

                const SizedBox(height: 8),

                Text(
                  widget.pickupPoint.name ?? 'Punto de recogida',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Timer grande (sincronizado con el del conductor)
                Text(
                  '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: AppTextStyles.h1.copyWith(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: _waitSecondsRemaining < 60
                        ? AppColors.error
                        : _waitTimerColor,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Tiempo restante para llegar',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 16),

                if (_waitSecondsRemaining <= 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Text(
                      'El conductor puede marcarte como ausente',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 16),

                // Botón de chat con el conductor
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ChatBottomSheet.show(
                        context,
                        tripId: widget.tripId,
                        passengerId: widget.userId,
                        currentUserId: widget.userId,
                        currentUserRole: 'pasajero',
                        isActive: _passengerStatus == 'accepted',
                        otherUserName: _driverUser != null
                            ? '${_driverUser!.firstName} ${_driverUser!.lastName}'
                            : 'Conductor',
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text(
                      'Mensaje al conductor',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEtaSection() {
    final isNearby = _distanceToPassenger != null && _distanceToPassenger! < 50;
    final isStalePrePickup = _driverLocationStale && !_driverArrivedAtPickup && !_isPickedUp;

    // Caso: conductor esperando en pickup
    if (_driverArrivedAtPickup && !_isPickedUp) {
      return Column(
        children: [
          Text(
            'El conductor te espera',
            style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            _waitTimerText,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: _waitTimerColor,
            ),
          ),
        ],
      );
    }

    // Caso: sin señal
    if (isStalePrePickup) {
      return Column(
        children: [
          Text(
            'Sin señal del conductor',
            style: AppTextStyles.body2.copyWith(color: AppColors.warning),
          ),
          const SizedBox(height: 4),
          Text(
            '--',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }

    // Caso normal: ETA + distancia (estilo Google Maps)
    return Column(
      children: [
        Text(
          _etaText,
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: isNearby ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
        if (_distanceText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _distanceText,
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDriverRow() {
    final driverName = _driverUser != null
        ? '${_driverUser!.firstName} ${_driverUser!.lastName.isNotEmpty ? '${_driverUser!.lastName[0]}.' : ''}'
        : 'Conductor';

    // Subtítulo: siempre vehículo
    String subtitle;
    if (_driverVehicle != null) {
      subtitle = '${_driverVehicle!.brand} ${_driverVehicle!.model} · ${_driverVehicle!.plate}';
    } else {
      subtitle = '';
    }
    const Color? subtitleColor = null;

    return Row(
      children: [
        // Avatar del conductor (56x56)
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.tertiary,
            border: Border.all(color: AppColors.divider, width: 1.5),
          ),
          child: ClipOval(
            child: _driverUser?.profilePhotoUrl != null
                ? Image.network(
                    _driverUser!.profilePhotoUrl!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildDriverPlaceholder(),
                  )
                : _buildDriverPlaceholder(),
          ),
        ),
        const SizedBox(width: 12),

        // Nombre, rating, vehículo
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      driverName,
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_driverUser != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.star, size: 14, color: AppColors.warning),
                    const SizedBox(width: 2),
                    Text(
                      _driverUser!.rating.toStringAsFixed(1),
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: AppTextStyles.caption.copyWith(
                    color: subtitleColor ?? AppColors.textSecondary,
                    fontWeight: subtitleColor != null ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),

        // Tarifa badge (solo en viaje)
        if (_meterFare != null && _isPickedUp)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '\$${_meterFare!.toStringAsFixed(2)}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.success,
                fontSize: 18,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDriverPlaceholder() {
    final initials = _driverUser != null
        ? '${_driverUser!.firstName.isNotEmpty ? _driverUser!.firstName[0] : ''}${_driverUser!.lastName.isNotEmpty ? _driverUser!.lastName[0] : ''}'
        : '?';
    return Container(
      color: AppColors.primary.withOpacity(0.1),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: AppTextStyles.body2.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildChatButton() {
    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                _markMessagesAsRead();
                ChatBottomSheet.show(
                  context,
                  tripId: widget.tripId,
                  passengerId: widget.userId,
                  currentUserId: widget.userId,
                  currentUserRole: 'pasajero',
                  isActive: _passengerStatus == 'accepted',
                  otherUserName: _driverUser != null
                      ? '${_driverUser!.firstName} ${_driverUser!.lastName}'
                      : 'Conductor',
                );
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text(
                'Mensaje al conductor',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
          // Badge de mensajes no leídos
          if (_unreadMessageCount > 0)
            Positioned(
              top: -6,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Center(
                  child: Text(
                    _unreadMessageCount > 9 ? '9+' : '$_unreadMessageCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDestinationRow() {
    return Row(
      children: [
        const Icon(Icons.location_on, size: 18, color: AppColors.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.destination.name,
            style: AppTextStyles.body2.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
