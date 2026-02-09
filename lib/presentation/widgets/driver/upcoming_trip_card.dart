// lib/presentation/widgets/driver/upcoming_trip_card.dart
// Card de un viaje programado del conductor

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/models/trip_model.dart';

class UpcomingTripCard extends StatelessWidget {
  final TripModel trip;
  final VoidCallback onTap;

  const UpcomingTripCard({
    super.key,
    required this.trip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE d MMM', 'es');
    final timeFormat = DateFormat('HH:mm');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppDimensions.paddingL),
        decoration: BoxDecoration(
          color: (trip.isActive || trip.isInProgress)
              ? AppColors.success.withOpacity(0.03)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          border: Border.all(
            color: (trip.isActive || trip.isInProgress) ? AppColors.success : AppColors.border,
            width: (trip.isActive || trip.isInProgress) ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: fecha + status badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateFormat.format(trip.departureTime),
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                _buildStatusBadge(),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingS),

            // Ruta
            Row(
              children: [
                // Indicador visual de ruta
                Column(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 2),
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 24,
                      color: AppColors.divider,
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.success, width: 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppDimensions.spacingM),

                // Nombres de origen y destino
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.origin.name,
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        trip.destination.name,
                        style: AppTextStyles.body2.copyWith(
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
            const SizedBox(height: AppDimensions.spacingM),

            // Footer: hora + pasajeros + precio
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: AppDimensions.spacingS),
            Row(
              children: [
                // Hora
                Icon(Icons.access_time, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  timeFormat.format(trip.departureTime),
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingL),

                // Pasajeros
                Icon(Icons.people_outline, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${trip.acceptedPassengersCount}/${trip.totalCapacity}',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),

                // Solicitudes pendientes
                if (trip.pendingRequestsCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${trip.pendingRequestsCount} pendientes',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 10,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const Spacer(),

                // Precio
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
    );
  }

  Widget _buildStatusBadge() {
    Color bgColor;
    Color textColor;
    String label;

    switch (trip.status) {
      case 'scheduled':
        bgColor = AppColors.info.withOpacity(0.1);
        textColor = AppColors.info;
        label = 'Pendiente';
        break;
      case 'active':
        bgColor = AppColors.success.withOpacity(0.1);
        textColor = AppColors.success;
        label = 'En curso';
        break;
      case 'completed':
        bgColor = AppColors.textSecondary.withOpacity(0.1);
        textColor = AppColors.textSecondary;
        label = 'Completado';
        break;
      case 'cancelled':
        bgColor = AppColors.error.withOpacity(0.1);
        textColor = AppColors.error;
        label = 'Cancelado';
        break;
      default:
        bgColor = AppColors.tertiary;
        textColor = AppColors.textSecondary;
        label = trip.status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
