// lib/presentation/screens/driver/driver_trip_detail_screen.dart
// Pantalla de detalle de un viaje del conductor
// Muestra info del viaje, pasajeros y solicitudes pendientes

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../blocs/trip/trip_event.dart';
import '../../blocs/trip/trip_state.dart';
import '../../widgets/driver/passenger_request_card.dart';

class DriverTripDetailScreen extends StatefulWidget {
  final String tripId;

  const DriverTripDetailScreen({
    super.key,
    required this.tripId,
  });

  @override
  State<DriverTripDetailScreen> createState() => _DriverTripDetailScreenState();
}

class _DriverTripDetailScreenState extends State<DriverTripDetailScreen> {
  final _firestoreService = FirestoreService();

  // Cache de datos de usuarios (pasajeros)
  final Map<String, UserModel?> _usersCache = {};

  @override
  void initState() {
    super.initState();
    context.read<TripBloc>().add(LoadTripDetailEvent(tripId: widget.tripId));
  }

  Future<UserModel?> _getUser(String userId) async {
    if (_usersCache.containsKey(userId)) {
      return _usersCache[userId];
    }
    try {
      final user = await _firestoreService.getUser(userId);
      _usersCache[userId] = user;
      return user;
    } catch (_) {
      return null;
    }
  }

