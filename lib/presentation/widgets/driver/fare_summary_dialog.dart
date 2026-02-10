// lib/presentation/widgets/driver/fare_summary_dialog.dart
// Diálogo de resumen de tarifa al bajar un pasajero
// Sigue los estándares de UI de diálogos de UniRide

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/services/pricing_service.dart';
import '../../../data/services/taximeter_service.dart';

/// Muestra un resumen detallado de la tarifa cuando un pasajero se baja
class FareSummaryDialog extends StatelessWidget {
  final String passengerName;
  final TaximeterSession session;
  final String paymentMethod;

  const FareSummaryDialog({
    super.key,
    required this.passengerName,
    required this.session,
    this.paymentMethod = 'Efectivo',
  });

  /// Mostrar el diálogo. Retorna true si el conductor confirmó el pago.
  static Future<bool?> show(
    BuildContext context, {
    required String passengerName,
    required TaximeterSession session,
    String paymentMethod = 'Efectivo',
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FareSummaryDialog(
        passengerName: passengerName,
        session: session,
        paymentMethod: paymentMethod,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNight = session.isNightTariff;
    final startFare = isNight
        ? PricingService.nightStartFare
        : PricingService.dayStartFare;
    final perKm = isNight ? PricingService.nightPerKm : PricingService.dayPerKm;
    final perWaitMin = isNight
        ? PricingService.nightPerWaitMinute
        : PricingService.dayPerWaitMinute;
    final minimumFare = isNight
        ? PricingService.nightMinimumFare
        : PricingService.dayMinimumFare;

    final distanceCost = session.totalDistanceKm * perKm;
    final waitCost = session.totalWaitMinutes * perWaitMin;
    final rawTotal = startFare + distanceCost + waitCost;
    final appliedMinimum = rawTotal < minimumFare;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      actionsAlignment: MainAxisAlignment.center,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icono check
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.success,
              size: 32,
            ),
          ),
          const SizedBox(height: 12),

          // Título
          Text(
            'Pasajero entregado',
            style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            passengerName,
            style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // Tarifa badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isNight
                  ? Colors.indigo.withValues(alpha: 0.1)
                  : Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                  size: 14,
                  color: isNight ? Colors.indigo : Colors.amber.shade700,
                ),
                const SizedBox(width: 4),
                Text(
                  'Tarifa ${isNight ? 'Nocturna' : 'Diurna'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isNight ? Colors.indigo : Colors.amber.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Desglose
          _buildRow('Arranque', '\$${startFare.toStringAsFixed(2)}'),
          _buildRow(
            '${session.totalDistanceKm.toStringAsFixed(1)} km',
            '\$${distanceCost.toStringAsFixed(2)}',
          ),
          if (session.totalWaitMinutes >= 0.5)
            _buildRow(
              '${session.totalWaitMinutes.round()} min espera',
              '\$${waitCost.toStringAsFixed(2)}',
            ),
          // Descuento grupal
          if (session.discountPercent > 0)
            _buildRow(
              'Desc. grupo (${(session.discountPercent * 100).round()}%)',
              '-\$${(session.fareBeforeDiscount - session.currentFare).toStringAsFixed(2)}',
              color: AppColors.success,
            ),
          const Divider(height: 20),

          // Total (con redondeo si es efectivo)
          Builder(builder: (context) {
            final isCash = paymentMethod == 'Efectivo';
            final displayFare = isCash
                ? PricingService.roundUpToNickel(session.currentFare)
                : session.currentFare;
            final wasRounded = isCash && displayFare != session.currentFare;

            return Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL',
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '\$${displayFare.toStringAsFixed(2)}',
                      style: AppTextStyles.h2.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                if (appliedMinimum)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '(Tarifa mínima aplicada)',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (wasRounded)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '(Redondeado a \$0.05 — efectivo)',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 12),

          // Método de pago
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.tertiary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  paymentMethod == 'Efectivo'
                      ? Icons.payments_outlined
                      : Icons.account_balance_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  paymentMethod,
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Tiempo y distancia
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${session.totalDistanceKm.toStringAsFixed(1)} km · ${session.elapsedFormatted}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'No pagó',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.payments, size: 18),
                label: const Text(
                  'Confirmar pago',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: AppTextStyles.body2.copyWith(
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
