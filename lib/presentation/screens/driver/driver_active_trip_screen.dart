// lib/presentation/screens/driver/driver_active_trip_screen.dart
// Pantalla principal del viaje activo del conductor
// Muestra: mapa con ubicación en tiempo real, ruta, solicitudes entrantes,
// temporizador de espera en puntos de recogida

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/ride_request_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/trips_service.dart';
import '../../../data/services/ride_requests_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/google_directions_service.dart';
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
    with TickerProviderStateMixin {
  // === Servicios ===
  final _tripsService = TripsService();
  final _requestsService = RideRequestsService();
  final _firestoreService = FirestoreService();
  final _directionsService = GoogleDirectionsService();

  // === Mapa ===
  GoogleMapController? _mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // === Viaje ===
  TripModel? _currentTrip;
  bool _isLoadingTrip = true;

  // === Solicitudes ===
  List<RideRequestModel> _pendingRequests = [];
  final Map<String, UserModel?> _usersCache = {};
  final Map<String, int?> _deviationsCache = {};

  // === Estado de espera en punto de recogida ===
  bool _isWaitingAtPickup = false;
  TripPassenger? _waitingForPassenger;
  Timer? _waitTimer;
  int _waitSecondsRemaining = 0;
  bool _isPausedForPickup = false;

  // === Animaciones ===
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _requestSlideController;
  late Animation<Offset> _requestSlideAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startLocationTracking();
    _loadInitialData();
  }

  void _initAnimations() {
    // Animación de pulso para el marcador de ubicación
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Animación para las solicitudes entrantes
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
    // El stream del viaje y solicitudes se manejan en el build
    setState(() => _isLoadingTrip = false);
  }

  void _startLocationTracking() async {
    try {
      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      // Obtener posición inicial
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() => _currentPosition = position);
        _updateDriverMarker();
      }

      // Escuchar cambios de posición
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Actualizar cada 10 metros
        ),
      ).listen((position) {
        if (mounted) {
          setState(() => _currentPosition = position);
          _updateDriverMarker();
          _checkArrivalAtPickup();
        }
      });
    } catch (e) {
      debugPrint('Error iniciando tracking: $e');
    }
  }

  void _updateDriverMarker() {
    if (_currentPosition == null) return;

    final driverMarker = Marker(
      markerId: const MarkerId('driver'),
      position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      anchor: const Offset(0.5, 0.5),
      rotation: _currentPosition!.heading,
    );

    setState(() {
      _markers = {
        driverMarker,
        ..._markers.where((m) => m.markerId.value != 'driver'),
      };
    });

    // Centrar mapa en la posición del conductor
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      ),
    );
  }

  void _checkArrivalAtPickup() {
    if (_currentTrip == null || _currentPosition == null || _isPausedForPickup) {
      return;
    }

    // Buscar pasajeros aceptados pendientes de recoger
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

      // Si está a menos de 50 metros del punto de recogida
      if (distance < 50) {
        _startWaitingTimer(passenger);
        break;
      }
    }
  }

  void _startWaitingTimer(TripPassenger passenger) {
    if (_isWaitingAtPickup) return;

    final maxWait = _currentTrip?.maxWaitMinutes ?? 5;

    setState(() {
      _isWaitingAtPickup = true;
      _isPausedForPickup = true;
      _waitingForPassenger = passenger;
      _waitSecondsRemaining = maxWait * 60;
    });

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
            Text('Tiempo de espera'),
          ],
        ),
        content: const Text(
          '¿El pasajero llegó al punto de encuentro?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handlePassengerNoShow();
            },
            child: const Text(
              'No llegó',
              style: TextStyle(color: AppColors.error),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handlePassengerPickedUp();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            child: const Text('Sí, subió'),
          ),
        ],
      ),
    );
  }

  void _handlePassengerPickedUp() {
    if (_waitingForPassenger == null || _currentTrip == null) return;

    // Actualizar estado del pasajero a "picked_up"
    context.read<TripBloc>().add(
      UpdatePassengerStatusEvent(
        tripId: widget.tripId,
        passengerId: _waitingForPassenger!.userId,
        newStatus: 'picked_up',
      ),
    );

    _resetWaitingState();
  }

  void _handlePassengerNoShow() {
    if (_waitingForPassenger == null || _currentTrip == null) return;

    // Mostrar confirmación
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pasajero no apareció'),
        content: const Text(
          '¿Confirmas que el pasajero no llegó al punto de encuentro? '
          'Se liberará el asiento y el pasajero recibirá una notificación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Actualizar estado del pasajero a "no_show"
              context.read<TripBloc>().add(
                UpdatePassengerStatusEvent(
                  tripId: widget.tripId,
                  passengerId: _waitingForPassenger!.userId,
                  newStatus: 'no_show',
                ),
              );
              _resetWaitingState();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  void _resetWaitingState() {
    _waitTimer?.cancel();
    setState(() {
      _isWaitingAtPickup = false;
      _isPausedForPickup = false;
      _waitingForPassenger = null;
      _waitSecondsRemaining = 0;
    });
  }

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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar viaje'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (result == true) {
      // Cancelar el viaje
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Todavía no'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<TripBloc>().add(
                CompleteTripEvent(tripId: widget.tripId),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            child: const Text('Sí, finalizar'),
          ),
        ],
      ),
    );
  }

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

  @override
  void dispose() {
    _positionStream?.cancel();
    _waitTimer?.cancel();
    _pulseController.dispose();
    _requestSlideController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

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
            _navigateToHome();
          } else if (state is TripCancelled) {
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
              _updateTripMarkers(trip);

              return Stack(
                children: [
                  // Mapa de fondo
                  _buildMap(trip),

                  // Overlay superior con info del viaje
                  _buildTopOverlay(trip),

                  // Solicitudes entrantes (si no está pausado)
                  if (!_isPausedForPickup)
                    _buildRequestsOverlay(trip),

                  // Timer de espera (si está esperando)
                  if (_isWaitingAtPickup)
                    _buildWaitingOverlay(),

                  // Botones de acción
                  _buildActionButtons(trip),
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

  void _updateTripMarkers(TripModel trip) {
    final newMarkers = <Marker>{};

    // Marcador de destino
    newMarkers.add(Marker(
      markerId: const MarkerId('destination'),
      position: LatLng(trip.destination.latitude, trip.destination.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(title: 'Destino', snippet: trip.destination.name),
    ));

    // Marcadores de puntos de recogida de pasajeros aceptados
    for (final passenger in trip.passengers) {
      if (passenger.status == 'accepted' && passenger.pickupPoint != null) {
        newMarkers.add(Marker(
          markerId: MarkerId('pickup_${passenger.userId}'),
          position: LatLng(
            passenger.pickupPoint!.latitude,
            passenger.pickupPoint!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: 'Recoger pasajero',
            snippet: passenger.pickupPoint!.name,
          ),
        ));
      }
    }

    // Mantener el marcador del conductor
    final driverMarker = _markers.where((m) => m.markerId.value == 'driver');

    setState(() {
      _markers = {...newMarkers, ...driverMarker};
    });
  }

  Widget _buildMap(TripModel trip) {
    final initialPosition = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : LatLng(trip.origin.latitude, trip.origin.longitude);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: initialPosition,
        zoom: 15,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        _updateDriverMarker();
      },
      markers: _markers,
      polylines: _polylines,
      myLocationEnabled: false, // Usamos nuestro propio marcador
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
                    // Botón atrás (con confirmación)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _onWillPop,
                    ),
                    const Spacer(),
                    // Badge de viaje activo
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

  Widget _buildRequestsOverlay(TripModel trip) {
    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: StreamBuilder<List<RideRequestModel>>(
        stream: _requestsService.getMatchingRequestsStream(
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

          // Mostrar solo las primeras 2 solicitudes como cards
          final displayRequests = requests.take(2).toList();

          return Column(
            children: [
              // Badge de solicitudes pendientes
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

              // Cards de solicitudes
              ...displayRequests.map((request) {
                _calculateDeviation(request);
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
                        Text(
                          '\$${trip.pricePerPassenger.toStringAsFixed(2)}',
                          style: AppTextStyles.body2.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
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

                // Botones
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

  Widget _buildActionButtons(TripModel trip) {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Row(
        children: [
          // Botón ver todas las solicitudes
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                context.push('/driver/active-requests/${widget.tripId}');
              },
              icon: Badge(
                isLabelVisible: _pendingRequests.isNotEmpty,
                label: Text('${_pendingRequests.length}'),
                child: const Icon(Icons.people),
              ),
              label: const Text('Solicitudes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Botón finalizar viaje
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _completeTrip,
              icon: const Icon(Icons.flag),
              label: const Text('Finalizar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
