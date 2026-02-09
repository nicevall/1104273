// lib/presentation/screens/driver/driver_active_requests_screen.dart
// Pantalla de solicitudes activas del conductor
// Muestra: solicitudes globales de pasajeros + pasajeros aceptados + botón comenzar viaje

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
import '../../../data/services/tts_service.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../blocs/trip/trip_event.dart';
import '../../blocs/trip/trip_state.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _tripsService = TripsService();
  final _requestsService = RideRequestsService();
  final _firestoreService = FirestoreService();
  final _directionsService = GoogleDirectionsService();
  final _ttsService = TtsService();

  // Cache de usuarios para evitar múltiples llamadas
  final Map<String, UserModel?> _usersCache = {};

  // Cache de desvíos calculados
  final Map<String, int?> _deviationsCache = {};

  // TTS: solicitudes ya anunciadas
  final Set<String> _announcedRequests = {};

  // Viaje actual del conductor
  TripModel? _currentTrip;

  // Stream cacheado de solicitudes (se crea una sola vez al obtener el trip)
  Stream<List<RideRequestModel>>? _requestsStream;

  // IDs de pasajeros aceptados localmente (evita race condition con Firestore)
  final Set<String> _locallyAcceptedIds = {};

  // Si se está procesando "comenzar viaje"
  bool _isStartingTrip = false;

  // Animación para el empty state
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ttsService.init();
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
    WidgetsBinding.instance.removeObserver(this);
    _ttsService.stop();
    _pulseController.dispose();
    super.dispose();
  }

  /// Interceptar el botón back nativo de Android a nivel de plataforma
  /// Esto funciona incluso cuando go_router intenta manejar el pop
  @override
  Future<bool> didPopRoute() async {
    debugPrint('🔙 didPopRoute interceptado en DriverActiveRequestsScreen');
    _showCancelTripDialog();
    return true; // true = manejado, no propagar al sistema
  }

  /// Maneja la navegación de retroceso — pide confirmación para cancelar viaje
  void _handleBackNavigation() {
    _showCancelTripDialog();
  }

  void _showCancelTripDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar viaje'),
        content: const Text(
          '¿Estás seguro que quieres cancelar este viaje?\n\n'
          'Los pasajeros aceptados serán notificados.',
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
                  child: const Text('No, continuar'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmCancelTrip();
                  },
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
  }

  Future<void> _confirmCancelTrip() async {
    try {
      await _tripsService.cancelTrip(widget.tripId);
      _ttsService.speakAnnouncement('Viaje cancelado');

      if (!mounted) return;

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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cancelar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Lee en voz alta las solicitudes nuevas
  void _announceNewRequests(List<RideRequestModel> requests) {
    for (final request in requests) {
      if (_announcedRequests.contains(request.requestId)) continue;
      _announcedRequests.add(request.requestId);

      // Construir el mensaje
      final name = _usersCache[request.passengerId]?.firstName ?? 'Un pasajero';
      final pickup = request.pickupPoint.name;
      final deviation = _deviationsCache[request.requestId];
      final deviationText = deviation != null ? ' Desvío de $deviation minutos.' : '';

      final message = 'Nueva solicitud. $name quiere que lo recojas en $pickup.$deviationText';
      _ttsService.speakRequest(message);
    }
  }

  /// Comenzar el viaje
  void _startTrip() {
    if (_currentTrip == null || _isStartingTrip) return;

    setState(() => _isStartingTrip = true);
    _ttsService.speakAnnouncement('Viaje iniciado');

    context.read<TripBloc>().add(
          StartTripEvent(tripId: widget.tripId),
        );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _showCancelTripDialog();
        }
      },
      child: BlocListener<TripBloc, TripState>(
        listener: (context, state) {
          if (state is TripStarted) {
            // Navegar a la pantalla de viaje activo con GPS
            context.go('/driver/active-trip/${widget.tripId}');
          } else if (state is TripError) {
            setState(() => _isStartingTrip = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        child: Scaffold(
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
            actions: const [],
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

            // Auto-ocultar solicitudes cuando está lleno
            final bool isFull = trip.availableSeats <= 0;

            // Cachear stream de solicitudes
            _requestsStream ??= _requestsService.getMatchingRequestsStream(
              driverOrigin: trip.origin,
              driverDestination: trip.destination,
              radiusKm: 5.0,
            );

            // Pasajeros aceptados del viaje
            final acceptedPassengers = trip.passengers
                .where((p) => p.status == 'accepted' || p.status == 'picked_up')
                .toList();

            // IDs de pasajeros ya aceptados (para filtrar solicitudes)
            final acceptedIds = acceptedPassengers
                .map((p) => p.userId)
                .toSet();

            return StreamBuilder<List<RideRequestModel>>(
              stream: _requestsStream,
              builder: (context, requestsSnapshot) {
                final allRequests = requestsSnapshot.data ?? [];

                // Filtrar solicitudes: excluir pasajeros ya aceptados (Firestore + locales)
                final availableRequests = allRequests
                    .where((r) =>
                        !acceptedIds.contains(r.passengerId) &&
                        !_locallyAcceptedIds.contains(r.passengerId))
                    .toList();

                // Anunciar nuevas solicitudes por TTS
                if (availableRequests.isNotEmpty && !isFull) {
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    _announceNewRequests(availableRequests);
                  });
                }

                // Determinar si mostrar solicitudes
                final bool showRequests =
                    !isFull &&
                    availableRequests.isNotEmpty;

                // Sincronizar IDs locales con Firestore
                // Si Firestore ya tiene al pasajero, removerlo del set local
                for (final p in acceptedPassengers) {
                  _locallyAcceptedIds.remove(p.userId);
                }

                final bool hasAccepted = acceptedPassengers.isNotEmpty ||
                    _locallyAcceptedIds.isNotEmpty;
                // Siempre mostrar la misma estructura consistente
                final totalAccepted = acceptedPassengers.length +
                    _locallyAcceptedIds
                        .where((id) => !acceptedPassengers.any((p) => p.userId == id))
                        .length;

                return Column(
                  children: [
                    // Header con info del viaje
                    _buildTripHeader(trip),

                    // Contenido scrollable
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sección de pasajeros aceptados
                            _buildAcceptedPassengersSection(
                                acceptedPassengers, trip),

                            // Banner de asientos llenos
                            if (isFull) _buildFullBanner(),

                            // Cantidad de solicitudes disponibles
                            if (showRequests) ...[
                              const SizedBox(height: 16),
                              Text(
                                '${availableRequests.length} pasajero${availableRequests.length == 1 ? '' : 's'} buscan viaje',
                                style: AppTextStyles.body2.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Lista de solicitudes disponibles
                              ...availableRequests.map(
                                (request) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildRequestCard(trip, request),
                                ),
                              ),
                            ],

                            // Mensaje cuando no hay solicitudes
                            if (!showRequests && !isFull) ...[
                              const SizedBox(height: 32),
                              Center(
                                child: Column(
                                  children: [
                                    // Radar-like scanning animation
                                    AnimatedBuilder(
                                      animation: _pulseController,
                                      builder: (context, child) {
                                        return SizedBox(
                                          width: 80,
                                          height: 80,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              // Anillo exterior pulsante
                                              Container(
                                                width: 80 * _pulseAnimation.value,
                                                height: 80 * _pulseAnimation.value,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: AppColors.primary.withOpacity(
                                                      0.3 * (1 - (_pulseAnimation.value - 0.85) / 0.15),
                                                    ),
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                              // Anillo medio
                                              Container(
                                                width: 56,
                                                height: 56,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: AppColors.primary.withOpacity(0.08),
                                                ),
                                              ),
                                              // Ícono central
                                              Transform.scale(
                                                scale: 0.9 + 0.1 * _pulseAnimation.value,
                                                child: const Icon(
                                                  Icons.person_search,
                                                  size: 32,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Buscando pasajeros',
                                          style: AppTextStyles.body2.copyWith(
                                            color: AppColors.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        // Animated dots
                                        _AnimatedDots(
                                          color: AppColors.textSecondary,
                                          controller: _pulseController,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Las solicitudes aparecerán aquí automáticamente',
                                      style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Espacio para que el bottom bar no tape contenido
                            const SizedBox(height: 160),
                          ],
                        ),
                      ),
                    ),

                    // Barra de acción inferior
                    _buildBottomActionBar(trip, totalAccepted),
                  ],
                );
              },
            );
          },
          ),
        ),
      ),
    );
  }

  // ============================================================
  // WIDGETS
  // ============================================================

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
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sección de pasajeros aceptados (agregados a la ruta)
  Widget _buildAcceptedPassengersSection(
    List<TripPassenger> acceptedPassengers,
    TripModel trip,
  ) {
    // IDs locales que aún no aparecen en Firestore
    final firestoreIds = acceptedPassengers.map((p) => p.userId).toSet();
    final pendingLocalIds = _locallyAcceptedIds
        .where((id) => !firestoreIds.contains(id))
        .toList();

    final totalCount = acceptedPassengers.length + pendingLocalIds.length;
    if (totalCount == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.people, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Text(
              'Pasajeros en tu ruta ($totalCount)',
              style: AppTextStyles.body2.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Pasajeros confirmados en Firestore
        ...acceptedPassengers.map((passenger) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildAcceptedPassengerCard(passenger),
          );
        }),
        // Pasajeros aceptados localmente (aún sincronizando)
        ...pendingLocalIds.map((passengerId) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildPendingAcceptedCard(passengerId),
          );
        }),
      ],
    );
  }

  /// Card para pasajero aceptado localmente (aún sincronizando con Firestore)
  /// Se muestra con el mismo estilo verde que los confirmados para evitar confusión
  Widget _buildPendingAcceptedCard(String passengerId) {
    return FutureBuilder<UserModel?>(
      future: _getUserInfo(passengerId),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data;
        final name = user != null
            ? '${user.firstName} ${user.lastName.isNotEmpty ? '${user.lastName[0]}.' : ''}'
            : 'Pasajero';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              // Checkmark verde (igual que los confirmados)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Agregado a tu ruta',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAcceptedPassengerCard(TripPassenger passenger) {
    return FutureBuilder<UserModel?>(
      future: _getUserInfo(passenger.userId),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data;
        final name = user != null
            ? '${user.firstName} ${user.lastName.isNotEmpty ? '${user.lastName[0]}.' : ''}'
            : 'Pasajero';
        final pickup = passenger.pickupPoint?.name ?? 'Sin punto de recogida';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              // Checkmark verde
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.place,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            pickup,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Botón cancelar
              IconButton(
                onPressed: () => _cancelAcceptedPassenger(passenger, name),
                icon: const Icon(Icons.close, size: 18),
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.error,
                  backgroundColor: AppColors.error.withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(6),
                  minimumSize: const Size(32, 32),
                ),
                tooltip: 'Quitar pasajero',
              ),
            ],
          ),
        );
      },
    );
  }

  void _cancelAcceptedPassenger(TripPassenger passenger, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar pasajero'),
        content: Text(
          '¿Quitar a $name del viaje?\n\n'
          'Se liberará el asiento y el pasajero será notificado.',
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
                  child: const Text('No'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmCancelPassenger(passenger);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Sí, quitar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancelPassenger(TripPassenger passenger) async {
    try {
      // 1. Remover pasajero del viaje
      if (_currentTrip != null) {
        final updatedPassengers = _currentTrip!.passengers
            .where((p) => p.userId != passenger.userId)
            .toList();

        final updatedTrip = _currentTrip!.copyWith(
          passengers: updatedPassengers,
          availableSeats: _currentTrip!.availableSeats + 1,
        );

        await _tripsService.updateTrip(updatedTrip);
      }

      // 2. Remover del set local
      _locallyAcceptedIds.remove(passenger.userId);

      if (mounted) {
        _ttsService.speakAnnouncement('Pasajero removido del viaje');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pasajero removido del viaje'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error cancelando pasajero: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Banner cuando todos los asientos están ocupados
  Widget _buildFullBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_seat, color: AppColors.info, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Todos los asientos ocupados. Puedes comenzar el viaje.',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.info,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Banner cuando el conductor decidió no recibir más pasajeros
  Widget _buildRequestCard(TripModel trip, RideRequestModel request) {
    return FutureBuilder<UserModel?>(
      future: _getUserInfo(request.passengerId),
      builder: (context, userSnapshot) {
        // Calcular desvío
        int? deviation = _deviationsCache[request.requestId];
        if (deviation == null &&
            !_deviationsCache.containsKey(request.requestId)) {
          _calculateDeviation(trip, request);
        }

        return RideRequestCard(
          request: request,
          passengerUser: userSnapshot.data,
          deviationMinutes: deviation,
          onTap: () async {
            final result = await context.push<String>(
              '/driver/passenger-request/${widget.tripId}/${request.requestId}',
            );
            // Si devolvió un passengerId, lo aceptamos localmente
            if (result != null && result.isNotEmpty && mounted) {
              setState(() {
                _locallyAcceptedIds.add(result);
              });
            }
          },
        );
      },
    );
  }

  /// Barra de acción inferior con botones
  Widget _buildBottomActionBar(TripModel trip, int acceptedCount) {
    final bool canStartTrip = acceptedCount > 0;
    final bool isFull = trip.availableSeats <= 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Botón "Comenzar viaje"
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canStartTrip && !_isStartingTrip ? _startTrip : null,
                icon: _isStartingTrip
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.play_arrow, color: Colors.white),
                label: Text(
                  _isStartingTrip ? 'Iniciando...' : 'Comenzar viaje',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canStartTrip
                      ? AppColors.primary
                      : AppColors.primary.withOpacity(0.4),
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: canStartTrip ? 2 : 0,
                ),
              ),
            ),

            if (!canStartTrip) ...[
              const SizedBox(height: 8),
              Text(
                'Acepta al menos un pasajero para comenzar',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],

            if (canStartTrip) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Puedes comenzar el viaje y seguir recibiendo solicitudes en camino',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // "No recibir más" moved to driver_active_trip_screen (GPS)
          ],
        ),
      ),
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

  // ============================================================
  // DEAD CODE — _buildEmptyState ya no se llama (se dejó por referencia)
  // ============================================================
  Widget _buildEmptyState(TripModel trip) {
    // Pasajeros aceptados incluso en empty state
    final acceptedPassengers = trip.passengers
        .where((p) => p.status == 'accepted' || p.status == 'picked_up')
        .toList();

    if (acceptedPassengers.isNotEmpty) {
      // Hay pasajeros aceptados pero no hay más solicitudes
      return Column(
        children: [
          _buildTripHeader(trip),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _buildAcceptedPassengersSection(acceptedPassengers, trip),
                  const SizedBox(height: 32),
                  const Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sin más solicitudes por ahora',
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 160),
                ],
              ),
            ),
          ),
          _buildBottomActionBar(trip, acceptedPassengers.length + _locallyAcceptedIds.where((id) => !acceptedPassengers.any((p) => p.userId == id)).length),
        ],
      );
    }

    // Sin pasajeros ni solicitudes
    return Column(
      children: [
        Expanded(
          child: Center(
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
                      ],
                    ),
                  ),

                  // "Ver detalles" removed — redundant in current flow
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Widget de puntos animados (...) para "Buscando pasajeros..."
class _AnimatedDots extends StatelessWidget {
  final Color color;
  final AnimationController controller;

  const _AnimatedDots({
    required this.color,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Cycle through 0, 1, 2, 3 dots based on animation progress
        final progress = controller.value;
        final dotCount = (progress * 4).floor() % 4;
        final dots = '.' * (dotCount == 0 ? 3 : dotCount);
        return SizedBox(
          width: 20,
          child: Text(
            dots,
            style: AppTextStyles.body2.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      },
    );
  }
}
