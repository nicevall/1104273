// lib/presentation/screens/home/activity_screen.dart
// Pantalla de Historial de viajes completados
// Filtra por rol activo: conductor ve sus viajes, pasajero ve viajes donde participó
// No muestra viajes cancelados

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/services/trips_service.dart';

class ActivityScreen extends StatefulWidget {
  final String userId;
  final String activeRole; // 'pasajero' o 'conductor'

  const ActivityScreen({
    super.key,
    required this.userId,
    required this.activeRole,
  });

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _tripsService = TripsService();
  late Future<List<TripModel>> _completedTripsFuture;

  @override
  void initState() {
    super.initState();
    _loadCompletedTrips();
  }

  void _loadCompletedTrips() {
    if (widget.activeRole == 'conductor') {
      // Conductor: viajes donde fue el driverId
      _completedTripsFuture = _tripsService.getDriverTrips(
        widget.userId,
        statusFilter: ['completed'],
      );
    } else {
      // Pasajero: viajes donde participó como pasajero
      _completedTripsFuture = _getPassengerCompletedTrips();
    }
  }

  /// Obtener viajes completados donde el usuario fue pasajero
  Future<List<TripModel>> _getPassengerCompletedTrips() async {
    try {
      // Buscar ride_requests completadas del pasajero
      final reqSnap = await FirebaseFirestore.instance
          .collection('ride_requests')
          .where('passengerId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'completed')
          .get();

      // Obtener tripIds únicos
      final tripIds = reqSnap.docs
          .map((d) => d.data()['tripId'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet();

      if (tripIds.isEmpty) return [];

      // Fetch cada trip
      final trips = <TripModel>[];
      for (final tripId in tripIds) {
        try {
          final tripDoc = await FirebaseFirestore.instance
              .collection('trips')
              .doc(tripId)
              .get();
          if (tripDoc.exists) {
            trips.add(TripModel.fromFirestore(tripDoc));
          }
        } catch (_) {
          // Skip trips que no se pueden cargar
        }
      }

      // Ordenar por fecha de salida (más recientes primero)
      trips.sort((a, b) {
        final aTime = a.departureTime ?? DateTime(2000);
        final bTime = b.departureTime ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      return trips;
    } catch (e) {
      debugPrint('Error cargando historial de pasajero: $e');
      return [];
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loadCompletedTrips();
    });
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Historial de viajes',
          style: AppTextStyles.h2,
        ),
        centerTitle: false,
      ),
      body: FutureBuilder<List<TripModel>>(
        future: _completedTripsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError) {
            // Si es error de índice, mostrar empty state
            final error = snapshot.error.toString();
            if (error.contains('index') ||
                error.contains('FAILED_PRECONDITION')) {
              return _buildEmptyState();
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No se pudo cargar el historial',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }

          final trips = snapshot.data ?? [];

          if (trips.isEmpty) {
            return _buildEmptyState();
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: trips.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final trip = trips[index];
                return _buildTripHistoryCard(trip);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildTripHistoryCard(TripModel trip) {
    final dateStr = trip.departureTime != null
        ? '${trip.departureTime!.day}/${trip.departureTime!.month}/${trip.departureTime!.year}'
        : 'Sin fecha';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fecha + Badge completado
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateStr,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Completado',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Origen
          Row(
            children: [
              const Icon(Icons.circle, size: 10, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trip.origin.name,
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          // Línea conectora
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              width: 2,
              height: 16,
              color: AppColors.divider,
            ),
          ),
          // Destino
          Row(
            children: [
              Icon(Icons.location_on, size: 10, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trip.destination.name,
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Info adicional: distancia + pasajeros
          Row(
            children: [
              if (trip.distanceKm != null) ...[
                Icon(Icons.straighten, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${trip.distanceKm!.toStringAsFixed(1)} km',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Icon(Icons.people_outline, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                '${trip.passengers.length} pasajero${trip.passengers.length != 1 ? 's' : ''}',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final roleText = widget.activeRole == 'conductor'
        ? 'como conductor'
        : 'como pasajero';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icono ilustrativo
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.tertiary.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history,
                size: 64,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Sin viajes completados',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Aún no tienes viajes completados $roleText.',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando completes tu primer viaje, aparecerá aquí.',
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
}
