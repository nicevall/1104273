// lib/presentation/screens/driver/driver_active_trip_screen.dart
// Pantalla principal del viaje activo del conductor
// GPS turn-by-turn navigation + TTS + polyline + solicitudes entrantes

import 'dart:async';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/ride_request_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/route_info.dart';
import '../../../data/services/trips_service.dart';
import '../../../data/services/ride_requests_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/google_directions_service.dart';
import '../../../data/services/tts_service.dart';
import '../../../data/services/taximeter_service.dart';
import '../../../data/services/pricing_service.dart';
import '../../../data/services/roads_service.dart';
import '../../widgets/driver/taximeter_widget.dart';
import '../../widgets/driver/fare_summary_dialog.dart';
import '../../../core/utils/car_marker_generator.dart';
import 'rate_passenger_screen.dart';
import '../../../data/services/chat_service.dart';
import '../../widgets/chat/chat_bottom_sheet.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../blocs/trip/trip_event.dart';
import '../../blocs/trip/trip_state.dart';

class DriverActiveTripScreen extends StatefulWidget {
  final String tripId;

  const DriverActiveTripScreen({
    super.key,
    required this.tripId,
  });

  @override
  State<DriverActiveTripScreen> createState() => _DriverActiveTripScreenState();
}

class _DriverActiveTripScreenState extends State<DriverActiveTripScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // === Servicios ===
  final _tripsService = TripsService();
  final _requestsService = RideRequestsService();
  final _firestoreService = FirestoreService();
  final _directionsService = GoogleDirectionsService();
  final _ttsService = TtsService();
  final _chatService = ChatService();

  // === Mapa ===
  GoogleMapController? _mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Circle> _circles = {};

  // === Suavizado GPS ===
  Position? _lastValidPosition;
  DateTime? _lastGpsTimestamp;

  // === Brújula del dispositivo (para orientación de cámara) ===
  StreamSubscription<CompassEvent>? _compassSubscription;
  double _compassHeading = 0; // Heading real del magnetómetro

  // === Snap to Roads (solo para Firestore push, NO para UI) ===
  bool _isSnapping = false;

  // === Viaje ===
  TripModel? _currentTrip;
  bool _isLoadingTrip = true;

  // === Navegación turn-by-turn ===
  RouteInfo? _currentRoute;
  int _currentStepIndex = 0;
  double _distanceToNextStep = 0;
  bool _hasAnnouncedCurrentStep = false;
  bool _isCalculatingRoute = false;
  int _lastAcceptedCount = 0;

  // === Solicitudes ===
  List<RideRequestModel> _pendingRequests = [];
  Stream<List<RideRequestModel>>? _requestsStream;
  final Map<String, UserModel?> _usersCache = {};
  final Map<String, int?> _deviationsCache = {};
  final Set<String> _announcedRequests = {};
  bool _stoppedAccepting = false;

  // === Push GPS a Firestore ===
  DateTime? _lastLocationPush;
  static const _locationPushInterval = Duration(seconds: 3);

  // === Performance: car icon cache + camera throttle ===
  BitmapDescriptor? _carIcon;
  double _lastCameraLat = 0;
  double _lastCameraLng = 0;
  double _lastCameraHeading = 0;

  // === Throttle global de cámara (máx 2 animaciones/seg) ===
  DateTime? _lastCameraAnim;
  static const _cameraAnimInterval = Duration(milliseconds: 500);

  // === Auto-completar viaje al llegar al destino ===
  bool _hasTriggeredAutoComplete = false;

  // === Cache para evitar _updateTripMarkers innecesarios ===
  String _lastTripMarkersHash = '';

  // === Estado de espera en punto de recogida ===
  bool _isWaitingAtPickup = false;
  TripPassenger? _waitingForPassenger;
  Timer? _waitTimer;
  int _waitSecondsRemaining = 0;
  bool _isPausedForPickup = false;

  // === Taxímetro ===
  final _taximeterService = TaximeterService();
  Map<String, TaximeterSession> _activeMeterSessions = {};
  final Map<String, String> _passengerNames = {};
  DateTime? _lastMeterSync;
  static const _meterSyncInterval = Duration(seconds: 30);

  // === Animaciones ===
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _requestSlideController;
  late Animation<Offset> _requestSlideAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAnimations();
    _loadCarIcon();
    _startLocationTracking();
    _startCompass();
    _loadInitialData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App va a segundo plano — pausar brújula (GPS se auto-maneja por Android)
      debugPrint('⏸️ Conductor: app en segundo plano — pausando compass');
      _compassSubscription?.cancel();
      _compassSubscription = null;
    } else if (state == AppLifecycleState.resumed) {
      // App vuelve a primer plano — re-suscribir brújula y refrescar UI
      debugPrint('▶️ Conductor: app en primer plano — restaurando');
      _startCompass();

      // Restaurar taxímetros si es necesario (por si el proceso fue pausado mucho tiempo)
      if (_currentTrip != null) {
        _restoreTaximetersIfNeeded(_currentTrip!);
      }

      // Forzar refresh de la UI
      if (mounted) setState(() {});
    }
  }

  /// Escuchar brújula del dispositivo para orientar la cámara
  double _lastCompassBearing = 0; // Último bearing aplicado a la cámara
  DateTime? _lastCompassUpdate;
  static const _compassInterval = Duration(milliseconds: 300);

  // TODO(prod): Cambiar a true para producción (usa brújula real del dispositivo)
  // En false: el mapa se orienta según la dirección de movimiento del GPS/Joystick
  // En true: el mapa se orienta según el giroscopio/magnetómetro del teléfono
  static const _useCompass = false;

  /// Throttle para movimiento GPS de cámara (posición)
  void _animateCameraThrottled(LatLng target, double bearing) {
    final now = DateTime.now();
    if (_lastCameraAnim != null &&
        now.difference(_lastCameraAnim!) < _cameraAnimInterval) return;
    _lastCameraAnim = now;
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 17, bearing: bearing),
      ),
    );
  }

  void _startCompass() {
    // En modo Fake GPS, no usar brújula — el mapa sigue la dirección del movimiento
    if (!_useCompass) {
      debugPrint('🧭 Brújula desactivada (modo desarrollo / Fake GPS)');
      return;
    }

    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading == null || !mounted || _mapController == null) return;
      _compassHeading = event.heading!;

      // Throttle propio de la brújula: máx ~3 actualizaciones/seg
      final now = DateTime.now();
      if (_lastCompassUpdate != null &&
          now.difference(_lastCompassUpdate!) < _compassInterval) return;

      // Solo rotar si cambió >10°
      final diff = (_compassHeading - _lastCompassBearing).abs();
      if (diff > 10) {
        _lastCompassUpdate = now;
        _lastCompassBearing = _compassHeading;
        // moveCamera es instantáneo (no enqueue animación) = más responsivo
        _mapController!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(_lastCameraLat, _lastCameraLng),
              zoom: 17,
              bearing: _compassHeading,
            ),
          ),
        );
      }
    });
  }

  /// Cargar ícono del carro:
  /// 1. Intenta cargar assets/icons/car_marker.png (personalizable)
  /// 2. Si no existe, genera uno programáticamente
  ///
  /// Para personalizar: poner tu propia imagen PNG en assets/icons/car_marker.png
  Future<void> _loadCarIcon() async {
    final icon = await CarMarkerGenerator.generate();
    if (icon != null) {
      _carIcon = icon;
      debugPrint('🚗 Ícono 3D de carro generado exitosamente');
      if (mounted) setState(() {});
    } else {
      debugPrint('⚠️ No se pudo generar ícono 3D, usando default');
    }
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    // NO iniciar repeat aquí — se inicia solo cuando _isWaitingAtPickup

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _requestSlideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _requestSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _requestSlideController,
      curve: Curves.easeOut,
    ));
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingTrip = false);
  }

  // ============================================================
  // GPS TRACKING + NAVEGACIÓN
  // ============================================================

  void _startLocationTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      // TODO(prod): Cambiar a LocationAccuracy.high para producción
      // LocationAccuracy.low permite que Fake GPS funcione para testing
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      if (mounted) {
        setState(() => _currentPosition = position);
        _updateDriverMarker();
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          // TODO(prod): Cambiar a LocationAccuracy.high para producción
          accuracy: LocationAccuracy.low,
          distanceFilter: 3,
        ),
      ).listen((position) {
        if (mounted) {
          _onGpsTick(position);
        }
      });
    } catch (e) {
      debugPrint('Error iniciando tracking: $e');
    }
  }

  /// Procesa UN tick GPS — ultra ligero, sin llamadas HTTP
  void _onGpsTick(Position position) {
    // Validación de velocidad para evitar saltos con Fake GPS
    final now = DateTime.now();
    if (_lastValidPosition != null && _lastGpsTimestamp != null) {
      final dist = Geolocator.distanceBetween(
        _lastValidPosition!.latitude,
        _lastValidPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      final timeDelta =
          now.difference(_lastGpsTimestamp!).inMilliseconds / 1000.0;
      if (timeDelta > 0.1) {
        final speedMs = dist / timeDelta;
        if (speedMs > 40) {
          return; // Salto irreal, descartar
        }
      }
    }

    // Heading del carro = dirección de movimiento (NO brújula)
    double carHeading = _lastCameraHeading;
    if (_lastValidPosition != null) {
      final dist = Geolocator.distanceBetween(
        _lastValidPosition!.latitude,
        _lastValidPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      // Fix C3: threshold 3m para recalcular bearing (antes 1m)
      if (dist > 3) {
        carHeading = Geolocator.bearingBetween(
          _lastValidPosition!.latitude,
          _lastValidPosition!.longitude,
          position.latitude,
          position.longitude,
        );
      }
    }

    // Calcular si la posición cambió visiblemente (>2m)
    final posChanged = Geolocator.distanceBetween(
      _lastCameraLat, _lastCameraLng,
      position.latitude, position.longitude,
    ) > 2;

    _lastValidPosition = position;
    _lastGpsTimestamp = now;
    _currentPosition = position;
    _lastCameraHeading = carHeading;

    // 2. Navegación turn-by-turn (siempre calcular, no depende de posChanged)
    double newDistToNext = _distanceToNextStep;
    int newStepIndex = _currentStepIndex;
    bool newHasAnnounced = _hasAnnouncedCurrentStep;

    if (_currentRoute != null && _currentRoute!.steps.isNotEmpty &&
        _currentStepIndex < _currentRoute!.steps.length) {
      final currentStep = _currentRoute!.steps[_currentStepIndex];
      final distToEnd = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        currentStep.endLocation.latitude, currentStep.endLocation.longitude,
      );
      newDistToNext = distToEnd;

      if (distToEnd < 100 && !_hasAnnouncedCurrentStep) {
        newHasAnnounced = true;
        if (_currentStepIndex + 1 < _currentRoute!.steps.length) {
          final nextStep = _currentRoute!.steps[_currentStepIndex + 1];
          final distText = distToEnd < 100
              ? 'En ${distToEnd.round()} metros'
              : 'En ${(distToEnd / 1000).toStringAsFixed(1)} kilómetros';
          _ttsService.speakNavigation('$distText, ${nextStep.instruction}');
        } else {
          _ttsService.speakNavigation('Estás llegando a tu destino.');
        }
      }

      if (distToEnd < 30) {
        newStepIndex = _currentStepIndex + 1;
        newHasAnnounced = false;
      }
    }

    final navChanged = newStepIndex != _currentStepIndex;

    // 3. Taxímetro
    Map<String, TaximeterSession>? updatedMeterSessions;
    if (_taximeterService.hasActiveSessions) {
      final updated = _taximeterService.onGpsUpdate(
        position.latitude, position.longitude, DateTime.now(),
      );
      updatedMeterSessions = Map.from(updated);
    }

    final meterChanged = updatedMeterSessions != null;

    // Fix C2: Solo setState si algo cambió visiblemente
    if (posChanged || navChanged || meterChanged) {
      // 1. Marker — posición GPS directa, rotación = dirección de movimiento
      final driverMarker = Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(position.latitude, position.longitude),
        icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        rotation: carHeading,
        flat: true,
      );

      final updatedMarkers = <Marker>{
        driverMarker,
        ..._markers.where((m) => m.markerId.value != 'driver'),
      };

      setState(() {
        _markers = updatedMarkers;
        _distanceToNextStep = newDistToNext;
        _currentStepIndex = newStepIndex;
        _hasAnnouncedCurrentStep = newHasAnnounced;
        if (updatedMeterSessions != null) {
          _activeMeterSessions = updatedMeterSessions;
        }
      });
    }

    // 4. Operaciones que NO necesitan setState
    _checkArrivalAtPickup();
    _pushLocationToFirestore(); // Snap to roads se hace AQUÍ, async
    _syncMetersToFirestore();
    _checkOffRoute();
    _checkArrivalAtDestination();

    // 5. Camera throttled — sigue al conductor
    // Con brújula: _compassHeading (giroscopio del teléfono)
    // Sin brújula (Fake GPS): carHeading (dirección de movimiento)
    if (posChanged) {
      _lastCameraLat = position.latitude;
      _lastCameraLng = position.longitude;
      _animateCameraThrottled(
        LatLng(position.latitude, position.longitude),
        _useCompass ? _compassHeading : carHeading,
      );
    }
  }

  /// Solo se usa en initState / onMapCreated (posición inicial)
  void _updateDriverMarker() {
    if (_currentPosition == null) return;

    // Calcular heading manual si tenemos posición previa
    double heading = _currentPosition!.heading;
    if (_lastValidPosition != null) {
      final dist = Geolocator.distanceBetween(
        _lastValidPosition!.latitude,
        _lastValidPosition!.longitude,
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      if (dist > 1) {
        heading = Geolocator.bearingBetween(
          _lastValidPosition!.latitude,
          _lastValidPosition!.longitude,
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      }
    }

    final driverMarker = Marker(
      markerId: const MarkerId('driver'),
      position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      anchor: const Offset(0.5, 0.5),
      rotation: heading,
      flat: true,
    );

    setState(() {
      _markers = {
        driverMarker,
        ..._markers.where((m) => m.markerId.value != 'driver'),
      };
    });

    _lastCameraLat = _currentPosition!.latitude;
    _lastCameraLng = _currentPosition!.longitude;
    _lastCameraHeading = heading;

    _animateCameraThrottled(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      _useCompass ? _compassHeading : heading,
    );
  }

  // ============================================================
  // PUSH GPS A FIRESTORE (para tracking del pasajero)
  // ============================================================

  /// Push posición a Firestore con snap to roads (async, no bloquea UI)
  void _pushLocationToFirestore() {
    if (_currentPosition == null) return;

    final now = DateTime.now();
    if (_lastLocationPush != null &&
        now.difference(_lastLocationPush!) < _locationPushInterval) {
      return;
    }

    _lastLocationPush = now;
    final rawLat = _currentPosition!.latitude;
    final rawLng = _currentPosition!.longitude;

    // Snap to roads async → push la posición ajustada a la calle
    if (!_isSnapping) {
      _isSnapping = true;
      RoadsService.snapToRoad(rawLat, rawLng).then((snapped) {
        _isSnapping = false;
        if (!mounted) return;
        _tripsService.updateDriverLocation(
          widget.tripId,
          latitude: snapped.latitude,
          longitude: snapped.longitude,
        ).catchError((e) {
          debugPrint('Error pushing driver location: $e');
        });
      }).catchError((e) {
        _isSnapping = false;
        // Fallback: enviar GPS raw
        _tripsService.updateDriverLocation(
          widget.tripId,
          latitude: rawLat,
          longitude: rawLng,
        ).catchError((e2) {
          debugPrint('Error pushing driver location: $e2');
        });
      });
    }
  }

  // ============================================================
  // CÁLCULO DE RUTA + POLYLINE
  // ============================================================

  Future<void> _calculateRoute() async {
    if (_currentTrip == null || _currentPosition == null || _isCalculatingRoute) {
      return;
    }

    _isCalculatingRoute = true;

    try {
      // Recoger los pickups de pasajeros aceptados que aún no han subido
      final acceptedPickups = _currentTrip!.passengers
          .where((p) => p.status == 'accepted' && p.pickupPoint != null)
          .map((p) => LatLng(p.pickupPoint!.latitude, p.pickupPoint!.longitude))
          .toList();

      final route = await _directionsService.getRouteWithMultipleWaypoints(
        originLat: _currentPosition!.latitude,
        originLng: _currentPosition!.longitude,
        waypoints: acceptedPickups,
        destLat: _currentTrip!.destination.latitude,
        destLng: _currentTrip!.destination.longitude,
      );

      if (route != null && mounted) {
        setState(() {
          _currentRoute = route;
          _currentStepIndex = 0;
          _hasAnnouncedCurrentStep = false;

          // Dibujar polyline turquesa
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: route.polylinePoints,
              color: AppColors.primary,
              width: 5,
              patterns: [],
            ),
          };
        });

        // Anunciar primera instrucción
        if (route.steps.isNotEmpty) {
          final firstStep = route.steps[0];
          await _ttsService.speakNavigation(firstStep.instruction);
          _hasAnnouncedCurrentStep = true;
        }
      }
    } catch (e) {
      debugPrint('Error calculando ruta: $e');
    } finally {
      _isCalculatingRoute = false;
    }
  }

  // ============================================================
  // NAVEGACIÓN TURN-BY-TURN
  // ============================================================

  // NOTA: La lógica de _updateNavigation() fue consolidada dentro de _onGpsTick()
  // para evitar múltiples setState() por tick GPS

  DateTime? _lastOffRouteCheck;
  static const _offRouteCheckInterval = Duration(seconds: 10);

  void _checkOffRoute() {
    if (_currentRoute == null || _currentPosition == null) return;

    // Throttle: verificar solo cada 10s (no cada tick GPS)
    final now = DateTime.now();
    if (_lastOffRouteCheck != null &&
        now.difference(_lastOffRouteCheck!) < _offRouteCheckInterval) return;
    _lastOffRouteCheck = now;

    final polyPoints = _currentRoute!.polylinePoints;
    if (polyPoints.isEmpty) return;

    // Sampling: verificar cada N puntos del polyline (no todos)
    final step = polyPoints.length > 50 ? polyPoints.length ~/ 30 : 1;
    double minDist = double.infinity;
    for (int i = 0; i < polyPoints.length; i += step) {
      final point = polyPoints[i];
      final dist = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        point.latitude,
        point.longitude,
      );
      if (dist < minDist) minDist = dist;
      if (minDist < 50) break; // Ya está cerca, no seguir buscando
    }

    // Si está a más de 150m de la ruta → recalcular
    if (minDist > 150) {
      debugPrint('Conductor se desvió ${minDist.round()}m, recalculando ruta...');
      _ttsService.speakAnnouncement('Recalculando ruta.');
      _calculateRoute();
    }
  }

  // ============================================================
  // AUTO-COMPLETAR VIAJE AL LLEGAR AL DESTINO
  // ============================================================

  void _checkArrivalAtDestination() {
    if (_currentTrip == null || _currentPosition == null) return;
    if (_hasTriggeredAutoComplete) return;

    // Solo verificar si hay pasajeros picked_up (viaje activamente en curso)
    final pickedUpPassengers = _currentTrip!.passengers
        .where((p) => p.status == 'picked_up')
        .toList();
    if (pickedUpPassengers.isEmpty) return;

    final distToDestination = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _currentTrip!.destination.latitude,
      _currentTrip!.destination.longitude,
    );

    // 80m threshold (más amplio que pickup porque destinos universitarios son áreas grandes)
    if (distToDestination < 80) {
      _hasTriggeredAutoComplete = true;
      debugPrint('🏁 Llegó al destino (${distToDestination.round()}m), mostrando overlay de pago...');
      _ttsService.speakAnnouncement('Has llegado al destino. Confirma el pago de cada pasajero.');
      _showDestinationPaymentSheet();
    }
  }

  /// Mostrar overlay de pago por pasajero al llegar al destino
  Future<void> _showDestinationPaymentSheet() async {
    if (!mounted || _currentTrip == null) return;

    // Obtener pasajeros picked_up que necesitan pago
    final pickedUpPassengers = _currentTrip!.passengers
        .where((p) => p.status == 'picked_up')
        .toList();

    if (pickedUpPassengers.isEmpty) {
      // No hay pasajeros, completar directamente
      _finalizeTrip();
      return;
    }

    // Procesar cada pasajero secuencialmente
    for (final passenger in pickedUpPassengers) {
      if (!mounted) break;

      // Detener taxímetro para este pasajero
      final finalSession = _taximeterService.stopMeter(passenger.userId);
      if (finalSession == null) continue;

      final name = _passengerNames[passenger.userId] ?? 'Pasajero';

      // Actualizar estado en Firestore
      try {
        await _tripsService.dropOffPassenger(
          widget.tripId,
          passenger.userId,
          finalFare: finalSession.currentFare,
          dropoffLatitude: _currentPosition?.latitude ?? 0,
          dropoffLongitude: _currentPosition?.longitude ?? 0,
          totalDistanceKm: finalSession.totalDistanceKm,
          totalWaitMinutes: finalSession.totalWaitMinutes,
        );

        if (mounted) {
          context.read<TripBloc>().add(
            UpdatePassengerStatusEvent(
              tripId: widget.tripId,
              passengerId: passenger.userId,
              newStatus: 'dropped_off',
            ),
          );
        }
      } catch (e) {
        debugPrint('Error en drop-off automático: $e');
      }

      // Actualizar UI
      setState(() {
        _activeMeterSessions.remove(passenger.userId);
      });

      // Mostrar diálogo de pago
      if (mounted) {
        final pagoConfirmado = await FareSummaryDialog.show(
          context,
          passengerName: name,
          session: finalSession,
          paymentMethod: passenger.paymentMethod,
        );

        if (pagoConfirmado == true && mounted) {
          // Marcar pago como recibido
          try {
            await _tripsService.updatePassengerPaymentStatus(
              widget.tripId,
              passenger.userId,
              'paid',
            );
          } catch (e) {
            debugPrint('Error actualizando pago: $e');
          }

          // Calificar al pasajero
          if (mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RatePassengerScreen(
                  tripId: widget.tripId,
                  driverId: _currentTrip?.driverId ?? '',
                  passengerId: passenger.userId,
                  passengerName: name,
                  fare: finalSession.currentFare,
                ),
              ),
            );
          }
        }
      }
    }

    // Todos los pasajeros procesados — completar viaje
    _finalizeTrip();
  }

  /// Completar el viaje (enviar evento al BLoC)
  void _finalizeTrip() {
    if (mounted) {
      _ttsService.speakAnnouncement('Viaje finalizado. ¡Buen viaje!');
      context.read<TripBloc>().add(
            CompleteTripEvent(tripId: widget.tripId),
          );
    }
  }

  // ============================================================
  // TTS PARA SOLICITUDES ENTRANTES
  // ============================================================

  void _announceNewRequests(List<RideRequestModel> requests) {
    for (final request in requests) {
      if (_announcedRequests.contains(request.requestId)) continue;
      _announcedRequests.add(request.requestId);

      // Construir texto para TTS
      _getUserInfo(request.passengerId).then((user) {
        final name = user?.firstName ?? 'Un pasajero';
        final pickup = request.pickupPoint.name;
        final deviation = _deviationsCache[request.requestId];

        final buffer = StringBuffer();
        buffer.write('Nueva solicitud. $name quiere que lo recojas en $pickup, pago con ${request.paymentMethod.toLowerCase()}.');

        if (deviation != null) {
          buffer.write(' Desvío de $deviation minutos.');
        }

        if (request.hasPet) {
          buffer.write(' Lleva mascota.');
        }
        if (request.hasLargeObject) {
          buffer.write(' Lleva objeto grande.');
        }

        _ttsService.speakRequest(buffer.toString());
      });
    }
  }

  // ============================================================
  // LÓGICA DE PICKUP Y ESPERA
  // ============================================================

  void _checkArrivalAtPickup() {
    if (_currentTrip == null || _currentPosition == null || _isPausedForPickup) {
      return;
    }

    final pendingPickups = _currentTrip!.passengers.where(
      (p) => p.status == 'accepted' && p.pickupPoint != null,
    ).toList();

    for (final passenger in pendingPickups) {
      final distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        passenger.pickupPoint!.latitude,
        passenger.pickupPoint!.longitude,
      );

      if (distance < 50) {
        _ttsService.speakAnnouncement(
          'Has llegado al punto de recogida del pasajero.',
        );
        _startWaitingTimer(passenger);
        break;
      }
    }
  }

  void _startWaitingTimer(TripPassenger passenger) {
    if (_isWaitingAtPickup) return;

    final maxWait = _currentTrip?.maxWaitMinutes ?? 5;

    _pulseController.repeat(reverse: true);
    setState(() {
      _isWaitingAtPickup = true;
      _isPausedForPickup = true;
      _waitingForPassenger = passenger;
      _waitSecondsRemaining = maxWait * 60;
    });

    // Escribir timestamp en Firestore para sincronizar con pasajero
    FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .update({
      'waitingStartedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('⏱️ Timer de espera iniciado: ${maxWait}min');

    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_waitSecondsRemaining > 0) {
        setState(() => _waitSecondsRemaining--);
      } else {
        timer.cancel();
        _showPassengerArrivedDialog();
      }
    });
  }

  /// Reinicia el timer con minutos de gracia extra
  void _restartTimerWithGrace(int graceMinutes) {
    _waitTimer?.cancel();
    setState(() {
      _waitSecondsRemaining = graceMinutes * 60;
    });

    // Actualizar en Firestore para sincronizar con pasajero
    FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .update({
      'maxWaitMinutes': graceMinutes,
      'waitingStartedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('⏱️ Gracia extra: ${graceMinutes}min');

    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_waitSecondsRemaining > 0) {
        setState(() => _waitSecondsRemaining--);
      } else {
        timer.cancel();
        _showPassengerArrivedDialog();
      }
    });
  }

  void _showPassengerArrivedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.timer_off, color: AppColors.warning),
            SizedBox(width: 12),
            Expanded(child: Text('Se acabó el tiempo')),
          ],
        ),
        content: const Text(
          '¿El pasajero llegó? También puedes darle más tiempo de gracia.',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        actions: [
          // Fila 1: Botones de gracia
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _restartTimerWithGrace(1);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('+1 min'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _restartTimerWithGrace(2);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('+2 min'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _restartTimerWithGrace(3);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('+3 min'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fila 2: No llegó / Ya subió
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _handlePassengerNoShow();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('No llegó'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _handlePassengerPickedUp();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Ya subió'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Restaurar taxímetros desde Firestore para pasajeros que ya están picked_up
  /// pero cuya sesión local se perdió (ej: app restart, flutter run)
  bool _hasRestoredTaximeters = false;
  void _restoreTaximetersIfNeeded(TripModel trip) {
    if (_hasRestoredTaximeters) return; // Solo restaurar una vez

    final pickedUp = trip.passengers.where((p) => p.status == 'picked_up').toList();
    if (pickedUp.isEmpty) return;

    bool restored = false;
    for (final p in pickedUp) {
      if (_taximeterService.getSession(p.userId) != null) continue; // Ya existe

      // Restaurar desde Firestore
      final startLat = p.pickupPoint?.latitude ?? _currentPosition?.latitude ?? 0;
      final startLng = p.pickupPoint?.longitude ?? _currentPosition?.longitude ?? 0;
      final session = _taximeterService.restoreMeter(
        passengerId: p.userId,
        startTime: p.pickedUpAt ?? DateTime.now(),
        startLat: startLat,
        startLng: startLng,
        isNightTariff: p.isNightTariff ?? PricingService().isNightTime(),
        distanceKm: p.meterDistanceKm ?? 0,
        waitMinutes: p.meterWaitMinutes ?? 0,
        fare: p.meterFare ?? 0,
        currentLat: _currentPosition?.latitude ?? startLat,
        currentLng: _currentPosition?.longitude ?? startLng,
      );

      _activeMeterSessions[p.userId] = session;
      _passengerNames[p.userId] = 'Pasajero'; // Cargar nombre async
      _getUserInfo(p.userId).then((user) {
        if (user != null && mounted) {
          setState(() => _passengerNames[p.userId] = user.firstName);
        }
      });

      restored = true;
      debugPrint('🔄 Taxímetro restaurado para ${p.userId}: \$${session.currentFare.toStringAsFixed(2)}');
    }

    if (restored && mounted) {
      setState(() {}); // Refresh UI con los taxímetros restaurados
    }
    _hasRestoredTaximeters = true;
  }

  void _handlePassengerPickedUp() {
    if (_waitingForPassenger == null || _currentTrip == null) return;

    final passengerId = _waitingForPassenger!.userId;

    context.read<TripBloc>().add(
      UpdatePassengerStatusEvent(
        tripId: widget.tripId,
        passengerId: passengerId,
        newStatus: 'picked_up',
      ),
    );

    // === Iniciar taxímetro para este pasajero ===
    if (_currentPosition != null) {
      final session = _taximeterService.startMeter(
        passengerId: passengerId,
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
      );
      setState(() {
        _activeMeterSessions = {
          ..._activeMeterSessions,
          passengerId: session,
        };
      });

      // Guardar nombre para mostrar en el widget
      final cachedUser = _usersCache[passengerId];
      _passengerNames[passengerId] = cachedUser?.firstName ?? 'Pasajero';
      // Si no está en caché, obtener nombre asíncronamente
      if (cachedUser == null) {
        _getUserInfo(passengerId).then((user) {
          if (user != null && mounted) {
            setState(() {
              _passengerNames[passengerId] = user.firstName;
            });
          }
        });
      }

      // Iniciar taxímetro en Firestore
      _tripsService.startPassengerMeter(
        widget.tripId,
        passengerId,
        pickupLatitude: _currentPosition!.latitude,
        pickupLongitude: _currentPosition!.longitude,
        isNightTariff: session.isNightTariff,
      );

      debugPrint('🚕 Taxímetro iniciado para $passengerId '
          '(${session.isNightTariff ? "Nocturna" : "Diurna"})');
    }

    _ttsService.speakAnnouncement('Pasajero recogido. Taxímetro iniciado.');

    // Desactivar chat con este pasajero (chat solo activo en status 'accepted')
    _chatService.deactivateChat(widget.tripId, passengerId);

    _resetWaitingState();
    // Recalcular ruta sin este pickup
    _calculateRoute();
  }

  void _handlePassengerNoShow() {
    if (_waitingForPassenger == null || _currentTrip == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pasajero no apareció'),
        content: const Text(
          '¿Confirmas que el pasajero no llegó al punto de encuentro? '
          'Se liberará el asiento y el pasajero recibirá una notificación.',
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
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    final passengerId = _waitingForPassenger!.userId;

                    // 1. Marcar como no_show en el viaje
                    context.read<TripBloc>().add(
                      UpdatePassengerStatusEvent(
                        tripId: widget.tripId,
                        passengerId: passengerId,
                        newStatus: 'no_show',
                      ),
                    );

                    // 2. Cancelar ride_request del pasajero
                    _cancelPassengerRideRequest(passengerId);

                    // 3. Liberar asiento
                    FirebaseFirestore.instance
                        .collection('trips')
                        .doc(widget.tripId)
                        .update({
                      'availableSeats': FieldValue.increment(1),
                    });

                    _resetWaitingState();
                    _calculateRoute();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Confirmar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Cancela el ride_request del pasajero que no apareció
  Future<void> _cancelPassengerRideRequest(String passengerId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('ride_requests')
          .where('passengerId', isEqualTo: passengerId)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({'status': 'no_show'});
        debugPrint('✅ ride_request del pasajero $passengerId marcado como no_show');
      }
    } catch (e) {
      debugPrint('⚠️ Error cancelando ride_request: $e');
    }
  }

  void _resetWaitingState() {
    _waitTimer?.cancel();
    _pulseController.stop(); // Detener animación de espera
    setState(() {
      _isWaitingAtPickup = false;
      _isPausedForPickup = false;
      _waitingForPassenger = null;
      _waitSecondsRemaining = 0;
    });
  }

  // ============================================================
  // NAVEGACIÓN Y ACCIONES
  // ============================================================

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: AppColors.warning),
            SizedBox(width: 12),
            Text('¿Cancelar viaje?'),
          ],
        ),
        content: const Text(
          'Si sales ahora, el viaje se cancelará y los pasajeros '
          'que hayas aceptado serán notificados.\n\n'
          '¿Estás seguro de que quieres cancelar?',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Continuar viaje'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Sí, cancelar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (result == true) {
      context.read<TripBloc>().add(CancelTripEvent(tripId: widget.tripId));
      await _ttsService.stop();
      _navigateToHome();
    }

    return false;
  }

  void _navigateToHome() {
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      context.go('/home', extra: {
        'userId': authState.user.userId,
        'userRole': authState.user.role,
        'hasVehicle': authState.user.hasVehicle,
        'activeRole': 'conductor',
      });
    } else {
      context.go('/home');
    }
  }

  // ============================================================
  // TAXÍMETRO — Actualización y sincronización
  // ============================================================

  // NOTA: La lógica de _updateTaximeters() fue consolidada dentro de _onGpsTick()
  // para evitar múltiples setState() por tick GPS

  Future<void> _syncMetersToFirestore() async {
    final now = DateTime.now();
    if (_lastMeterSync != null &&
        now.difference(_lastMeterSync!) < _meterSyncInterval) {
      return;
    }
    _lastMeterSync = now;

    final sessionsToSync = _taximeterService.getSessionsNeedingSync();
    for (final session in sessionsToSync) {
      try {
        await _tripsService.updatePassengerMeter(
          widget.tripId,
          session.passengerId,
          meterDistanceKm: session.totalDistanceKm,
          meterWaitMinutes: session.totalWaitMinutes,
          meterFare: session.currentFare,
        );
        _taximeterService.markSynced(session.passengerId);
        debugPrint('📡 Sync taxímetro ${session.passengerId}: '
            '\$${session.currentFare.toStringAsFixed(2)}');
      } catch (e) {
        debugPrint('⚠️ Error sync taxímetro: $e');
      }
    }
  }

  void _handlePassengerDropOff(String passengerId) {
    final session = _taximeterService.getSession(passengerId);
    if (session == null) return;

    final name = _passengerNames[passengerId] ?? 'Pasajero';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.place, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(child: Text('¿Dejar a $name aquí?')),
          ],
        ),
        content: Text(
          'Tarifa actual: \$${session.currentFare.toStringAsFixed(2)}\n'
          'Distancia: ${session.totalDistanceKm.toStringAsFixed(1)} km\n'
          'Tiempo: ${session.elapsedFormatted}\n\n'
          '¿Confirmas que el pasajero se baja aquí?',
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
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmDropOff(passengerId);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Sí, dejar aquí'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Obtener método de pago de un pasajero del trip actual
  String _getPassengerPaymentMethod(String passengerId) {
    if (_currentTrip == null) return 'Efectivo';
    try {
      final passenger = _currentTrip!.passengers.firstWhere(
        (p) => p.userId == passengerId,
      );
      return passenger.paymentMethod;
    } catch (_) {
      return 'Efectivo';
    }
  }

  Future<void> _confirmDropOff(String passengerId) async {
    // Detener taxímetro local
    final finalSession = _taximeterService.stopMeter(passengerId);
    if (finalSession == null) return;

    final name = _passengerNames[passengerId] ?? 'Pasajero';

    // Actualizar estado en Firestore
    try {
      await _tripsService.dropOffPassenger(
        widget.tripId,
        passengerId,
        finalFare: finalSession.currentFare,
        dropoffLatitude: _currentPosition?.latitude ?? 0,
        dropoffLongitude: _currentPosition?.longitude ?? 0,
        totalDistanceKm: finalSession.totalDistanceKm,
        totalWaitMinutes: finalSession.totalWaitMinutes,
      );

      // Actualizar estado del pasajero a dropped_off
      if (mounted) {
        context.read<TripBloc>().add(
          UpdatePassengerStatusEvent(
            tripId: widget.tripId,
            passengerId: passengerId,
            newStatus: 'dropped_off',
          ),
        );
      }
    } catch (e) {
      debugPrint('Error en drop-off: $e');
    }

    // Actualizar UI
    setState(() {
      _activeMeterSessions.remove(passengerId);
    });

    // TTS
    _ttsService.speakAnnouncement(
      'Pasajero dejado. Tarifa: \$${finalSession.currentFare.toStringAsFixed(2)}',
    );

    // Mostrar resumen de tarifa y esperar confirmación de pago
    if (mounted) {
      final pagoConfirmado = await FareSummaryDialog.show(
        context,
        passengerName: name,
        session: finalSession,
        paymentMethod: _getPassengerPaymentMethod(passengerId),
      );

      if (pagoConfirmado == true && mounted) {
        // Actualizar paymentStatus a 'paid' en Firestore
        try {
          await _tripsService.updatePassengerPaymentStatus(
            widget.tripId,
            passengerId,
            'paid',
          );
        } catch (e) {
          debugPrint('Error actualizando pago: $e');
        }

        // Navegar a pantalla de calificación del pasajero
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RatePassengerScreen(
                tripId: widget.tripId,
                driverId: _currentTrip?.driverId ?? '',
                passengerId: passengerId,
                passengerName: name,
                fare: finalSession.currentFare,
              ),
            ),
          );
        }
      }
    }

    // Recalcular ruta si quedan pasajeros
    if (_taximeterService.hasActiveSessions) {
      _calculateRoute();
    }
  }

  void _completeTrip() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            SizedBox(width: 12),
            Text('Finalizar viaje'),
          ],
        ),
        content: const Text(
          '¿Has llegado a tu destino y completado el viaje?',
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
                  child: const Text('Todavía no'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    // Mostrar flujo de pago por pasajero + rating
                    if (_taximeterService.hasActiveSessions) {
                      await _showDestinationPaymentSheet();
                    } else {
                      // No hay taxímetros activos, finalizar directamente
                      _finalizeTrip();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Sí, finalizar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS DE DATOS
  // ============================================================

  Future<void> _calculateDeviation(RideRequestModel request) async {
    if (_currentTrip == null) return;
    if (_deviationsCache.containsKey(request.requestId)) return;

    try {
      final acceptedPickups = _currentTrip!.passengers
          .where((p) => p.status == 'accepted' && p.pickupPoint != null)
          .map((p) => p.pickupPoint!)
          .toList();

      final deviation = await _directionsService.calculateTotalDeviation(
        origin: _currentTrip!.origin,
        destination: _currentTrip!.destination,
        acceptedPickups: acceptedPickups,
        newPickup: request.pickupPoint,
      );

      if (mounted) {
        setState(() {
          _deviationsCache[request.requestId] = deviation?.deviationMinutes;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _deviationsCache[request.requestId] = null;
        });
      }
    }
  }

  Future<UserModel?> _getUserInfo(String passengerId) async {
    if (_usersCache.containsKey(passengerId)) {
      return _usersCache[passengerId];
    }

    try {
      final user = await _firestoreService.getUser(passengerId);
      _usersCache[passengerId] = user;
      return user;
    } catch (e) {
      _usersCache[passengerId] = null;
      return null;
    }
  }

  IconData _getManeuverIcon(String? maneuver) {
    switch (maneuver) {
      case 'turn-left':
        return Icons.turn_left;
      case 'turn-right':
        return Icons.turn_right;
      case 'turn-slight-left':
        return Icons.turn_slight_left;
      case 'turn-slight-right':
        return Icons.turn_slight_right;
      case 'uturn-left':
        return Icons.u_turn_left;
      case 'uturn-right':
        return Icons.u_turn_right;
      case 'roundabout-left':
        return Icons.roundabout_left;
      case 'roundabout-right':
        return Icons.roundabout_right;
      case 'straight':
        return Icons.straight;
      case 'merge':
        return Icons.merge;
      case 'fork-left':
        return Icons.fork_left;
      case 'fork-right':
        return Icons.fork_right;
      case 'ramp-left':
        return Icons.turn_slight_left;
      case 'ramp-right':
        return Icons.turn_slight_right;
      default:
        return Icons.navigation;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _compassSubscription?.cancel();
    _waitTimer?.cancel();
    _pulseController.dispose();
    _requestSlideController.dispose();
    _mapController?.dispose();
    _ttsService.stop();
    _taximeterService.dispose();
    super.dispose();
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
          await _onWillPop();
        }
      },
      child: BlocListener<TripBloc, TripState>(
        listener: (context, state) {
          if (state is TripCompleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('¡Viaje completado!'),
                backgroundColor: AppColors.success,
              ),
            );
            _ttsService.stop();
            _navigateToHome();
          } else if (state is TripCancelled) {
            _ttsService.stop();
            _navigateToHome();
          }
        },
        child: Scaffold(
          body: StreamBuilder<TripModel?>(
            stream: _tripsService.getTripStream(widget.tripId),
            builder: (context, tripSnapshot) {
              if (tripSnapshot.connectionState == ConnectionState.waiting &&
                  _currentTrip == null) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              if (tripSnapshot.hasError) {
                return _buildError(tripSnapshot.error.toString());
              }

              final trip = tripSnapshot.data;
              if (trip == null) {
                return const Center(child: Text('Viaje no encontrado'));
              }

              _currentTrip = trip;

              // Diferir actualizaciones para evitar setState durante build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _updateTripMarkers(trip);

                // Restaurar taxímetros de pasajeros picked_up si la sesión local se perdió
                _restoreTaximetersIfNeeded(trip);

                // Calcular ruta al inicio o cuando cambian los pasajeros
                if (_currentRoute == null && _currentPosition != null) {
                  _calculateRoute();
                } else if (trip.acceptedPassengersCount != _lastAcceptedCount) {
                  _lastAcceptedCount = trip.acceptedPassengersCount;
                  _ttsService.speakAnnouncement(
                    'Ruta actualizada. Nuevo pasajero agregado.',
                  );
                  _calculateRoute();
                }
              });

              return Stack(
                children: [
                  // Mapa de fondo
                  _buildMap(trip),

                  // Overlay superior con info del viaje
                  _buildTopOverlay(trip),

                  // Banner de navegación turn-by-turn
                  if (_currentRoute != null &&
                      _currentRoute!.steps.isNotEmpty &&
                      _currentStepIndex < _currentRoute!.steps.length)
                    _buildNavigationBanner(),

                  // Solicitudes entrantes (si no está pausado)
                  if (!_isPausedForPickup)
                    _buildRequestsOverlay(trip),

                  // Timer de espera (si está esperando)
                  if (_isWaitingAtPickup)
                    _buildWaitingOverlay(),

                  // Botones de acción (abajo del todo)
                  _buildActionButtons(trip),

                  // Chip "No más solicitudes" (arriba)
                  _buildStopAcceptingChip(trip),

                  // Taxímetro flotante (encima del botón finalizar)
                  if (_activeMeterSessions.isNotEmpty)
                    Positioned(
                      bottom: 110,
                      left: 0,
                      right: 0,
                      child: TaximeterWidget(
                        sessions: _taximeterService.activeSessions,
                        passengerNames: _passengerNames,
                        isNightTariff: _taximeterService.activeSessions.isNotEmpty
                            ? _taximeterService.activeSessions.first.isNightTariff
                            : PricingService().isNightTime(),
                        onDropOff: _handlePassengerDropOff,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildError(String error) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Error'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _navigateToHome,
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Error: $error'),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MARKERS DEL VIAJE
  // ============================================================

  void _updateTripMarkers(TripModel trip) {
    // Crear hash para detectar si los markers realmente cambiaron
    // Solo incluir datos que afectan los markers (pasajeros pendientes)
    final hashBuffer = StringBuffer();
    hashBuffer.write('dest:${trip.destination.latitude},${trip.destination.longitude}|');
    for (final p in trip.passengers) {
      hashBuffer.write('${p.userId}:${p.status}|');
    }
    final newHash = hashBuffer.toString();

    // Si no cambió nada relevante, no hacer setState
    if (newHash == _lastTripMarkersHash) return;
    _lastTripMarkersHash = newHash;

    final newMarkers = <Marker>{};
    final newCircles = <Circle>{};

    // Marcador de destino
    newMarkers.add(Marker(
      markerId: const MarkerId('destination'),
      position: LatLng(trip.destination.latitude, trip.destination.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(title: 'Destino', snippet: trip.destination.name),
    ));

    // Marcadores de puntos de recogida de pasajeros pendientes de recoger
    for (final passenger in trip.passengers) {
      final isPendingPickup = passenger.status == 'accepted' ||
          passenger.status == 'waiting_for_passenger';
      if (isPendingPickup && passenger.pickupPoint != null) {
        final pickupPos = LatLng(
          passenger.pickupPoint!.latitude,
          passenger.pickupPoint!.longitude,
        );

        newMarkers.add(Marker(
          markerId: MarkerId('pickup_${passenger.userId}'),
          position: pickupPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: 'Recoger pasajero',
            snippet: passenger.pickupPoint!.name,
          ),
        ));

        // Área circular de recogida (50m = radio de activación del timer)
        newCircles.add(Circle(
          circleId: CircleId('pickup_zone_${passenger.userId}'),
          center: pickupPos,
          radius: 50, // metros — mismo radio que _checkArrivalAtPickup
          fillColor: AppColors.primary.withOpacity(0.12),
          strokeColor: AppColors.primary.withOpacity(0.4),
          strokeWidth: 2,
        ));
      }
    }

    // Mantener el marcador del conductor
    final driverMarker = _markers.where((m) => m.markerId.value == 'driver');

    setState(() {
      _markers = {...newMarkers, ...driverMarker};
      _circles = newCircles;
    });
  }

  // ============================================================
  // WIDGETS DE UI
  // ============================================================

  Widget _buildMap(TripModel trip) {
    final initialPosition = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : LatLng(trip.origin.latitude, trip.origin.longitude);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: initialPosition,
        zoom: 17,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        _updateDriverMarker();
      },
      markers: _markers,
      polylines: _polylines,
      circles: _circles,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }

  Widget _buildTopOverlay(TripModel trip) {
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
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Barra superior
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _onWillPop,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 8, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'EN VIAJE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Info del destino
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.flag,
                          color: AppColors.success,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Destino',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              trip.destination.name,
                              style: AppTextStyles.body2.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Pasajeros aceptados
                      Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${trip.acceptedPassengersCount}/${trip.totalCapacity}',
                                style: AppTextStyles.body2.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'pasajeros',
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BANNER DE NAVEGACIÓN TURN-BY-TURN
  // ============================================================

  Widget _buildNavigationBanner() {
    final step = _currentRoute!.steps[_currentStepIndex];
    final distText = _distanceToNextStep < 1000
        ? '${_distanceToNextStep.round()} m'
        : '${(_distanceToNextStep / 1000).toStringAsFixed(1)} km';

    return Positioned(
      top: MediaQuery.of(context).padding.top + 145,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icono de maniobra
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getManeuverIcon(step.maneuver),
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),

            // Instrucción
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.instruction,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    distText,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Indicador de step
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_currentStepIndex + 1}/${_currentRoute!.steps.length}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SOLICITUDES ENTRANTES
  // ============================================================

  Widget _buildRequestsOverlay(TripModel trip) {
    if (_stoppedAccepting) return const SizedBox.shrink();

    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: StreamBuilder<List<RideRequestModel>>(
        stream: _requestsStream ??= _requestsService.getMatchingRequestsStream(
          driverOrigin: trip.origin,
          driverDestination: trip.destination,
          radiusKm: 5.0,
        ),
        builder: (context, snapshot) {
          final requests = snapshot.data ?? [];
          _pendingRequests = requests;

          if (requests.isEmpty) {
            return const SizedBox.shrink();
          }

          // Anunciar solicitudes nuevas por TTS
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _announceNewRequests(requests);
          });

          final displayRequests = requests.take(2).toList();

          // Calcular desvíos fuera del build
          for (final request in displayRequests) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _calculateDeviation(request);
            });
          }

          return Column(
            children: [
              if (requests.length > 2)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '+${requests.length - 2} solicitudes más',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              ...displayRequests.map((request) {
                return _buildRequestCard(request, trip);
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRequestCard(RideRequestModel request, TripModel trip) {
    final deviation = _deviationsCache[request.requestId];

    return FutureBuilder<UserModel?>(
      future: _getUserInfo(request.passengerId),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                context.push(
                  '/driver/passenger-request/${widget.tripId}/${request.requestId}',
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      backgroundImage: user?.profilePhotoUrl != null
                          ? NetworkImage(user!.profilePhotoUrl!)
                          : null,
                      child: user?.profilePhotoUrl == null
                          ? const Icon(Icons.person, color: AppColors.primary)
                          : null,
                    ),

                    const SizedBox(width: 12),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.firstName ?? 'Pasajero',
                            style: AppTextStyles.body2.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            request.pickupPoint.name,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Desvío y precio
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (deviation != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: deviation <= 5
                                  ? AppColors.success.withOpacity(0.1)
                                  : AppColors.warning.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '+$deviation min',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: deviation <= 5
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.speed_rounded, size: 14, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Taxímetro',
                              style: AppTextStyles.body2.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(width: 8),

                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // OVERLAY DE ESPERA
  // ============================================================

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
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.hourglass_top,
                          size: 40,
                          color: AppColors.warning,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

                Text(
                  'Esperando pasajero',
                  style: AppTextStyles.h3,
                ),

                const SizedBox(height: 8),

                Text(
                  _waitingForPassenger?.pickupPoint?.name ?? 'Punto de recogida',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Timer
                Text(
                  '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: AppTextStyles.h1.copyWith(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: _waitSecondsRemaining < 60
                        ? AppColors.error
                        : AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Tiempo restante de espera',
                  style: AppTextStyles.caption,
                ),

                const SizedBox(height: 24),

                // Botón de chat
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (_waitingForPassenger != null) {
                        final passengerId = _waitingForPassenger!.userId;
                        final passengerName = _passengerNames[passengerId] ?? 'Pasajero';
                        ChatBottomSheet.show(
                          context,
                          tripId: widget.tripId,
                          passengerId: passengerId,
                          currentUserId: _currentTrip?.driverId ?? '',
                          currentUserRole: 'conductor',
                          isActive: true,
                          otherUserName: passengerName,
                        );
                      }
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('Mensaje al pasajero'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Botones de acción
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _handlePassengerNoShow,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('No llegó'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _handlePassengerPickedUp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Ya subió'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BOTONES DE ACCIÓN
  // ============================================================

  /// Chip superior "No recibir más pasajeros" (se muestra arriba del mapa)
  Widget _buildStopAcceptingChip(TripModel trip) {
    final bool isFull = trip.availableSeats <= 0;
    if (_stoppedAccepting || isFull) return const SizedBox.shrink();

    return Positioned(
      top: 100,
      left: 16,
      right: 16,
      child: Center(
        child: GestureDetector(
          onTap: () {
            setState(() => _stoppedAccepting = true);
            _ttsService.speakAnnouncement('No se recibirán más pasajeros');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Text(
                  'No recibir más pasajeros',
                  style: AppTextStyles.body2.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(TripModel trip) {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _completeTrip,
            icon: const Icon(Icons.flag),
            label: const Text('Finalizar viaje'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
          ),
        ),
      ),
    );
  }
}
