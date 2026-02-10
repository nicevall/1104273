// lib/presentation/widgets/driver/taximeter_widget.dart
// Widget flotante de taxímetro para la pantalla del conductor
// Muestra tarifa individual por cada pasajero a bordo

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/services/taximeter_service.dart';

class TaximeterWidget extends StatefulWidget {
  final List<TaximeterSession> sessions;
  final Map<String, String> passengerNames; // passengerId → nombre
  final bool isNightTariff;
  final void Function(String passengerId) onDropOff;

  const TaximeterWidget({
    super.key,
    required this.sessions,
    required this.passengerNames,
    required this.isNightTariff,
    required this.onDropOff,
  });

  @override
  State<TaximeterWidget> createState() => _TaximeterWidgetState();
}

class _TaximeterWidgetState extends State<TaximeterWidget> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.sessions.isEmpty) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildHeader(),
          // Contenido colapsable
          if (_isExpanded) ...[
            const Divider(height: 1),
            ...widget.sessions.map(_buildPassengerMeter),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final totalFare = widget.sessions.fold<double>(
      0.0,
      (sum, s) => sum + s.currentFare,
    );

    return InkWell(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Icono taxímetro
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.speed_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            // Título + total
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TAXIMETRO',
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: 1.2,
                      fontSize: 11,
                    ),
                  ),
                  if (widget.sessions.length > 1)
                    Text(
                      '${widget.sessions.length} pasajeros · Total: \$${totalFare.toStringAsFixed(2)}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            // Badge tarifa
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: widget.isNightTariff
                    ? Colors.indigo.withValues(alpha: 0.12)
                    : Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isNightTariff
                        ? Icons.nightlight_round
                        : Icons.wb_sunny_rounded,
                    size: 14,
                    color: widget.isNightTariff ? Colors.indigo : Colors.amber.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.isNightTariff ? 'Nocturna' : 'Diurna',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: widget.isNightTariff ? Colors.indigo : Colors.amber.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Colapsar/expandir
            Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassengerMeter(TaximeterSession session) {
    final name = widget.passengerNames[session.passengerId] ?? 'Pasajero';
    final firstName = name.split(' ').first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Nombre y detalles
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre + tiempo
                Row(
                  children: [
                    Text(
                      firstName,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      session.elapsedFormatted,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Distancia + espera + descuento
                Row(
                  children: [
                    Text(
                      '${session.totalDistanceKm.toStringAsFixed(1)} km'
                      '${session.totalWaitMinutes > 0.5 ? ' · ${session.totalWaitMinutes.round()} min espera' : ''}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (session.discountPercent > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '-${(session.discountPercent * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Tarifa grande
          Text(
            '\$${session.currentFare.toStringAsFixed(2)}',
            style: AppTextStyles.h3.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              fontSize: 22,
            ),
          ),
          const SizedBox(width: 10),
          // Botón dejar aquí
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: () => widget.onDropOff(session.passengerId),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error, width: 1),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: Size.zero,
              ),
              child: const Text(
                'Dejar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
