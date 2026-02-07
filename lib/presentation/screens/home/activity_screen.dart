// lib/presentation/screens/home/activity_screen.dart
// Pantalla de Actividad - Historial de viajes completados
// Usa TripsService directo (no TripBloc) para evitar conflicto de estado global

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/services/trips_service.dart';
import '../../widgets/driver/upcoming_trip_card.dart';

class ActivityScreen extends StatefulWidget {
  final String userId;

  const ActivityScreen({
    super.key,
    required this.userId,
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
    _completedTripsFuture = _tripsService.getDriverTrips(
      widget.userId,
      statusFilter: ['completed'],
    );
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
        title: Text(
          'Actividad',
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

          // Ordenar: más recientes primero
          final sortedTrips = trips.reversed.toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: sortedTrips.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return UpcomingTripCard(
                  trip: sortedTrips[index],
                  onTap: () {
                    context.push('/driver/trip/${sortedTrips[index].tripId}');
                  },
                );
              },
            ),
          );
        },
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
              'Sin actividad reciente',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Aquí aparecerán tus viajes realizados.',
              style: AppTextStyles.body2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando completes tu primer viaje, podrás ver el historial aquí.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
