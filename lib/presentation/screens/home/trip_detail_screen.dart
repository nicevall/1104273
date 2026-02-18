// lib/presentation/screens/home/trip_detail_screen.dart
// Pantalla de detalle de un viaje completado
// Muestra ruta, fecha, pasajeros, tarifas y método de pago

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/trip_model.dart';

class TripDetailScreen extends StatefulWidget {
  final TripModel trip;
  final String viewerRole; // 'conductor' o 'pasajero'
  final String viewerId; // userId del usuario que ve el detalle

  const TripDetailScreen({
    super.key,
    required this.trip,
    required this.viewerRole,
    required this.viewerId,
  });

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  // Nombre del conductor (se carga desde Firestore)
  String? _driverName;

  // Nombres de pasajeros (se cargan desde Firestore)
  final Map<String, String> _passengerNames = {};

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  Future<void> _loadNames() async {
    final firestore = FirebaseFirestore.instance;

    // Cargar nombre del conductor
    try {
      final driverDoc = await firestore
          .collection('users')
          .doc(widget.trip.driverId)
          .get();
      if (driverDoc.exists && mounted) {
        final data = driverDoc.data()!;
        setState(() {
          _driverName = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        });
      }
    } catch (_) {}

    // Cargar nombres de pasajeros
    final activePassengers = widget.trip.passengers
        .where((p) => p.status == 'dropped_off' || p.status == 'picked_up')
        .toList();

    for (final p in activePassengers) {
      try {
        final doc = await firestore.collection('users').doc(p.userId).get();
        if (doc.exists && mounted) {
          final data = doc.data()!;
          setState(() {
            _passengerNames[p.userId] =
                '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
          });
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final dateFormat = DateFormat('EEEE d MMMM yyyy', 'es');
    final timeFormat = DateFormat('HH:mm', 'es');

    final dateStr = dateFormat.format(trip.departureTime);
    final timeStr = timeFormat.format(trip.departureTime);

    // Pasajeros activos (que completaron el viaje)
    final activePassengers = trip.passengers
        .where((p) => p.status == 'dropped_off' || p.status == 'picked_up')
        .toList();

    // Tarifa total del viaje
    double totalFare = 0;
    for (final p in activePassengers) {
      totalFare += p.price > 0 ? p.price : (p.meterFare ?? 0);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Detalle del viaje', style: AppTextStyles.h2),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge de estado + fecha
            _buildStatusHeader(dateStr, timeStr, trip.status),

            const SizedBox(height: 20),

            // Ruta: Origen → Destino
            _buildRouteCard(trip),

            const SizedBox(height: 16),

            // Info del viaje (distancia, duración, pasajeros)
            _buildTripInfoCard(trip, activePassengers),

            const SizedBox(height: 16),

            // Conductor (si el viewer es pasajero)
            if (widget.viewerRole == 'pasajero' && _driverName != null)
              ...[
                _buildDriverCard(),
                const SizedBox(height: 16),
              ],

            // Pasajeros (si el viewer es conductor)
            if (widget.viewerRole == 'conductor' && activePassengers.isNotEmpty)
              ...[
                _buildPassengersCard(activePassengers),
                const SizedBox(height: 16),
              ],

            // Resumen de tarifa
            if (activePassengers.isNotEmpty)
              _buildFareCard(activePassengers, totalFare),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(String dateStr, String timeStr, String status) {
    final statusLabel = _getStatusLabel(status);
    final statusColor = _getStatusColor(status);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fecha y hora
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateStr,
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Salida: $timeStr',
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        // Badge de estado
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            statusLabel,
            style: AppTextStyles.caption.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteCard(TripModel trip) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ruta',
            style: AppTextStyles.label.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),

          // Origen
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  Container(
                    width: 2,
                    height: 30,
                    color: AppColors.divider,
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Origen',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trip.origin.name,
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (trip.origin.address.isNotEmpty)
                      Text(
                        trip.origin.address,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),

          // Destino
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
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
                    const SizedBox(height: 2),
                    Text(
                      trip.destination.name,
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (trip.destination.address.isNotEmpty)
                      Text(
                        trip.destination.address,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTripInfoCard(TripModel trip, List<TripPassenger> activePassengers) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Información del viaje',
            style: AppTextStyles.label.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Distancia
              if (trip.distanceKm != null)
                _buildInfoItem(
                  icon: Icons.straighten,
                  label: 'Distancia',
                  value: '${trip.distanceKm!.toStringAsFixed(1)} km',
                ),
              if (trip.distanceKm != null) const SizedBox(width: 24),

              // Duración
              if (trip.durationMinutes != null)
                _buildInfoItem(
                  icon: Icons.timer_outlined,
                  label: 'Duración',
                  value: '${trip.durationMinutes} min',
                ),
              if (trip.durationMinutes != null) const SizedBox(width: 24),

              // Pasajeros
              _buildInfoItem(
                icon: Icons.people_outline,
                label: 'Pasajeros',
                value: '${activePassengers.length}',
              ),
            ],
          ),
          if (trip.isNightTariffTrip(activePassengers)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.nightlight_round, size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Text(
                  'Tarifa nocturna aplicada',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.body1.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conductor',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  _driverName ?? 'Cargando...',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengersCard(List<TripPassenger> passengers) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pasajeros',
            style: AppTextStyles.label.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...passengers.map((p) {
            final name = _passengerNames[p.userId] ?? 'Pasajero';
            final fare = p.price > 0 ? p.price : (p.meterFare ?? 0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.tertiary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_outline, size: 18, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              p.paymentMethod,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            if (p.paymentStatus == 'paid') ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle, size: 12, color: AppColors.success),
                              const SizedBox(width: 2),
                              Text(
                                'Pagado',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.success,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${fare.toStringAsFixed(2)}',
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFareCard(List<TripPassenger> passengers, double totalFare) {
    // Si es pasajero, mostrar solo su tarifa
    if (widget.viewerRole == 'pasajero') {
      final myPassenger = passengers.firstWhere(
        (p) => p.userId == widget.viewerId,
        orElse: () => passengers.first,
      );
      final myFare = myPassenger.price > 0 ? myPassenger.price : (myPassenger.meterFare ?? 0);
      final hadDiscount = (myPassenger.discountPercent ?? 0) > 0;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tarifa',
              style: AppTextStyles.label.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (hadDiscount) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tarifa base', style: AppTextStyles.body2),
                  Text(
                    '\$${(myPassenger.fareBeforeDiscount ?? myFare).toStringAsFixed(2)}',
                    style: AppTextStyles.body2,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Descuento grupal (${(myPassenger.discountPercent! * 100).toInt()}%)',
                    style: AppTextStyles.body2.copyWith(color: AppColors.success),
                  ),
                  Text(
                    '-\$${((myPassenger.fareBeforeDiscount ?? myFare) - myFare).toStringAsFixed(2)}',
                    style: AppTextStyles.body2.copyWith(color: AppColors.success),
                  ),
                ],
              ),
              const Divider(height: 20),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '\$${myFare.toStringAsFixed(2)}',
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  myPassenger.paymentMethod == 'Efectivo'
                      ? Icons.payments_outlined
                      : Icons.account_balance,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  myPassenger.paymentMethod,
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

    // Conductor: mostrar total recaudado
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recaudación',
            style: AppTextStyles.label.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...passengers.map((p) {
            final name = _passengerNames[p.userId] ?? 'Pasajero';
            final fare = p.price > 0 ? p.price : (p.meterFare ?? 0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(name, style: AppTextStyles.body2),
                  Text(
                    '\$${fare.toStringAsFixed(2)}',
                    style: AppTextStyles.body2,
                  ),
                ],
              ),
            );
          }),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total recaudado',
                style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '\$${totalFare.toStringAsFixed(2)}',
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: AppColors.shadow.withOpacity(0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completado';
      case 'cancelled':
        return 'Cancelado';
      case 'in_progress':
        return 'En progreso';
      case 'active':
        return 'Activo';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'in_progress':
        return AppColors.info;
      case 'active':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }
}

/// Extension para detectar si algún pasajero usó tarifa nocturna
extension _NightTariffCheck on TripModel {
  bool isNightTariffTrip(List<TripPassenger> activePassengers) {
    return activePassengers.any((p) => p.isNightTariff == true);
  }
}
