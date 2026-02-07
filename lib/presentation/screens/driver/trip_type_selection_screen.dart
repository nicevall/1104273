// lib/presentation/screens/driver/trip_type_selection_screen.dart
// Pantalla de selección del tipo de viaje: Programado o Inmediato

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_dimensions.dart';

class TripTypeSelectionScreen extends StatelessWidget {
  final String userId;

  const TripTypeSelectionScreen({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Ofrecer viaje',
          style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingXXL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppDimensions.spacingL),

            Text(
              '¿Qué tipo de viaje deseas ofrecer?',
              style: AppTextStyles.h2,
            ),
            const SizedBox(height: 8),
            Text(
              'Elige cómo quieres compartir tu viaje',
              style: AppTextStyles.body2,
            ),

            const SizedBox(height: AppDimensions.spacing3XL),

            // Opción 1: Disponibilidad Inmediata (habilitado)
            _buildOptionCard(
              context: context,
              icon: Icons.flash_on,
              title: 'Disponibilidad Inmediata',
              description:
                  'Indica que estás disponible ahora y recibe solicitudes en tiempo real.',
              isEnabled: true,
              onTap: () {
                context.push('/driver/instant-trip', extra: {
                  'userId': userId,
                });
              },
            ),

            const SizedBox(height: AppDimensions.spacingL),

            // Opción 2: Viaje Programado (habilitado)
            _buildOptionCard(
              context: context,
              icon: Icons.calendar_today,
              title: 'Viaje Programado',
              description:
                  'Publica un viaje con fecha y hora específica. Los pasajeros pueden solicitar unirse.',
              isEnabled: true,
              onTap: () {
                context.push('/driver/create-trip/form', extra: {
                  'userId': userId,
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required bool isEnabled,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppDimensions.paddingXXL),
        decoration: BoxDecoration(
          color: isEnabled ? AppColors.background : AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          border: Border.all(
            color: isEnabled ? AppColors.primary : AppColors.border,
            width: isEnabled ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Ícono
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isEnabled
                    ? AppColors.primary.withOpacity(0.1)
                    : AppColors.tertiary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isEnabled ? AppColors.primary : AppColors.disabled,
                size: 24,
              ),
            ),
            const SizedBox(width: AppDimensions.spacingL),

            // Texto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppTextStyles.body1.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isEnabled
                                ? AppColors.textPrimary
                                : AppColors.disabled,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badge,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTextStyles.caption.copyWith(
                      color: isEnabled
                          ? AppColors.textSecondary
                          : AppColors.disabled,
                    ),
                  ),
                ],
              ),
            ),

            if (isEnabled)
              Icon(
                Icons.arrow_forward_ios,
                color: AppColors.primary,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}
