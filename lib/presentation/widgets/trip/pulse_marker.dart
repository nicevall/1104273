// lib/presentation/widgets/trip/pulse_marker.dart
// Widget de marcador con animación de pulso
// Usado para mostrar origen y destino antes de confirmar conductor

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class PulseMarker extends StatefulWidget {
  final Color color;
  final double size;
  final bool isSquare; // true para destino (cuadrado), false para origen (círculo)

  const PulseMarker({
    super.key,
    this.color = AppColors.primary,
    this.size = 20,
    this.isSquare = false,
  });

  @override
  State<PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<PulseMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 1.0, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 3,
      height: widget.size * 3,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Círculo/cuadrado de pulso (animado)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(_opacityAnimation.value),
                    shape: widget.isSquare ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: widget.isSquare
                        ? BorderRadius.circular(widget.size * 0.15)
                        : null,
                  ),
                ),
              );
            },
          ),

          // Marcador central (estático)
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: widget.isSquare ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: widget.isSquare
                  ? BorderRadius.circular(widget.size * 0.15)
                  : null,
              border: Border.all(
                color: Colors.white,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget para mostrar línea punteada entre dos puntos
class DottedLine extends StatelessWidget {
  final double height;
  final Color color;

  const DottedLine({
    super.key,
    this.height = 100,
    this.color = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: 2,
      child: CustomPaint(
        painter: _DottedLinePainter(color: color),
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  final Color color;

  _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dashHeight = 5.0;
    const dashSpace = 5.0;
    double startY = 0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