  /// Navega al home manteniendo el contexto del conductor
  void _goToDriverHome() {
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

  void _startTrip() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Iniciar viaje'),
        content: const Text(
          '¿Estás seguro de que deseas iniciar este viaje? '
          'El estado cambiará a "En curso".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context
                  .read<TripBloc>()
                  .add(StartTripEvent(tripId: widget.tripId));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, iniciar'),
          ),
        ],
      ),
    );
  }

  void _completeTrip() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar viaje'),
        content: const Text(
          '¿Estás seguro de que deseas finalizar este viaje? '
          'Aparecerá en tu historial de actividad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context
                  .read<TripBloc>()
                  .add(CompleteTripEvent(tripId: widget.tripId));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, finalizar'),
          ),
        ],
      ),
    );
  }

  void _cancelTrip() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar viaje'),
        content: const Text(
          '¿Estás seguro de que deseas cancelar este viaje? '
          'Los pasajeros serán notificados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context
                  .read<TripBloc>()
                  .add(CancelTripEvent(tripId: widget.tripId));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
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
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              _goToDriverHome();
            }
          },
        ),
        title: Text(
          'Detalle del viaje',
          style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
        ),
        centerTitle: true,
      ),
      body: BlocConsumer<TripBloc, TripState>(
        listener: (context, state) {
          if (state is TripCancelled) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Viaje cancelado'),
                backgroundColor: AppColors.success,
              ),
            );
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              _goToDriverHome();
            }
          } else if (state is TripStarted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('¡Viaje iniciado!'),
                backgroundColor: AppColors.success,
              ),
            );
            // Recargar detalle para reflejar nuevo status
            context
                .read<TripBloc>()
                .add(LoadTripDetailEvent(tripId: widget.tripId));
          } else if (state is TripCompleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Viaje finalizado'),
                backgroundColor: AppColors.success,
              ),
            );
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              _goToDriverHome();
            }
          } else if (state is PassengerAccepted || state is PassengerRejected) {
            // Recargar detalle
            context
                .read<TripBloc>()
                .add(LoadTripDetailEvent(tripId: widget.tripId));
          }
        },
        builder: (context, state) {
          if (state is TripLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (state is TripDetailLoaded) {
            return _buildContent(state.trip);
          }

          if (state is TripError) {
            return Center(
              child: Text(
                state.error,
                style: AppTextStyles.body2.copyWith(color: AppColors.error),
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildContent(TripModel trip) {
    final dateFormat = DateFormat('EEEE d MMMM, yyyy', 'es');
    final timeFormat = DateFormat('HH:mm');

    final pendingPassengers =
        trip.passengers.where((p) => p.status == 'pending').toList();
    final acceptedPassengers = trip.passengers
        .where((p) => p.status == 'accepted' || p.status == 'picked_up')
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          _buildStatusBadge(trip),

          const SizedBox(height: 20),

          // Ruta
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppDimensions.paddingL),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            ),
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(width: 2, height: 30, color: AppColors.divider),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trip.origin.name,
                          style: AppTextStyles.body1
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text(trip.origin.address,
                          style: AppTextStyles.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 20),
                      Text(trip.destination.name,
                          style: AppTextStyles.body1
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text(trip.destination.address,
                          style: AppTextStyles.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Fecha, hora, precio
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppDimensions.paddingL),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            ),
            child: Column(
              children: [
                _buildInfoRow(Icons.calendar_today,
                    dateFormat.format(trip.departureTime)),
                const SizedBox(height: 12),
                _buildInfoRow(Icons.access_time,
                    'Sale a las ${timeFormat.format(trip.departureTime)}'),
                const SizedBox(height: 12),
                _buildInfoRow(Icons.people_outline,
                    '${trip.acceptedPassengersCount}/${trip.totalCapacity} pasajeros (${trip.availableSeats} disponibles)'),
                const SizedBox(height: 12),
                _buildInfoRow(Icons.attach_money,
                    '\$${trip.pricePerPassenger.toStringAsFixed(2)} por pasajero'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Solicitudes pendientes
          if (pendingPassengers.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'Solicitudes pendientes',
                  style: AppTextStyles.body1
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${pendingPassengers.length}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...pendingPassengers.map((passenger) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FutureBuilder<UserModel?>(
                  future: _getUser(passenger.userId),
                  builder: (context, snapshot) {
                    return PassengerRequestCard(
                      passenger: passenger,
                      passengerUser: snapshot.data,
                      onAccept: () {
                        context.read<TripBloc>().add(AcceptPassengerEvent(
                              tripId: trip.tripId,
                              passengerId: passenger.userId,
                            ));
                      },
                      onReject: () {
                        context.read<TripBloc>().add(RejectPassengerEvent(
                              tripId: trip.tripId,
                              passengerId: passenger.userId,
                            ));
                      },
                    );
                  },
                ),
              );
            }),
            const SizedBox(height: 12),
          ],

          // Pasajeros aceptados
          if (acceptedPassengers.isNotEmpty) ...[
            Text(
              'Pasajeros confirmados',
              style:
                  AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...acceptedPassengers.map((passenger) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FutureBuilder<UserModel?>(
                  future: _getUser(passenger.userId),
                  builder: (context, snapshot) {
                    return PassengerRequestCard(
                      passenger: passenger,
                      passengerUser: snapshot.data,
                      onAccept: () {}, // No-op for accepted
                      onReject: () {}, // No-op for accepted
                    );
                  },
                ),
              );
            }),
          ],

          // Sin pasajeros
          if (trip.passengers.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.tertiary.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.people_outline,
                      size: 40, color: AppColors.textSecondary),
                  const SizedBox(height: 8),
                  Text(
                    'Aún no hay solicitudes',
                    style: AppTextStyles.body2
                        .copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Los pasajeros podrán solicitarte cuando busquen viajes',
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Botones de acción según estado
          if (trip.isScheduled) ...[
            // Botón "Iniciar viaje" para viajes pendientes
            SizedBox(
              width: double.infinity,
              height: AppDimensions.buttonHeight,
              child: ElevatedButton.icon(
                onPressed: () => _startTrip(),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text(
                  'Iniciar viaje',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.buttonRadius),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Botón "Cancelar viaje"
            SizedBox(
              width: double.infinity,
              height: AppDimensions.buttonHeight,
              child: OutlinedButton(
                onPressed: _cancelTrip,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.buttonRadius),
                  ),
                ),
                child: Text(
                  'Cancelar viaje',
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],

          // Botón "Finalizar viaje" para viajes en curso
          if (trip.isActive) ...[
            SizedBox(
              width: double.infinity,
              height: AppDimensions.buttonHeight,
              child: ElevatedButton.icon(
                onPressed: () => _completeTrip(),
                icon: const Icon(Icons.check_circle_outline, size: 22),
                label: const Text(
                  'Finalizar viaje',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.buttonRadius),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(TripModel trip) {
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;

    switch (trip.status) {
      case 'scheduled':
        bgColor = AppColors.info.withOpacity(0.1);
        textColor = AppColors.info;
        label = 'Pendiente';
        icon = Icons.schedule;
        break;
      case 'active':
        bgColor = AppColors.success.withOpacity(0.1);
        textColor = AppColors.success;
        label = 'En curso';
        icon = Icons.directions_car;
        break;
      case 'completed':
        bgColor = AppColors.textSecondary.withOpacity(0.1);
        textColor = AppColors.textSecondary;
        label = 'Completado';
        icon = Icons.check_circle;
        break;
      case 'cancelled':
        bgColor = AppColors.error.withOpacity(0.1);
        textColor = AppColors.error;
        label = 'Cancelado';
        icon = Icons.cancel;
        break;
      default:
        bgColor = AppColors.tertiary;
        textColor = AppColors.textSecondary;
        label = trip.status;
        icon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.body2.copyWith(
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
