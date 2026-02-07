// lib/presentation/widgets/driver/passenger_request_card.dart
// Card de solicitud de pasajero con botones Accept/Reject

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/user_model.dart';

class PassengerRequestCard extends StatelessWidget {
  final TripPassenger passenger;
  final UserModel? passengerUser; // Datos del usuario (nombre, foto)
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const PassengerRequestCard({
    super.key,
    required this.passenger,
    this.passengerUser,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.paddingL),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(
          color: passenger.status == 'pending'
              ? AppColors.warning.withOpacity(0.5)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: foto + nombre + hora
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.tertiary,
                backgroundImage: passengerUser?.profilePhotoUrl != null &&
                        passengerUser!.profilePhotoUrl!.isNotEmpty
                    ? NetworkImage(passengerUser!.profilePhotoUrl!)
                    : null,
                child: passengerUser?.profilePhotoUrl == null ||
                        passengerUser!.profilePhotoUrl!.isEmpty
                    ? const Icon(Icons.person, color: AppColors.textSecondary)
                    : null,
              ),
              const SizedBox(width: AppDimensions.spacingM),

              // Nombre y hora
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      passengerUser?.fullName ?? 'Pasajero',
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Solicitó a las ${timeFormat.format(passenger.requestedAt)}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),

              // Status badge
              _buildStatusBadge(),
            ],
          ),

          // Punto de recogida
          if (passenger.pickupPoint != null) ...[
            const SizedBox(height: AppDimensions.spacingS),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    passenger.pickupPoint!.name,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // Referencia
          if (passenger.referenceNote != null &&
              passenger.referenceNote!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    passenger.referenceNote!,
                    style: AppTextStyles.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // Preferencias
          if (passenger.preferences.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spacingS),
            Wrap(
              spacing: 6,
              children: passenger.preferences.map((pref) {
                return _buildPreferenceChip(pref);
              }).toList(),
            ),
          ],

          // Botones Accept/Reject solo si status es pending
          if (passenger.status == 'pending') ...[
            const SizedBox(height: AppDimensions.spacingM),
            Row(
              children: [
                // Rechazar
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.buttonRadius),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      'Rechazar',
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingM),

                // Aceptar
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.buttonRadius),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      'Aceptar',
                      style: AppTextStyles.body2.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (passenger.status == 'pending') return const SizedBox.shrink();

    Color bgColor;
    Color textColor;
    String label;

    switch (passenger.status) {
      case 'accepted':
        bgColor = AppColors.success.withOpacity(0.1);
        textColor = AppColors.success;
        label = 'Aceptado';
        break;
      case 'rejected':
        bgColor = AppColors.error.withOpacity(0.1);
        textColor = AppColors.error;
        label = 'Rechazado';
        break;
      case 'picked_up':
        bgColor = AppColors.info.withOpacity(0.1);
        textColor = AppColors.info;
        label = 'Recogido';
        break;
      default:
        bgColor = AppColors.tertiary;
        textColor = AppColors.textSecondary;
        label = passenger.status;
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

  Widget _buildPreferenceChip(String pref) {
    IconData icon;
    String label;

    switch (pref) {
      case 'mochila':
        icon = Icons.backpack_outlined;
        label = 'Mochila';
        break;
      case 'objeto_grande':
        icon = Icons.luggage_outlined;
        label = 'Objeto grande';
        break;
      case 'mascota':
        icon = Icons.pets_outlined;
        label = 'Mascota';
        break;
      default:
        icon = Icons.inventory_2_outlined;
        label = pref;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}
