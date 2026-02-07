// lib/presentation/widgets/home/role_switcher.dart
// Widget Toggle para cambiar entre rol Pasajero y Conductor
// Solo visible para usuarios con rol "ambos"

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class RoleSwitcher extends StatelessWidget {
  final String activeRole; // 'pasajero' o 'conductor'
  final Function(String) onRoleChanged;

  const RoleSwitcher({
    super.key,
    required this.activeRole,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          // Botón Pasajero
          Expanded(
            child: _buildRoleButton(
              role: 'pasajero',
              icon: Icons.directions_walk,
              label: 'Pasajero',
              isActive: activeRole == 'pasajero',
              isEnabled: true,
              onTap: () => onRoleChanged('pasajero'),
            ),
          ),

          // Botón Conductor
          Expanded(
            child: _buildRoleButton(
              role: 'conductor',
              icon: Icons.directions_car,
              label: 'Conductor',
              isActive: activeRole == 'conductor',
              isEnabled: true,
              onTap: () => onRoleChanged('conductor'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleButton({
    required String role,
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : () => _showComingSoonTooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.background : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive
                  ? AppColors.primary
                  : isEnabled
                      ? AppColors.textSecondary
                      : AppColors.disabled,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.body2.copyWith(
                  color: isActive
                      ? AppColors.textPrimary
                      : isEnabled
                          ? AppColors.textSecondary
                          : AppColors.disabled,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Badge de "Próximamente" para conductor
            if (!isEnabled) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Pronto',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 8,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showComingSoonTooltip(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'El modo conductor estará disponible próximamente',
                style: AppTextStyles.body2.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
