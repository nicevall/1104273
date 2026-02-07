// lib/presentation/widgets/driver/passenger_request_list_card.dart
// Card para mostrar una solicitud de pasajero en la lista del conductor
// Muestra: pickup, avatar, desvío, iconos de preferencias

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/user_model.dart';

class PassengerRequestListCard extends StatelessWidget {
  final TripPassenger passenger;
  final UserModel? passengerUser;
  final int? deviationMinutes;
  final VoidCallback onTap;

  const PassengerRequestListCard({
    super.key,
    required this.passenger,
    this.passengerUser,
    this.deviationMinutes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.paddingL),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sección superior: Punto de recogida
            _buildPickupSection(),

            const SizedBox(height: AppDimensions.spacingM),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: AppDimensions.spacingM),

            // Sección media: Avatar + Info + Badge de desvío
            _buildPassengerInfoSection(),

            const SizedBox(height: AppDimensions.spacingM),

            // Sección inferior: Iconos de preferencias
            _buildPreferencesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPickupSection() {
    final pickupName = passenger.pickupPoint?.name ?? 'Punto de recogida';
    final reference = passenger.referenceNote;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icono de ubicación
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.place,
            color: AppColors.warning,
            size: 20,
          ),
        ),
        const SizedBox(width: AppDimensions.spacingM),

        // Nombre y referencia
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pickupName,
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (reference != null && reference.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '"$reference"',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPassengerInfoSection() {
    return Row(
      children: [
        // Avatar del pasajero
        _buildAvatar(),
        const SizedBox(width: AppDimensions.spacingM),

        // Nombre y rating
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getPassengerDisplayName(),
                style: AppTextStyles.body2.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (passengerUser?.rating != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.star,
                      size: 14,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      passengerUser!.rating!.toStringAsFixed(1),
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Badge de desvío
        if (deviationMinutes != null) _buildDeviationBadge(),
      ],
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.tertiary,
        border: Border.all(
          color: AppColors.divider,
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: passengerUser?.profilePhotoUrl != null
            ? Image.network(
                passengerUser!.profilePhotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildAvatarPlaceholder(),
              )
            : _buildAvatarPlaceholder(),
      ),
    );
  }

  Widget _buildAvatarPlaceholder() {
    final initials = _getInitials();
    return Container(
      color: AppColors.primary.withOpacity(0.1),
      child: Center(
        child: Text(
          initials,
          style: AppTextStyles.body2.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _getInitials() {
    if (passengerUser == null) return '?';
    final first = passengerUser!.firstName.isNotEmpty
        ? passengerUser!.firstName[0].toUpperCase()
        : '';
    final last = passengerUser!.lastName.isNotEmpty
        ? passengerUser!.lastName[0].toUpperCase()
        : '';
    return '$first$last';
  }

  String _getPassengerDisplayName() {
    if (passengerUser == null) return 'Pasajero';
    final firstName = passengerUser!.firstName;
    final lastInitial = passengerUser!.lastName.isNotEmpty
        ? '${passengerUser!.lastName[0]}.'
        : '';
    return '$firstName $lastInitial';
  }

  Widget _buildDeviationBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.add,
            size: 14,
            color: AppColors.warning,
          ),
          const SizedBox(width: 2),
          Text(
            '$deviationMinutes min',
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesSection() {
    return Row(
      children: [
        // Método de pago
        _buildPreferenceChip(
          icon: passenger.paymentMethod == 'Efectivo'
              ? Icons.payments_outlined
              : Icons.phone_android,
          label: passenger.paymentMethod,
          color: AppColors.success,
        ),

        const SizedBox(width: 8),

        // Equipaje
        if (passenger.preferences.contains('objeto_grande')) ...[
          _buildPreferenceChip(
            icon: Icons.inventory_2_outlined,
            label: 'Grande',
            color: AppColors.info,
          ),
          const SizedBox(width: 8),
        ] else if (passenger.preferences.contains('mochila')) ...[
          _buildPreferenceChip(
            icon: Icons.backpack_outlined,
            label: 'Mochila',
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
        ],

        // Mascota
        if (passenger.preferences.contains('mascota') && passenger.petType != null)
          _buildPetChip(),
      ],
    );
  }

  Widget _buildPreferenceChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPetChip() {
    String emoji;
    String label;

    switch (passenger.petType) {
      case 'perro':
        emoji = '🐕';
        label = passenger.petSize != null
            ? 'Perro (${passenger.petSize})'
            : 'Perro';
        break;
      case 'gato':
        emoji = '🐱';
        label = 'Gato';
        break;
      case 'otro':
        emoji = '🐾';
        label = passenger.petDescription ?? 'Otro';
        break;
      default:
        emoji = '🐾';
        label = 'Mascota';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.amber.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
