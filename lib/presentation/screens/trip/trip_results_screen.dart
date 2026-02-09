// lib/presentation/screens/trip/trip_results_screen.dart
// Pantalla de resultados de búsqueda de viajes (lado pasajero)
// Muestra viajes disponibles que coinciden con la búsqueda

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../blocs/trip/trip_event.dart';
import '../../blocs/trip/trip_state.dart';

class TripResultsScreen extends StatefulWidget {
  final List<TripModel> trips;
  final String userId;
  final TripLocation? pickupPoint;
  final String? referenceNote;
  final List<String> preferences;
  final String? objectDescription;
  final String? petDescription;

  const TripResultsScreen({
    super.key,
    required this.trips,
    required this.userId,
    this.pickupPoint,
    this.referenceNote,
    this.preferences = const ['mochila'],
    this.objectDescription,
    this.petDescription,
  });

  @override
  State<TripResultsScreen> createState() => _TripResultsScreenState();
}

class _TripResultsScreenState extends State<TripResultsScreen> {
  final _firestoreService = FirestoreService();
  final Map<String, UserModel?> _driversCache = {};
  final Map<String, VehicleModel?> _vehiclesCache = {};

  Future<UserModel?> _getDriver(String userId) async {
    if (_driversCache.containsKey(userId)) return _driversCache[userId];
    try {
      final user = await _firestoreService.getUser(userId);
      _driversCache[userId] = user;
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<VehicleModel?> _getVehicle(String vehicleId) async {
    if (_vehiclesCache.containsKey(vehicleId))
      return _vehiclesCache[vehicleId];
    try {
      final vehicle = await _firestoreService.getVehicle(vehicleId);
      _vehiclesCache[vehicleId] = vehicle;
      return vehicle;
    } catch (_) {
      return null;
    }
  }

  void _requestToJoin(TripModel trip) {
    final passenger = TripPassenger(
      userId: widget.userId,
      status: 'pending',
      pickupPoint: widget.pickupPoint,
      price: 0.0,
      preferences: widget.preferences,
      referenceNote: widget.referenceNote,
      objectDescription: widget.objectDescription,
      petDescription: widget.petDescription,
      requestedAt: DateTime.now(),
    );

    context.read<TripBloc>().add(
          RequestToJoinEvent(tripId: trip.tripId, passenger: passenger),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TripBloc, TripState>(
      listener: (context, state) {
        if (state is JoinRequestSent) {
          _showSuccessDialog();
        } else if (state is TripError) {
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
            onPressed: () => context.pop(),
          ),
          title: Text(
            'Viajes disponibles',
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
          ),
          centerTitle: true,
        ),
        body: widget.trips.isEmpty
            ? _buildEmptyState()
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: widget.trips.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  return _buildTripCard(widget.trips[index]);
                },
              ),
      ),
    );
  }

  Widget _buildTripCard(TripModel trip) {
    final timeFormat = DateFormat('HH:mm');

    return Container(
      padding: const EdgeInsets.all(AppDimensions.paddingL),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Conductor info
          FutureBuilder<UserModel?>(
            future: _getDriver(trip.driverId),
            builder: (context, driverSnap) {
              return FutureBuilder<VehicleModel?>(
                future: _getVehicle(trip.vehicleId),
                builder: (context, vehicleSnap) {
                  final driver = driverSnap.data;
                  final vehicle = vehicleSnap.data;

                  return Row(
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.tertiary,
                        backgroundImage: driver?.profilePhotoUrl != null &&
                                driver!.profilePhotoUrl!.isNotEmpty
                            ? NetworkImage(driver.profilePhotoUrl!)
                            : null,
                        child: driver?.profilePhotoUrl == null ||
                                driver!.profilePhotoUrl!.isEmpty
                            ? const Icon(Icons.person,
                                color: AppColors.textSecondary)
                            : null,
                      ),
                      const SizedBox(width: 12),

                      // Nombre y vehículo
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driver?.fullName ?? 'Conductor',
                              style: AppTextStyles.body1.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (vehicle != null)
                              Text(
                                '${vehicle.brand} ${vehicle.model} · ${vehicle.color}',
                                style: AppTextStyles.caption,
                              ),
                          ],
                        ),
                      ),

                      // Hora
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timeFormat.format(trip.departureTime),
                            style: AppTextStyles.h3.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                          Text('Salida', style: AppTextStyles.caption),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),

          const SizedBox(height: 12),

          // Ruta
          Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 18,
                    color: AppColors.divider,
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.origin.name,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      trip.destination.name,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 8),

          // Footer: asientos + precio + botón
          Row(
            children: [
              // Asientos
              Icon(Icons.event_seat, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                '${trip.availableSeats} disponibles',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(),

              // Botón solicitar
              ElevatedButton(
                onPressed: () => _requestToJoin(trip),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.buttonRadius),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  'Solicitar',
                  style: AppTextStyles.body2.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No se encontraron viajes',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'No hay viajes disponibles para tu ruta y horario. Intenta con otra fecha u hora.',
              style: AppTextStyles.body2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => context.pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.buttonRadius),
                ),
              ),
              child: const Text('Volver a buscar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '¡Solicitud enviada!',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'El conductor recibirá tu solicitud y podrá aceptarla o rechazarla.',
              style: AppTextStyles.body2,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/home');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
                ),
              ),
              child: const Text('Volver al inicio'),
            ),
          ),
        ],
      ),
    );
  }
}
