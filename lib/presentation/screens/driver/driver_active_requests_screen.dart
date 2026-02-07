// lib/presentation/screens/driver/driver_active_requests_screen.dart
// Pantalla de solicitudes activas del conductor
// Muestra: solicitudes globales de pasajeros que buscan viaje

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
import '../../widgets/driver/ride_request_card.dart';

class DriverActiveRequestsScreen extends StatefulWidget {
  final String tripId;

  const DriverActiveRequestsScreen({
    super.key,
    required this.tripId,
  });

  @override
  State<DriverActiveRequestsScreen> createState() =>
      _DriverActiveRequestsScreenState();
}

class _DriverActiveRequestsScreenState
    extends State<DriverActiveRequestsScreen>
    with SingleTickerProviderStateMixin {
  final _tripsService = TripsService();
  final _requestsService = RideRequestsService();
  final _firestoreService = FirestoreService();
  final _directionsService = GoogleDirectionsService();

  // Cache de usuarios para evitar múltiples llamadas
  final Map<String, UserModel?> _usersCache = {};

  // Cache de desvíos calculados
  final Map<String, int?> _deviationsCache = {};

  // Viaje actual del conductor
  TripModel? _currentTrip;

  // Animación para el empty state
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Maneja la navegación de retroceso
  /// Siempre vuelve al home con el rol de conductor activo
  void _handleBackNavigation() {
    final authState = context.read<AuthBloc>().state;

    if (authState is Authenticated) {
      // Navegar al home con el contexto del conductor
      context.go('/home', extra: {
        'userId': authState.user.userId,
        'userRole': authState.user.role,
        'hasVehicle': authState.user.hasVehicle,
        'activeRole': 'conductor', // Forzar modo conductor
      });
    } else if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => _handleBackNavigation(),
        ),
        title: Text(
          'Pasajeros disponibles',
          style: AppTextStyles.h3,
        ),
        centerTitle: true,
        actions: [
          // Botón para ir al detalle del viaje
          IconButton(
            icon: const Icon(Icons.info_outline, color: AppColors.textSecondary),
            onPressed: () {
              context.push('/driver/trip/${widget.tripId}');
            },
          ),
        ],
      ),
      body: StreamBuilder<TripModel?>(
        stream: _tripsService.getTripStream(widget.tripId),
        builder: (context, tripSnapshot) {
          if (tripSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (tripSnapshot.hasError) {
            return _buildError(tripSnapshot.error.toString());
          }

          final trip = tripSnapshot.data;
          if (trip == null) {
            return const Center(
              child: Text('Viaje no encontrado'),
            );
          }

          // Guardar referencia del viaje
          _currentTrip = trip;

          // Stream de solicitudes globales que coinciden con la ruta
          return StreamBuilder<List<RideRequestModel>>(
            stream: _requestsService.getMatchingRequestsStream(
              driverOrigin: trip.origin,
              driverDestination: trip.destination,
              radiusKm: 5.0,
            ),
            builder: (context, requestsSnapshot) {
              if (requestsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              final requests = requestsSnapshot.data ?? [];

              if (requests.isEmpty) {
                return _buildEmptyState(trip);
              }

              return Column(
                children: [
                  // Header con info del viaje
                  _buildTripHeader(trip),

                  // Cantidad de solicitudes
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          '${requests.length} pasajero${requests.length == 1 ? '' : 's'} buscan viaje',
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Lista de solicitudes
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: () async {
                        setState(() {});
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _buildRequestCard(trip, requests[index]);
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error al cargar solicitudes',
              style: AppTextStyles.body1,
            ),
            const SizedBox(height: 8),
            Text(
              error,
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

  Widget _buildTripHeader(TripModel trip) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Icono de ruta
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.route,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),

          // Info de ruta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu ruta',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${trip.origin.name} → ${trip.destination.name}',
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.event_seat,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${trip.availableSeats} asientos disponibles',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '\$${trip.pricePerPassenger.toStringAsFixed(2)}',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(TripModel trip, RideRequestModel request) {
    return FutureBuilder<UserModel?>(
      future: _getUserInfo(request.passengerId),
      builder: (context, userSnapshot) {
        // Calcular desvío
        int? deviation = _deviationsCache[request.requestId];
        if (deviation == null && !_deviationsCache.containsKey(request.requestId)) {
          _calculateDeviation(trip, request);
        }

        return RideRequestCard(
          request: request,
          passengerUser: userSnapshot.data,
          deviationMinutes: deviation,
          onTap: () {
            context.push(
              '/driver/passenger-request/${widget.tripId}/${request.requestId}',
            );
          },
        );
      },
    );
  }

  Future<UserModel?> _getUserInfo(String userId) async {
    if (_usersCache.containsKey(userId)) {
      return _usersCache[userId];
    }

    try {
      final user = await _firestoreService.getUser(userId);
      _usersCache[userId] = user;
      return user;
    } catch (e) {
      _usersCache[userId] = null;
      return null;
    }
  }

  Future<void> _calculateDeviation(
    TripModel trip,
    RideRequestModel request,
  ) async {
    if (_currentTrip == null) return;

    try {
      // Obtener pasajeros ya aceptados del viaje
      final acceptedPickups = trip.passengers
          .where((p) => p.status == 'accepted' && p.pickupPoint != null)
          .map((p) => p.pickupPoint!)
          .toList();

      final deviation = await _directionsService.calculateTotalDeviation(
        origin: trip.origin,
        destination: trip.destination,
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

  Widget _buildEmptyState(TripModel trip) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animación de espera suave
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: child,
                );
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search,
                  size: 56,
                  color: AppColors.primary,
                ),
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'Buscando pasajeros...',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            Text(
              'Cuando alguien necesite ir hacia\ntu destino, aparecerá aquí.',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Info del viaje
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.route,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          trip.routeDescription,
                          style: AppTextStyles.body2.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.event_seat,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${trip.availableSeats} asientos disponibles',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                      Text(
                        '\$${trip.pricePerPassenger.toStringAsFixed(2)}',
                        style: AppTextStyles.body2.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Botón para ver detalles
            OutlinedButton.icon(
              onPressed: () {
                context.push('/driver/trip/${widget.tripId}');
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Ver detalles del viaje'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
