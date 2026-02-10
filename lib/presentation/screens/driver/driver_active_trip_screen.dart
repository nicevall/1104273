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
import '../../../data/services/notification_service.dart';
import '../../widgets/driver/taximeter_widget.dart';
import '../../widgets/driver/fare_summary_dialog.dart';
import '../../../core/utils/car_marker_generator.dart';
import 'rate_passenger_screen.dart';
import '../../../data/models/chat_message.dart';
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
  final Map<String, int?> _etaCache = {};
  final Set<String> _announcedRequests = {};
  bool _stoppedAccepting = false;
  DateTime? _lastBackPressTime;

  // === Push GPS a Firestore ===
  DateTime? _lastLocationPush;
  static const _locationPushInterval = Duration(milliseconds: 1500);

  // === Performance: car icon cache + camera throttle ===
  BitmapDescriptor? _carIcon;
  double _lastCameraLat = 0;
  double _lastCameraLng = 0;
  double _lastCameraHeading = 0;

  // === Throttle global de cámara (máx 2 animaciones/seg) ===
  DateTime? _lastCameraAnim;
  static const _cameraAnimInterval = Duration(milliseconds: 300);


  // === Cache para evitar _updateTripMarkers innecesarios ===
  String _lastTripMarkersHash = '';

  // === Estado de espera en punto de recogida ===
  bool _isWaitingAtPickup = false;
  TripPassenger? _waitingForPassenger;
  Timer? _waitTimer;
  int _waitSecondsRemaining = 0;
  bool _isPausedForPickup = false;
  bool _waitTimerExpired = false;
  final Set<String> _processedPickups = {}; // Pickups ya procesados (evita re-trigger)

  // === Taxímetro ===
  final _taximeterService = TaximeterService();
  Map<String, TaximeterSession> _activeMeterSessions = {};
  final Map<String, String> _passengerNames = {};
  DateTime? _lastMeterSync;
  static const _meterSyncInterval = Duration(seconds: 30);

  // === Chat: unread messages por pasajero ===
  final Map<String, int> _unreadCounts = {}; // passengerId → unread count
  final Map<String, int> _lastSeenCounts = {}; // passengerId → last seen count
  final Map<String, StreamSubscription<List<ChatMessage>>> _chatSubs = {};
  String? _selectedChatPassengerId; // Tab activo del chat (browser-tab style)

  // === Bottom sheet de espera: expandido = timer expirado ===
  bool _waitSheetExpanded = false;

  // === Suscripción a eventos de abrir chat desde notificaciones ===
  StreamSubscription<Map<String, String>>? _openChatSub;

  // === Animaciones ===
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _requestSlideController;
  late Animation<Offset> _requestSlideAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Suprimir notificaciones de solicitudes (ya las ve en la pantalla)
    NotificationService().suppressType('new_ride_request');
    _initAnimations();
    _loadCarIcon();
    _startLocationTracking();
    _startCompass();
    _loadInitialData();
    _listenForChatOpen();
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

  /// Interceptar back del sistema cuando esta pantalla es la ruta raíz
  @override
  Future<bool> didPopRoute() async {
    await _onWillPop();
    return true; // true = ya manejamos el evento, no salir de la app
  }

  /// Escuchar brújula del dispositivo para orientar la cámara
  double _lastCompassBearing = 0; // Último bearing aplicado a la cámara
  DateTime? _lastCompassUpdate;
  static const _compassInterval = Duration(milliseconds: 300);

  // Brújula real activada (producción)
  // En true: el mapa se orienta según el giroscopio/magnetómetro del teléfono
  static const _useCompass = true;

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

  /// Escuchar eventos de abrir chat desde notificaciones tocadas
  void _listenForChatOpen() {
    _openChatSub = NotificationService().onOpenChatRequested.listen((data) {
      final tripId = data['tripId'] ?? '';
      final passengerId = data['passengerId'] ?? '';
      if (tripId != widget.tripId || !mounted) return;

      // Buscar el pasajero que envió el mensaje
      String chatPassengerId = passengerId;
      if (chatPassengerId.isEmpty && _currentTrip != null) {
        // Si no viene passengerId, usar el primer pasajero accepted/picked_up
        final eligible = _currentTrip!.passengers.where(
          (p) => p.status == 'accepted' || p.status == 'picked_up',
        );
        if (eligible.isNotEmpty) chatPassengerId = eligible.first.userId;
      }

      if (chatPassengerId.isEmpty) return;

      final name = _passengerNames[chatPassengerId] ?? 'Pasajero';
      final passenger = _currentTrip?.passengers.firstWhere(
        (p) => p.userId == chatPassengerId,
        orElse: () => _currentTrip!.passengers.first,
      );
      final isActive = passenger?.status == 'accepted';

      debugPrint('🔔 Abriendo chat desde notificación: $chatPassengerId');

      ChatBottomSheet.show(
        context,
        tripId: widget.tripId,
        passengerId: chatPassengerId,
        currentUserId: _currentTrip?.driverId ?? '',
        currentUserRole: 'conductor',
        isActive: isActive,
        otherUserName: name,
      );
    });
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

      // GPS de alta precisión (producción)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() => _currentPosition = position);
        _updateDriverMarker();
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          // GPS de alta precisión (producción)
          accuracy: LocationAccuracy.high,
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
      // Recalcular bearing con threshold de 2m
      if (dist > 2) {
        carHeading = Geolocator.bearingBetween(
          _lastValidPosition!.latitude,
          _lastValidPosition!.longitude,
          position.latitude,
          position.longitude,
        );
      }
    }

    // Calcular si la posición cambió visiblemente (>1m)
    final posChanged = Geolocator.distanceBetween(
      _lastCameraLat, _lastCameraLng,
      position.latitude, position.longitude,
    ) > 1;

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

      // Preview: a <100m del fin del step actual, anunciar "Luego, [siguiente]"
      if (distToEnd < 100 && !_hasAnnouncedCurrentStep) {
        newHasAnnounced = true;
        final distText = 'En ${distToEnd.round()} metros';
        if (_currentStepIndex + 1 < _currentRoute!.steps.length) {
          final nextStep = _currentRoute!.steps[_currentStepIndex + 1];
          _ttsService.speakNavigation('$distText, luego ${nextStep.instruction}');
        } else {
          _ttsService.speakNavigation('Estás llegando a tu destino.');
        }
      }

      // Avanzar al siguiente step cuando está a <30m del endpoint
      if (distToEnd < 30) {
        newStepIndex = _currentStepIndex + 1;
        newHasAnnounced = false;
        // Anunciar la instrucción del nuevo step actual al entrar
        if (newStepIndex < _currentRoute!.steps.length) {
          final newStep = _currentRoute!.steps[newStepIndex];
          _ttsService.speakNavigation(newStep.instruction);
        }
      }
    }

    final navChanged = newStepIndex != _currentStepIndex;

    // 3. Taxímetro (con groupSize para descuento grupal)
    Map<String, TaximeterSession>? updatedMeterSessions;
    if (_taximeterService.hasActiveSessions) {
      final pickedUpCount = _currentTrip?.passengers
          .where((p) => p.status == 'picked_up')
          .length ?? 0;
      final updated = _taximeterService.onGpsUpdate(
        position.latitude, position.longitude, DateTime.now(),
        groupSize: pickedUpCount > 0 ? pickedUpCount : 1,
      );
      updatedMeterSessions = Map.from(updated);
    }

    final meterChanged = updatedMeterSessions != null;

    // Fix C2: Solo setState si algo cambió visiblemente
    if (posChanged || navChanged || meterChanged) {
      // 1. Marker — posición GPS directa, rotación sigue el bearing
      final driverMarker = Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(position.latitude, position.longitude),
        icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        rotation: _useCompass ? _compassHeading : _lastCameraHeading,
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
      rotation: 0, // Siempre apunta al norte — el mapa rota con bearing
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
        // Encontrar el step en el que está el conductor actualmente
        // Busca el step cuyo startLocation está más cerca Y cuyo endLocation está más lejos
        // (es decir, el conductor está "dentro" del step, avanzando hacia el end)
        int closestStep = 0;
        if (_currentPosition != null && route.steps.isNotEmpty) {
          double minDist = double.infinity;
          for (int i = 0; i < route.steps.length; i++) {
            final distToStart = Geolocator.distanceBetween(
              _currentPosition!.latitude, _currentPosition!.longitude,
              route.steps[i].startLocation.latitude, route.steps[i].startLocation.longitude,
            );
            final distToEnd = Geolocator.distanceBetween(
              _currentPosition!.latitude, _currentPosition!.longitude,
              route.steps[i].endLocation.latitude, route.steps[i].endLocation.longitude,
            );
            // El conductor está en este step si está cerca del inicio
            // y el final está más lejos (aún no lo completó)
            if (distToStart < minDist && distToEnd >= distToStart) {
              minDist = distToStart;
              closestStep = i;
            }
          }
        }

        setState(() {
          _currentRoute = route;
          _currentStepIndex = closestStep;
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

        // Anunciar instrucción del paso actual
        if (route.steps.isNotEmpty && closestStep < route.steps.length) {
          final currentStep = route.steps[closestStep];
          await _ttsService.speakNavigation(currentStep.instruction);
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
  static const _offRouteCheckInterval = Duration(seconds: 5);

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

    // Si está a más de 80m de la ruta → recalcular
    if (minDist > 80) {
      debugPrint('Conductor se desvió ${minDist.round()}m, recalculando ruta...');
      _ttsService.speakAnnouncement('Recalculando ruta.');
      _calculateRoute();
    }
  }

  // ============================================================
  // AUTO-COMPLETAR VIAJE AL LLEGAR AL DESTINO
  // ============================================================

  /// Mostrar bottom sheet con tabs de pago por pasajero al finalizar viaje
  Future<void> _showPaymentTabsSheet({List<TripPassenger>? forcePassengers}) async {
    if (!mounted || _currentTrip == null) return;

    // Capturar driverId AHORA antes de que _currentTrip pueda cambiar
    final driverId = _currentTrip!.driverId;

    // Usar pasajeros forzados si se pasan, o buscar picked_up actuales
    final pickedUpPassengers = forcePassengers ??
        _currentTrip!.passengers
            .where((p) => p.status == 'picked_up')
            .toList();

    debugPrint('💰 _showPaymentTabsSheet: ${pickedUpPassengers.length} pasajeros (forced=${forcePassengers != null})');

    if (pickedUpPassengers.isEmpty) {
      debugPrint('💰 No hay pasajeros picked_up, finalizando directo');
      _finalizeTrip();
      return;
    }

    // 1. Detener TODOS los taxímetros y guardar sesiones
    final Map<String, TaximeterSession> sessions = {};
    for (final passenger in pickedUpPassengers) {
      final session = _taximeterService.stopMeter(passenger.userId);
      if (session != null) sessions[passenger.userId] = session;

      // Drop off en Firestore
      try {
        await _tripsService.dropOffPassenger(
          widget.tripId,
          passenger.userId,
          finalFare: session?.currentFare ?? 0,
          dropoffLatitude: _currentPosition?.latitude ?? 0,
          dropoffLongitude: _currentPosition?.longitude ?? 0,
          totalDistanceKm: session?.totalDistanceKm ?? 0,
          totalWaitMinutes: session?.totalWaitMinutes ?? 0,
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
        debugPrint('Error en drop-off: $e');
      }
    }

    // 2. Limpiar UI de taxímetros
    setState(() {
      _activeMeterSessions.clear();
    });

    // 3. TTS
    await _ttsService.speakAnnouncement(
      'Viaje finalizado. Confirma el pago de cada pasajero.',
    );

    // 4. Mostrar bottom sheet con tabs (o directo si solo hay 1)
    if (!mounted) return;

    final paymentResults = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _PaymentTabsSheet(
        passengers: pickedUpPassengers,
        sessions: sessions,
        passengerNames: _passengerNames,
        tripId: widget.tripId,
        tripsService: _tripsService,
        firestoreService: FirestoreService(),
      ),
    );

    // 5. Actualizar pagos en Firestore según resultados
    if (paymentResults != null && mounted) {
      for (final entry in paymentResults.entries) {
        final passengerId = entry.key;
        final status = entry.value; // 'paid' o 'unpaid'
        try {
          await _tripsService.updatePassengerPaymentStatus(
            widget.tripId,
            passengerId,
            status,
          );
        } catch (e) {
          debugPrint('Error actualizando pago de $passengerId: $e');
        }
      }
    }

    // 6. Calificar a cada pasajero secuencialmente
    for (final passenger in pickedUpPassengers) {
      if (!mounted) break;
      final name = _passengerNames[passenger.userId] ?? 'Pasajero';
      final session = sessions[passenger.userId];
      debugPrint('💰 Mostrando rating para ${passenger.userId} ($name)');
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RatePassengerScreen(
            tripId: widget.tripId,
            driverId: driverId,
            passengerId: passenger.userId,
            passengerName: name,
            fare: session?.currentFare ?? 0,
          ),
        ),
      );
    }

    // 7. Finalizar viaje
    debugPrint('💰 Todos los pasajeros procesados → finalizando viaje');
    _finalizeTrip();
  }

  /// Completar el viaje (enviar evento al BLoC)
  /// Await TTS para que termine de hablar antes de navegar a home
  Future<void> _finalizeTrip() async {
    if (mounted) {
      await _ttsService.speakAnnouncement('Viaje finalizado. ¡Buen viaje!');
      if (mounted) {
        context.read<TripBloc>().add(
              CompleteTripEvent(tripId: widget.tripId),
            );
      }
    }
  }

  // ============================================================
  // TTS PARA SOLICITUDES ENTRANTES
  // ============================================================

  void _announceNewRequests(List<RideRequestModel> requests) {
    print('[TTS-DEBUG] _announceNewRequests llamado con ${requests.length} requests. Ya anunciados: ${_announcedRequests.length}');
    for (final request in requests) {
      print('[TTS-DEBUG] Revisando request ${request.requestId} - ya anunciado: ${_announcedRequests.contains(request.requestId)}');
      if (_announcedRequests.contains(request.requestId)) continue;
      _announcedRequests.add(request.requestId);

      print('[TTS-DEBUG] NUEVO request ${request.requestId} (pasajero: ${request.passengerId}, pago: ${request.paymentMethod})');

      // Obtener info del usuario y calcular ETA en paralelo
      final userFuture = _getUserInfo(request.passengerId);
      final etaFuture = _calculateEta(request);

      Future.wait<dynamic>([etaFuture, userFuture]).then((results) {
        if (!mounted) return;
        final user = results[1] as UserModel?;
        final name = user?.firstName ?? 'Un pasajero';
        final pickup = request.pickupPoint.name;
        final eta = _etaCache[request.requestId];

        print('[TTS-DEBUG] user=${user?.firstName}, eta=$eta, paymentMethod=${request.paymentMethod}');

        final buffer = StringBuffer();
        buffer.write('Nueva solicitud. $name en $pickup.');

        if (eta != null) {
          buffer.write(' Está a $eta minutos.');
        }

        buffer.write(' Pago con: ${request.paymentMethod.toLowerCase()}.');

        if (request.hasPet) {
          buffer.write(' Lleva mascota.');
        }
        if (request.hasLargeObject) {
          buffer.write(' Lleva objeto grande.');
        }

        print('[TTS-DEBUG] Texto final: ${buffer.toString()}');
        _ttsService.speakRequest(buffer.toString());
      }).catchError((e) {
        print('[TTS-DEBUG] ERROR: $e');
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
      (p) => p.status == 'accepted' && p.pickupPoint != null && !_processedPickups.contains(p.userId),
    ).toList();

    for (final passenger in pendingPickups) {
      final distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        passenger.pickupPoint!.latitude,
        passenger.pickupPoint!.longitude,
      );

      debugPrint('📍 Distancia al pickup de ${passenger.userId}: ${distance.toStringAsFixed(1)}m (umbral: 50m)');

      if (distance < 50) {
        _processedPickups.add(passenger.userId);
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

    // Escribir timestamp + flag en Firestore para sincronizar con pasajero
    // driverArrivedNotified: true dispara la Cloud Function de notificación
    FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .update({
      'waitingStartedAt': FieldValue.serverTimestamp(),
      'driverArrivedNotified': true,
    });

    debugPrint('⏱️ Timer de espera iniciado: ${maxWait}min');

    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_waitSecondsRemaining > 0) {
        setState(() => _waitSecondsRemaining--);
      } else {
        timer.cancel();
        setState(() => _waitTimerExpired = true);
        // Auto-expandir el bottom sheet al expirar
        _expandWaitSheet();
      }
    });
  }

  /// Expande el bottom sheet de espera (expired view con gracia)
  void _expandWaitSheet() {
    if (mounted) setState(() => _waitSheetExpanded = true);
  }

  /// Colapsa el bottom sheet de espera (timer activo)
  void _collapseWaitSheet() {
    if (mounted) setState(() => _waitSheetExpanded = false);
  }

  /// Reinicia el timer con minutos de gracia extra
  void _restartTimerWithGrace(int graceMinutes) {
    _waitTimer?.cancel();
    setState(() {
      _waitSecondsRemaining = graceMinutes * 60;
      _waitTimerExpired = false;
    });

    // Colapsar el sheet de vuelta al tamaño normal
    _collapseWaitSheet();

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
        setState(() => _waitTimerExpired = true);
        _expandWaitSheet();
      }
    });
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
        groupSize: pickedUp.length,
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

  Future<void> _handlePassengerPickedUp() async {
    if (_waitingForPassenger == null || _currentTrip == null) return;

    final passengerId = _waitingForPassenger!.userId;

    context.read<TripBloc>().add(
      UpdatePassengerStatusEvent(
        tripId: widget.tripId,
        passengerId: passengerId,
        newStatus: 'picked_up',
      ),
    );

    // === Iniciar taxímetro para este pasajero (con groupSize para descuento) ===
    if (_currentPosition != null) {
      final currentPickedUp = _currentTrip!.passengers
          .where((p) => p.status == 'picked_up')
          .length;
      final session = _taximeterService.startMeter(
        passengerId: passengerId,
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
        groupSize: currentPickedUp > 0 ? currentPickedUp : 1,
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

    await _ttsService.speakAnnouncement('Pasajero recogido. Taxímetro iniciado.');

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
      _waitTimerExpired = false;
      _waitSheetExpanded = false;
    });
  }

  // ============================================================
  // NAVEGACIÓN Y ACCIONES
  // ============================================================

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar viaje?'),
        content: const Text(
          'Los pasajeros que hayas aceptado serán notificados.',
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
                  child: const Text('Continuar'),
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
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (result == true) {
      context.read<TripBloc>().add(CancelTripEvent(tripId: widget.tripId));
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
          discountPercent: session.discountPercent,
          fareBeforeDiscount: session.fareBeforeDiscount,
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

    // TTS — esperar a que termine antes de mostrar diálogo
    await _ttsService.speakAnnouncement(
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
      } else if (pagoConfirmado == false && mounted) {
        // Flujo "No pagó" — confirmación + razón obligatoria + strike
        await _handleUnpaidPassenger(passengerId, name, finalSession);
      }
    }

    // Recalcular ruta si quedan pasajeros
    if (_taximeterService.hasActiveSessions) {
      _calculateRoute();
    }
  }

  /// Flujo cuando el conductor reporta "No pagó"
  /// 1. Confirmación  2. Razón obligatoria (10-100 chars)  3. Strike + guardar
  Future<void> _handleUnpaidPassenger(
    String passengerId,
    String passengerName,
    TaximeterSession session,
  ) async {
    // ── Paso 1: Confirmación ──
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Estás seguro?'),
        content: Text(
          'Reportar que $passengerName no realizó el pago.\n\n'
          'Esto aplicará un strike a su cuenta.',
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
                  child: const Text('Cancelar'),
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
                  child: const Text(
                    'Sí, no pagó',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // ── Paso 2: Razón obligatoria ──
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Describe la situación'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Explica brevemente por qué $passengerName no pagó.',
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reasonController,
                      maxLength: 100,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Ej: Se bajó sin pagar, dijo que no tenía efectivo...',
                        hintStyle: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      validator: (value) {
                        if (value == null || value.trim().length < 10) {
                          return 'Mínimo 10 caracteres';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
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
                        onPressed: () => Navigator.pop(ctx, null),
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
                        onPressed: reasonController.text.trim().length >= 10
                            ? () {
                                if (formKey.currentState!.validate()) {
                                  Navigator.pop(
                                    ctx,
                                    reasonController.text.trim(),
                                  );
                                }
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.error.withValues(alpha: 0.4),
                          disabledForegroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Reportar',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();

    if (reason == null || !mounted) return;

    // ── Paso 3: Guardar en Firestore + aplicar strike ──
    try {
      // Actualizar paymentStatus a 'unpaid' con nota
      await _tripsService.updatePassengerPaymentStatus(
        widget.tripId,
        passengerId,
        'unpaid',
        paymentNote: reason,
      );

      // Aplicar strike al pasajero
      final newStrikes = await _firestoreService.applyPaymentStrike(passengerId);

      if (mounted) {
        String strikeMsg;
        if (newStrikes >= 3) {
          strikeMsg = 'La cuenta de $passengerName ha sido bloqueada permanentemente (Strike 3/3).';
        } else if (newStrikes == 2) {
          strikeMsg = 'Strike $newStrikes/3 aplicado. $passengerName suspendido por 2 semanas.';
        } else {
          strikeMsg = 'Strike $newStrikes/3 aplicado. $passengerName suspendido por 1 semana.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strikeMsg),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error al reportar falta de pago: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reportar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }

    // ── Paso 4: Navegar a pantalla de calificación ──
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RatePassengerScreen(
            tripId: widget.tripId,
            driverId: _currentTrip?.driverId ?? '',
            passengerId: passengerId,
            passengerName: passengerName,
            fare: session.currentFare,
          ),
        ),
      );
    }
  }

  /// Restaurar taxímetros de emergencia para pasajeros picked_up
  /// cuando se perdieron las sesiones (ej: hot restart, reconexión)
  void _restoreTaximetersForFinish(List<TripPassenger> pickedUp) {
    for (final p in pickedUp) {
      if (_taximeterService.getSession(p.userId) != null) continue;

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
        groupSize: pickedUp.length,
      );

      _activeMeterSessions[p.userId] = session;
      _passengerNames.putIfAbsent(p.userId, () => 'Pasajero');
      _getUserInfo(p.userId).then((user) {
        if (user != null && mounted) {
          setState(() => _passengerNames[p.userId] = user.firstName);
        }
      });

      debugPrint('🔄 Taxímetro restaurado (finish) para ${p.userId}: \$${session.currentFare.toStringAsFixed(2)}');
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
                    // CAPTURAR datos ANTES de cerrar diálogo
                    // _currentTrip puede cambiar por StreamBuilder en cualquier momento
                    var pickedUp = _currentTrip?.passengers
                        .where((p) => p.status == 'picked_up')
                        .toList() ?? [];

                    final hasMeters = _taximeterService.hasActiveSessions;

                    debugPrint('💰 Finalizar: ${pickedUp.length} picked_up, '
                        'hasActiveSessions=$hasMeters, '
                        'meterCount=${_taximeterService.activeCount}');

                    // Si hay taxímetros activos pero 0 picked_up en _currentTrip,
                    // reconstruir la lista desde los taxímetros activos
                    if (pickedUp.isEmpty && hasMeters) {
                      final meterPassengerIds = _taximeterService.activeSessions
                          .map((s) => s.passengerId)
                          .toList();
                      pickedUp = (_currentTrip?.passengers ?? [])
                          .where((p) => meterPassengerIds.contains(p.userId))
                          .toList();
                      debugPrint('💰 Reconstruido desde taxímetros: ${pickedUp.length} pasajeros');
                    }

                    Navigator.pop(ctx);

                    if (pickedUp.isNotEmpty) {
                      // Restaurar taxímetros si se perdieron las sesiones
                      if (!hasMeters) {
                        _restoreTaximetersForFinish(pickedUp);
                      }
                      await _showPaymentTabsSheet(forcePassengers: pickedUp);
                    } else {
                      // No hay pasajeros ni taxímetros, finalizar directamente
                      debugPrint('💰 No hay pasajeros ni taxímetros → finalizar directo');
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

  /// Calcula ETA: tiempo de viaje desde posición actual del conductor al pickup del pasajero
  Future<void> _calculateEta(RideRequestModel request) async {
    if (_etaCache.containsKey(request.requestId)) return;

    // Usar posición actual del conductor, o posición del trip origin como fallback
    final driverLat = _currentPosition?.latitude ?? _currentTrip?.origin.latitude;
    final driverLng = _currentPosition?.longitude ?? _currentTrip?.origin.longitude;
    if (driverLat == null || driverLng == null) {
      print('[ETA-DEBUG] sin posicion del conductor, no se puede calcular');
      return;
    }

    print('[ETA-DEBUG] calculando desde ($driverLat, $driverLng) a (${request.pickupPoint.latitude}, ${request.pickupPoint.longitude})');

    try {
      final route = await _directionsService.getRoute(
        originLat: driverLat,
        originLng: driverLng,
        destLat: request.pickupPoint.latitude,
        destLng: request.pickupPoint.longitude,
      );

      print('[ETA-DEBUG] resultado: ${route?.durationMinutes} min');

      if (mounted) {
        setState(() {
          _etaCache[request.requestId] = route?.durationMinutes;
        });
      }
    } catch (e) {
      print('[ETA-DEBUG] error: $e');
      if (mounted) {
        setState(() {
          _etaCache[request.requestId] = null;
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
      if (mounted) setState(() {}); // Actualizar cards con nombre real
      return user;
    } catch (e) {
      // No cachear en error — permite reintento en el siguiente stream event
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
    NotificationService().unsuppressType('new_ride_request');
    _openChatSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _compassSubscription?.cancel();
    _waitTimer?.cancel();
    // Cancelar todos los streams de chat
    for (final sub in _chatSubs.values) {
      sub.cancel();
    }
    _chatSubs.clear();
    _pulseController.dispose();
    _requestSlideController.dispose();
    _mapController?.dispose();
    // NO llamar _ttsService.stop() — es singleton, puede seguir hablando
    // al navegar a otra pantalla (ej: "Viaje finalizado")
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
            // NO llamar _ttsService.stop() — TTS ya terminó en _finalizeTrip
            _navigateToHome();
          } else if (state is TripCancelled) {
            // NO llamar _ttsService.stop() — es singleton, no interrumpir
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

                // Sincronizar streams de chat para pasajeros aceptados
                _syncChatStreams(trip);

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

                  // Botones de acción (abajo del todo) — ocultos durante espera en pickup
                  if (!_isWaitingAtPickup)
                    _buildActionButtons(trip),

                  // Taxímetro flotante (encima de los botones de acción)
                  if (_activeMeterSessions.isNotEmpty && !_isWaitingAtPickup)
                    Positioned(
                      bottom: _calculateTaximeterBottom(trip),
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

                  // Bottom sheet de espera deslizable (no bloquea solicitudes ni taxímetro)
                  if (_isWaitingAtPickup)
                    _buildWaitingBottomSheet(),
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

    // Verificar si hay un paso siguiente para el preview
    final hasNextStep = _currentStepIndex + 1 < _currentRoute!.steps.length;
    final nextStep = hasNextStep ? _currentRoute!.steps[_currentStepIndex + 1] : null;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 145,
      left: 16,
      right: 16,
      child: Column(
        children: [
          // Paso actual
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(14),
                bottom: Radius.circular(hasNextStep ? 0 : 14),
              ),
              boxShadow: hasNextStep ? [] : [
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

                // Instrucción + distancia
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
              ],
            ),
          ),

          // Preview del siguiente paso
          if (hasNextStep)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.75),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
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
                  Icon(
                    _getManeuverIcon(nextStep!.maneuver),
                    color: Colors.white.withOpacity(0.7),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Luego: ${nextStep.instruction}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
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
        ),
        builder: (context, snapshot) {
          final requests = snapshot.data ?? [];
          _pendingRequests = requests;

          if (requests.isEmpty) {
            return const SizedBox.shrink();
          }

          // Pre-fetch info de usuarios para que el nombre esté listo al renderizar
          for (final request in requests) {
            if (!_usersCache.containsKey(request.passengerId)) {
              _getUserInfo(request.passengerId);
            }
          }

          // Anunciar solicitudes nuevas por TTS
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _announceNewRequests(requests);
          });

          // Calcular ETA para hasta 10 solicitudes (no solo las 2 mostradas)
          final requestsNeedingEta = requests
              .where((r) => !_etaCache.containsKey(r.requestId))
              .take(10);
          for (final request in requestsNeedingEta) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _calculateEta(request);
            });
          }

          // Ordenar por ETA (más cercano primero, sin ETA al final)
          final sortedRequests = List<RideRequestModel>.from(requests);
          sortedRequests.sort((a, b) {
            final etaA = _etaCache[a.requestId];
            final etaB = _etaCache[b.requestId];
            if (etaA != null && etaB != null) return etaA.compareTo(etaB);
            if (etaA != null) return -1;
            if (etaB != null) return 1;
            return a.requestedAt.compareTo(b.requestedAt);
          });

          final displayRequests = sortedRequests.take(2).toList();

          return Column(
            children: [
              if (sortedRequests.length > 2)
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
                    '+${sortedRequests.length - 2} solicitudes más',
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
    final eta = _etaCache[request.requestId];
    final user = _usersCache[request.passengerId];

    // Disparar fetch si aún no está en cache (se actualizará con setState)
    if (!_usersCache.containsKey(request.passengerId)) {
      _getUserInfo(request.passengerId);
    }

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
                      const SizedBox(height: 2),
                      // Método de pago
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            request.paymentMethod == 'Transferencia'
                                ? Icons.account_balance_outlined
                                : Icons.payments_outlined,
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            request.paymentMethod,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ETA y taxímetro
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (eta != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: eta <= 5
                              ? AppColors.success.withOpacity(0.1)
                              : AppColors.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: eta <= 5
                                  ? AppColors.success
                                  : AppColors.warning,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$eta min',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: eta <= 5
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                            ),
                          ],
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
  }

  // ============================================================
  // OVERLAY DE ESPERA
  // ============================================================

  /// Bottom sheet de espera en punto de recogida.
  /// Positioned(bottom:0) con AnimatedSize para expandir cuando expira el timer.
  Widget _buildWaitingBottomSheet() {
    final minutes = _waitSecondsRemaining ~/ 60;
    final seconds = _waitSecondsRemaining % 60;
    final pickupName =
        _waitingForPassenger?.pickupPoint?.name ?? 'Punto de recogida';
    final passengerName = _waitingForPassenger != null
        ? (_passengerNames[_waitingForPassenger!.userId] ?? 'Pasajero')
        : 'Pasajero';

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle decorativo
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // === Encabezado: icono + título ===
                  Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _waitTimerExpired
                                    ? AppColors.error.withOpacity(0.15)
                                    : AppColors.warning.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _waitTimerExpired
                                    ? Icons.timer_off
                                    : Icons.hourglass_top,
                                size: 22,
                                color: _waitTimerExpired
                                    ? AppColors.error
                                    : AppColors.warning,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _waitTimerExpired
                                  ? 'Se acabó el tiempo'
                                  : 'Esperando a $passengerName',
                              style: AppTextStyles.h3.copyWith(fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.location_on,
                                    size: 14,
                                    color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    pickupName,
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // === Timer grande ===
                  Text(
                    '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                    style: AppTextStyles.h1.copyWith(
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      color: _waitTimerExpired
                          ? AppColors.error
                          : _waitSecondsRemaining < 60
                              ? AppColors.error
                              : AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    _waitTimerExpired
                        ? 'Puedes dar tiempo de gracia'
                        : 'Tiempo restante de espera',
                    style: AppTextStyles.caption.copyWith(
                      color: _waitTimerExpired
                          ? AppColors.error
                          : AppColors.textSecondary,
                    ),
                  ),

                  // === Botones de gracia (solo cuando expiró) ===
                  if (_waitTimerExpired) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _restartTimerWithGrace(1),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
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
                            onPressed: () => _restartTimerWithGrace(2),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
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
                            onPressed: () => _restartTimerWithGrace(3),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('+3 min'),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),

                  // === Botón de chat con badge de unread ===
                  Builder(builder: (context) {
                    final waitUnread = _waitingForPassenger != null
                        ? (_unreadCounts[_waitingForPassenger!.userId] ?? 0)
                        : 0;
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_waitingForPassenger != null) {
                            final passengerId = _waitingForPassenger!.userId;
                            final name =
                                _passengerNames[passengerId] ?? 'Pasajero';
                            _markChatAsRead(passengerId);
                            ChatBottomSheet.show(
                              context,
                              tripId: widget.tripId,
                              passengerId: passengerId,
                              currentUserId: _currentTrip?.driverId ?? '',
                              currentUserRole: 'conductor',
                              isActive: true,
                              otherUserName: name,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble_outline, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Mensaje a $passengerName',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (waitUnread > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$waitUnread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 12),

                  // === Botones de acción ===
                  if (_waitTimerExpired)
                    // Timer expirado: No llegó + Ya subió
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _handlePassengerNoShow,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
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
                            onPressed: _handlePassengerPickedUp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Ya subió'),
                          ),
                        ),
                      ],
                    )
                  else
                    // Timer activo: solo Ya subió
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handlePassengerPickedUp,
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
            ),
          ),
        ),
    );
  }

  // ============================================================
  // BOTONES DE ACCIÓN
  // ============================================================

  /// Popup de confirmación para dejar de recibir pasajeros
  void _confirmStopAccepting() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿No recibir más pasajeros?'),
        content: const Text(
          'No recibirás nuevas solicitudes de pasajeros durante este viaje.',
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
                    setState(() => _stoppedAccepting = true);
                    _ttsService.speakAnnouncement('No se recibirán más pasajeros');
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
                    'Confirmar',
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
  // TAXIMETER POSITIONING
  // ============================================================

  /// Calcula el bottom offset del taxímetro según el tamaño del panel inferior.
  double _calculateTaximeterBottom(TripModel trip) {
    final acceptedPassengers = trip.passengers
        .where((p) => p.status == 'accepted' && p.userId.isNotEmpty)
        .toList();
    final hasAccepted = acceptedPassengers.isNotEmpty;
    final hasMultiple = acceptedPassengers.length > 1;
    final showStopButton = !_stoppedAccepting && trip.availableSeats > 0;

    // Panel: padding(14+16=30) + finalizar(48) + SafeArea bottom(~24) = 102 base
    double base = 102;
    if (hasAccepted) {
      if (hasMultiple) {
        // Tabs Chrome: barra tabs(40) + contenido(42) + spacing(12) = 94
        base += 106;
      } else {
        // Un solo pasajero: botón único(40) + spacing(12) = 52
        base += 60;
      }
    }
    if (showStopButton) base += 52; // stop button + spacing
    return base + 12; // margen extra
  }

  // ============================================================
  // CHAT UNREAD TRACKING
  // ============================================================

  /// Sincroniza streams de chat para pasajeros aceptados.
  /// Se llama desde el build (addPostFrameCallback) cuando cambian los pasajeros.
  void _syncChatStreams(TripModel trip) {
    final acceptedPassengers = trip.passengers
        .where((p) => p.status == 'accepted')
        .toList();
    final acceptedIds = acceptedPassengers.map((p) => p.userId).toSet();

    // Cancelar streams de pasajeros que ya no son "accepted" (ya abordaron o cancelaron)
    final toRemove = _chatSubs.keys.where((id) => !acceptedIds.contains(id)).toList();
    for (final id in toRemove) {
      _chatSubs[id]?.cancel();
      _chatSubs.remove(id);
      _unreadCounts.remove(id);
      _lastSeenCounts.remove(id);
    }

    // Si el tab seleccionado ya no existe, seleccionar otro
    if (_selectedChatPassengerId != null &&
        !acceptedIds.contains(_selectedChatPassengerId)) {
      _selectedChatPassengerId = acceptedIds.isNotEmpty ? acceptedIds.first : null;
    }

    // Crear streams para nuevos pasajeros "accepted"
    for (final passenger in acceptedPassengers) {
      if (_chatSubs.containsKey(passenger.userId)) continue;

      _lastSeenCounts[passenger.userId] = 0;
      _unreadCounts[passenger.userId] = 0;

      // Pre-cargar nombre del pasajero si no está en caché
      if (!_passengerNames.containsKey(passenger.userId)) {
        final cached = _usersCache[passenger.userId];
        if (cached != null) {
          _passengerNames[passenger.userId] = cached.firstName;
        } else {
          _getUserInfo(passenger.userId).then((user) {
            if (user != null && mounted) {
              setState(() => _passengerNames[passenger.userId] = user.firstName);
            }
          });
        }
      }

      _chatSubs[passenger.userId] = _chatService
          .getMessagesStream(widget.tripId, passenger.userId)
          .listen((messages) {
        if (!mounted) return;
        final passengerMsgs =
            messages.where((m) => m.senderRole == 'pasajero').length;
        final lastSeen = _lastSeenCounts[passenger.userId] ?? 0;
        final unread = (passengerMsgs - lastSeen).clamp(0, 99);
        if (unread != (_unreadCounts[passenger.userId] ?? 0)) {
          setState(() {
            _unreadCounts[passenger.userId] = unread;
          });
        }
      });

      // Auto-seleccionar primer tab si no hay ninguno seleccionado
      _selectedChatPassengerId ??= passenger.userId;
    }
  }

  /// Marca los mensajes del pasajero como leídos (al abrir el chat).
  void _markChatAsRead(String passengerId) {
    final current = (_lastSeenCounts[passengerId] ?? 0) +
        (_unreadCounts[passengerId] ?? 0);
    _lastSeenCounts[passengerId] = current;
    setState(() {
      _unreadCounts[passengerId] = 0;
    });
  }

  /// Total de mensajes no leídos de todos los pasajeros.
  int get _totalUnread =>
      _unreadCounts.values.fold(0, (sum, count) => sum + count);

  // ============================================================
  // BOTTOM PANEL (REDISEÑADO)
  // ============================================================

  Widget _buildActionButtons(TripModel trip) {
    final bool isFull = trip.availableSeats <= 0;
    final bool showStopButton = !_stoppedAccepting && !isFull;

    // Pasajeros con status "accepted" (en camino a recoger → chat activo)
    final acceptedPassengers = trip.passengers
        .where((p) => p.status == 'accepted' && p.userId.isNotEmpty)
        .toList();
    final hasAccepted = acceptedPassengers.isNotEmpty;

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // === Tabs de chat estilo Chrome con pasajeros aceptados ===
            if (hasAccepted) ...[
              _buildChatTabs(acceptedPassengers),
              const SizedBox(height: 12),
            ],

            // === Botón "Finalizar viaje" ===
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _completeTrip,
                icon: const Icon(Icons.flag, size: 20),
                label: const Text(
                  'Finalizar viaje',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),

            // === Botón "No recibir más pasajeros" ===
            if (showStopButton) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _confirmStopAccepting,
                  icon: Icon(Icons.block, size: 16, color: AppColors.textSecondary),
                  label: Text(
                    'No recibir más pasajeros',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: AppColors.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Ordena pasajeros aceptados por proximidad al conductor (más cercano primero).
  List<TripPassenger> _sortByProximity(List<TripPassenger> passengers) {
    if (_currentPosition == null) return passengers;
    final driverLat = _currentPosition!.latitude;
    final driverLng = _currentPosition!.longitude;

    final sorted = List<TripPassenger>.from(passengers);
    sorted.sort((a, b) {
      final distA = a.pickupPoint != null
          ? Geolocator.distanceBetween(
              driverLat, driverLng,
              a.pickupPoint!.latitude, a.pickupPoint!.longitude)
          : double.maxFinite;
      final distB = b.pickupPoint != null
          ? Geolocator.distanceBetween(
              driverLat, driverLng,
              b.pickupPoint!.latitude, b.pickupPoint!.longitude)
          : double.maxFinite;
      return distA.compareTo(distB);
    });
    return sorted;
  }

  /// Tabs estilo navegador Chrome para chat con pasajeros aceptados.
  /// Ordenados por proximidad al conductor (más cercano → primera tab).
  /// Cuando el pasajero aborda ("Ya subió"), su tab desaparece automáticamente.
  Widget _buildChatTabs(List<TripPassenger> acceptedPassengers) {
    final sorted = _sortByProximity(acceptedPassengers);

    // Si solo hay 1 pasajero → tab única con nombre completo + botón enviar
    if (sorted.length == 1) {
      final p = sorted.first;
      final name = _passengerNames[p.userId] ?? 'Pasajero';
      final unread = _unreadCounts[p.userId] ?? 0;

      return GestureDetector(
        onTap: () {
          _markChatAsRead(p.userId);
          ChatBottomSheet.show(
            context,
            tripId: widget.tripId,
            passengerId: p.userId,
            currentUserId: _currentTrip?.driverId ?? '',
            currentUserRole: 'conductor',
            isActive: true,
            otherUserName: name,
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 17, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'Mensaje a $name',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (unread > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Múltiples pasajeros → tabs estilo Chrome
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // === Barra de tabs ===
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: sorted.map((p) {
              final isSelected = _selectedChatPassengerId == p.userId;
              final name = _passengerNames[p.userId] ?? 'Pasajero';
              final unread = _unreadCounts[p.userId] ?? 0;
              final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedChatPassengerId = p.userId);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      // Borde sutil para separar tabs
                      border: isSelected
                          ? Border(
                              bottom: BorderSide(
                                color: AppColors.primary,
                                width: 2.5,
                              ),
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Círculo con inicial
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        // Nombre truncado
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        // Badge de unread
                        if (unread > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // === Contenido del tab seleccionado: botón de abrir chat ===
        Builder(
          builder: (context) {
            final selectedId = _selectedChatPassengerId;
            final selectedPassenger = sorted.firstWhere(
              (p) => p.userId == selectedId,
              orElse: () => sorted.first,
            );
            final name = _passengerNames[selectedPassenger.userId] ?? 'Pasajero';
            final pickup = selectedPassenger.pickupPoint?.name ?? 'Punto de recogida';

            return GestureDetector(
              onTap: () {
                _markChatAsRead(selectedPassenger.userId);
                ChatBottomSheet.show(
                  context,
                  tripId: widget.tripId,
                  passengerId: selectedPassenger.userId,
                  currentUserId: _currentTrip?.driverId ?? '',
                  currentUserRole: 'conductor',
                  isActive: true,
                  otherUserName: name,
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, size: 17, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Mensaje a $name',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            pickup,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white70),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ============================================================
// WIDGET: Bottom Sheet de pago con tabs por pasajero
// ============================================================

class _PaymentTabsSheet extends StatefulWidget {
  final List<TripPassenger> passengers;
  final Map<String, TaximeterSession> sessions;
  final Map<String, String> passengerNames;
  final String tripId;
  final TripsService tripsService;
  final FirestoreService firestoreService;

  const _PaymentTabsSheet({
    required this.passengers,
    required this.sessions,
    required this.passengerNames,
    required this.tripId,
    required this.tripsService,
    required this.firestoreService,
  });

  @override
  State<_PaymentTabsSheet> createState() => _PaymentTabsSheetState();
}

class _PaymentTabsSheetState extends State<_PaymentTabsSheet> {
  // Estado de pago por pasajero: null = pendiente, 'paid', 'unpaid'
  late Map<String, String?> _paymentStatus;
  late String _selectedPassengerId;

  @override
  void initState() {
    super.initState();
    _paymentStatus = {
      for (final p in widget.passengers) p.userId: null,
    };
    _selectedPassengerId = widget.passengers.first.userId;
  }

  int get _processedCount =>
      _paymentStatus.values.where((s) => s != null).length;

  bool get _allProcessed => _processedCount == widget.passengers.length;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Título
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined,
                    color: AppColors.primary, size: 24),
                const SizedBox(width: 10),
                Text(
                  'Confirmar pagos',
                  style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _allProcessed
                        ? AppColors.success.withValues(alpha: 0.12)
                        : AppColors.tertiary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_processedCount/${widget.passengers.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          _allProcessed ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tabs (solo si hay más de 1 pasajero)
          if (widget.passengers.length > 1) _buildTabs(),

          // Contenido del pasajero seleccionado
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomPadding + 20),
              child: _buildPassengerContent(_selectedPassengerId),
            ),
          ),

          // Botón continuar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _allProcessed
                      ? () {
                          // Retornar resultados de pago
                          Navigator.of(context).pop(
                            Map<String, String>.from(
                              _paymentStatus
                                  .map((k, v) => MapEntry(k, v ?? 'pending')),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: Text(
                    _allProcessed
                        ? 'Continuar a calificaciones'
                        : 'Procesa todos los pagos ($_processedCount/${widget.passengers.length})',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade200,
                    disabledForegroundColor: Colors.grey.shade500,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: widget.passengers.map((p) {
          final isSelected = _selectedPassengerId == p.userId;
          final name = widget.passengerNames[p.userId] ?? 'Pasajero';
          final status = _paymentStatus[p.userId];
          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

          // Colores según estado
          Color tabBg;
          Color? borderColor;
          if (isSelected) {
            tabBg = Colors.white;
            borderColor = status == 'paid'
                ? AppColors.success
                : status == 'unpaid'
                    ? AppColors.error
                    : AppColors.primary;
          } else {
            tabBg = status == 'paid'
                ? AppColors.success.withValues(alpha: 0.08)
                : status == 'unpaid'
                    ? AppColors.error.withValues(alpha: 0.08)
                    : Colors.transparent;
            borderColor = null;
          }

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPassengerId = p.userId),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: tabBg,
                  borderRadius: BorderRadius.circular(10),
                  border: borderColor != null
                      ? Border.all(color: borderColor, width: 1.5)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icono de estado o inicial
                    if (status == 'paid')
                      const Icon(Icons.check_circle,
                          size: 16, color: AppColors.success)
                    else if (status == 'unpaid')
                      const Icon(Icons.cancel, size: 16, color: AppColors.error)
                    else
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        name.split(' ').first,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPassengerContent(String passengerId) {
    final passenger = widget.passengers.firstWhere(
      (p) => p.userId == passengerId,
      orElse: () => widget.passengers.first,
    );
    final session = widget.sessions[passengerId];
    final name = widget.passengerNames[passengerId] ?? 'Pasajero';
    final status = _paymentStatus[passengerId];
    final isProcessed = status != null;

    if (session == null) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            'Sin datos de taxímetro para $name',
            style:
                AppTextStyles.body2.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    // Calcular desglose de tarifa
    final isNight = session.isNightTariff;
    final startFare = isNight
        ? PricingService.nightStartFare
        : PricingService.dayStartFare;
    final perKm =
        isNight ? PricingService.nightPerKm : PricingService.dayPerKm;
    final perWaitMin = isNight
        ? PricingService.nightPerWaitMinute
        : PricingService.dayPerWaitMinute;
    final minimumFare = isNight
        ? PricingService.nightMinimumFare
        : PricingService.dayMinimumFare;

    final distanceCost = session.totalDistanceKm * perKm;
    final waitCost = session.totalWaitMinutes * perWaitMin;
    final rawTotal = startFare + distanceCost + waitCost;
    final appliedMinimum = rawTotal < minimumFare;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre del pasajero + tarifa badge
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style:
                      AppTextStyles.h3.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      isNight
                          ? Icons.nightlight_round
                          : Icons.wb_sunny_rounded,
                      size: 14,
                      color: isNight ? Colors.indigo : Colors.amber.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isNight ? 'Nocturna' : 'Diurna',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            isNight ? Colors.indigo : Colors.amber.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Desglose de tarifa
          _buildFareRow('Arranque', '\$${startFare.toStringAsFixed(2)}'),
          _buildFareRow(
            '${session.totalDistanceKm.toStringAsFixed(1)} km',
            '\$${distanceCost.toStringAsFixed(2)}',
          ),
          if (session.totalWaitMinutes >= 0.5)
            _buildFareRow(
              '${session.totalWaitMinutes.round()} min espera',
              '\$${waitCost.toStringAsFixed(2)}',
            ),
          // Descuento grupal
          if (session.discountPercent > 0) ...[
            _buildFareRow(
              'Desc. grupo (${(session.discountPercent * 100).round()}%)',
              '-\$${(session.fareBeforeDiscount - session.currentFare).toStringAsFixed(2)}',
              valueColor: AppColors.success,
            ),
          ],
          const Divider(height: 20),

          // Total (con redondeo a $0.05 si es efectivo)
          Builder(builder: (context) {
            final isCash = passenger.paymentMethod == 'Efectivo';
            final displayFare = isCash
                ? PricingService.roundUpToNickel(session.currentFare)
                : session.currentFare;
            final wasRounded = isCash && displayFare != session.currentFare;

            return Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL',
                      style: AppTextStyles.body1
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '\$${displayFare.toStringAsFixed(2)}',
                      style: AppTextStyles.h2.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                if (appliedMinimum)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '(Tarifa mínima aplicada)',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (wasRounded)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '(Redondeado a \$0.05 — efectivo)',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 12),

          // Método de pago
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
                  style: AppTextStyles.body2
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          // Info de distancia y tiempo
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: Text(
                '${session.totalDistanceKm.toStringAsFixed(1)} km · ${session.elapsedFormatted}',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Botones de acción o estado procesado
          if (isProcessed)
            _buildProcessedBadge(status!)
          else
            _buildActionButtons(passengerId, name, session),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildProcessedBadge(String status) {
    final isPaid = status == 'paid';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: isPaid
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPaid
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPaid ? Icons.check_circle : Icons.cancel,
            color: isPaid ? AppColors.success : AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isPaid ? 'Pago confirmado' : 'Reportado como no pagó',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isPaid ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
      String passengerId, String name, TaximeterSession session) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => _handleUnpaid(passengerId, name, session),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'No pagó',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _paymentStatus[passengerId] = 'paid';
                // Auto-avanzar al siguiente pendiente
                _autoAdvanceToNext();
              });
            },
            icon: const Icon(Icons.payments, size: 18),
            label: const Text(
              'Pagó',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  /// Auto-avanzar a la siguiente tab pendiente
  void _autoAdvanceToNext() {
    final nextPending = widget.passengers.firstWhere(
      (p) => _paymentStatus[p.userId] == null,
      orElse: () => widget.passengers.first,
    );
    if (_paymentStatus[nextPending.userId] == null) {
      _selectedPassengerId = nextPending.userId;
    }
  }

  /// Flujo "No pagó" — confirmación + razón + strike
  Future<void> _handleUnpaid(
      String passengerId, String name, TaximeterSession session) async {
    // Step 1: Confirmar
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Estás seguro?'),
        content: Text(
          'Reportar que $name no realizó el pago.\n\n'
          'Esto aplicará un strike a su cuenta.',
        ),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  child: const Text('Cancelar'),
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
                  child: const Text('Sí, no pagó'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Step 2: Razón
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final controller = TextEditingController();
        final formKey = GlobalKey<FormState>();
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Motivo del no pago'),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                maxLength: 100,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Describe brevemente lo que pasó...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 10) {
                    return 'Mínimo 10 caracteres';
                  }
                  return null;
                },
                onChanged: (_) => setDialogState(() {}),
              ),
            ),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            actionsAlignment: MainAxisAlignment.center,
            actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, null),
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
                      onPressed: controller.text.trim().length >= 10
                          ? () {
                              if (formKey.currentState?.validate() ?? false) {
                                Navigator.pop(ctx, controller.text.trim());
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Reportar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (reason == null || !mounted) return;

    // Step 3: Aplicar strike + actualizar pago
    try {
      await widget.tripsService.updatePassengerPaymentStatus(
        widget.tripId,
        passengerId,
        'unpaid',
        paymentNote: reason,
      );
      final newStrikes =
          await widget.firestoreService.applyPaymentStrike(passengerId);

      String strikeMsg;
      if (newStrikes >= 3) {
        strikeMsg =
            'La cuenta de $name ha sido bloqueada permanentemente (Strike 3/3).';
      } else if (newStrikes == 2) {
        strikeMsg =
            'Strike $newStrikes/3 aplicado. $name suspendido por 2 semanas.';
      } else {
        strikeMsg =
            'Strike $newStrikes/3 aplicado. $name suspendido por 1 semana.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strikeMsg),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error aplicando strike: $e');
    }

    setState(() {
      _paymentStatus[passengerId] = 'unpaid';
      _autoAdvanceToNext();
    });
  }

  Widget _buildFareRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style:
                AppTextStyles.body2.copyWith(color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: AppTextStyles.body2.copyWith(
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
