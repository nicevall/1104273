// lib/presentation/widgets/home/recent_place_card.dart
// Card para mostrar lugares recientes o frecuentes
// Estilo Uber con icono de reloj y dirección

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../screens/home/home_screen.dart';

class RecentPlaceCard extends StatelessWidget {
  final RecentPlace place;
  final VoidCallback onTap;

  const RecentPlaceCard({
    super.key,
    required this.place,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.divider,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Icono circular
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.tertiary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                place.icon,
                size: 22,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(width: 14),

            // Información del lugar
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: AppTextStyles.body1.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    place.address,
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Flecha indicadora (opcional)
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 24,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
