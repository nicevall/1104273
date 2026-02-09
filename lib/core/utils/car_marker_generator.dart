// lib/core/utils/car_marker_generator.dart
// Genera un ícono de carro 3D estilo Uber para Google Maps
// Usado tanto por el conductor como por el pasajero

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CarMarkerGenerator {
  /// Genera un ícono de carro 3D estilo Uber profesional
  /// Vista top-down con perspectiva isométrica sutil
  /// Color oscuro tipo sedan ejecutivo
  static Future<BitmapDescriptor?> generate({
    double size = 180,
  }) async {
    // 1. Intentar cargar asset personalizado primero
    try {
      final icon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/icons/car_marker.png',
      );
      debugPrint('🚗 Car marker cargado desde asset');
      return icon;
    } catch (_) {
      debugPrint(
          'ℹ️ Asset car_marker.png no encontrado, generando programáticamente...');
    }

    // 2. Fallback: generación programática
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final cx = size / 2;
      final cy = size / 2;

      // Proporciones del carro (sedan tipo Uber)
      final carW = size * 0.38; // ancho del carro
      final carH = size * 0.72; // largo del carro (más largo que ancho)
      final halfW = carW / 2;
      final halfH = carH / 2;

      // Colores principales (negro/gris oscuro tipo Uber)
      const bodyColor = Color(0xFF2C2C2E); // gris muy oscuro
      const bodyLight = Color(0xFF3A3A3C);
      const bodyDark = Color(0xFF1C1C1E);
      const roofColor = Color(0xFF1C1C1E); // más oscuro que el cuerpo
      const glassColor = Color(0xFF5AC8FA); // azul cristal
      const glassDark = Color(0xFF007AFF);

      // ============================================
      // 1. SOMBRA PROYECTADA (da efecto de elevación 3D)
      // ============================================
      // Sombra principal — ovalada, difusa, desplazada
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + 3, cy + 8),
          width: carW + 8,
          height: carH + 4,
        ),
        shadowPaint,
      );

      // Sombra cercana (más definida)
      final closeShadow = Paint()
        ..color = Colors.black.withOpacity(0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + 1, cy + 4),
          width: carW + 2,
          height: carH - 4,
        ),
        closeShadow,
      );

      // ============================================
      // 2. CUERPO PRINCIPAL (carrocería)
      // ============================================
      final bodyPath = _buildBodyPath(cx, cy, halfW, halfH);

      // Gradiente lateral (simula curvatura 3D del carro)
      final bodyPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - halfW, cy),
          Offset(cx + halfW, cy),
          [
            bodyDark,
            bodyColor,
            bodyLight,
            const Color(0xFF48484A), // highlight central
            bodyLight,
            bodyColor,
            bodyDark,
          ],
          [0.0, 0.08, 0.25, 0.5, 0.75, 0.92, 1.0],
        );
      canvas.drawPath(bodyPath, bodyPaint);

      // Gradiente vertical superpuesto (profundidad frente/atrás)
      final bodyVertPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, cy - halfH),
          Offset(cx, cy + halfH),
          [
            Colors.white.withOpacity(0.06),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.08),
          ],
          [0.0, 0.3, 0.7, 1.0],
        );
      canvas.drawPath(bodyPath, bodyVertPaint);

      // Borde fino del cuerpo (contorno metálico)
      final bodyStroke = Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawPath(bodyPath, bodyStroke);

      // ============================================
      // 3. GUARDAFANGOS / PASOS DE RUEDA
      // ============================================
      _drawWheelWells(canvas, cx, cy, halfW, halfH);

      // ============================================
      // 4. CAPÓ DELANTERO (hood)
      // ============================================
      final hoodPath = Path();
      final hoodTop = cy - halfH * 0.65;
      final hoodBot = cy - halfH * 0.20;
      hoodPath.moveTo(cx - halfW * 0.82, hoodBot);
      hoodPath.lineTo(cx - halfW * 0.72, hoodTop);
      hoodPath.quadraticBezierTo(cx, hoodTop - 4, cx + halfW * 0.72, hoodTop);
      hoodPath.lineTo(cx + halfW * 0.82, hoodBot);
      hoodPath.close();

      final hoodPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, hoodTop),
          Offset(cx, hoodBot),
          [
            bodyLight,
            bodyColor,
          ],
        );
      canvas.drawPath(hoodPath, hoodPaint);

      // Línea central del capó (detalle realista)
      final hoodLine = Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(cx, hoodTop - 2),
        Offset(cx, hoodBot),
        hoodLine,
      );

      // ============================================
      // 5. PARABRISAS DELANTERO (windshield)
      // ============================================
      final wsTop = hoodTop - 1;
      final wsBot = cy - halfH * 0.22;
      final wsPath = Path();
      wsPath.moveTo(cx - halfW * 0.68, wsBot);
      wsPath.lineTo(cx - halfW * 0.55, wsTop);
      wsPath.quadraticBezierTo(cx, wsTop - 6, cx + halfW * 0.55, wsTop);
      wsPath.lineTo(cx + halfW * 0.68, wsBot);
      wsPath.close();

      // Cristal con reflejo
      final wsPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - halfW * 0.3, wsTop),
          Offset(cx + halfW * 0.4, wsBot),
          [
            glassDark.withOpacity(0.7),
            glassColor.withOpacity(0.5),
            Colors.white.withOpacity(0.4),
            glassColor.withOpacity(0.3),
          ],
          [0.0, 0.3, 0.55, 1.0],
        );
      canvas.drawPath(wsPath, wsPaint);

      // Borde del parabrisas
      final wsBorder = Paint()
        ..color = Colors.black.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawPath(wsPath, wsBorder);

      // ============================================
      // 6. TECHO / CABINA
      // ============================================
      final roofTop = cy - halfH * 0.18;
      final roofBot = cy + halfH * 0.22;
      final roofPath = Path();
      final roofHW = halfW * 0.62; // ancho del techo
      roofPath.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - roofHW, roofTop, cx + roofHW, roofBot),
        const Radius.circular(6),
      ));

      final roofPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - roofHW, cy),
          Offset(cx + roofHW, cy),
          [
            roofColor,
            const Color(0xFF2C2C2E),
            const Color(0xFF3A3A3C), // brillo central
            const Color(0xFF2C2C2E),
            roofColor,
          ],
          [0.0, 0.2, 0.5, 0.8, 1.0],
        );
      canvas.drawPath(roofPath, roofPaint);

      // Highlight especular del techo (efecto sol)
      final roofHighlight = Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx - roofHW * 0.2, roofTop + (roofBot - roofTop) * 0.35),
          roofHW * 0.7,
          [
            Colors.white.withOpacity(0.18),
            Colors.white.withOpacity(0.0),
          ],
        );
      canvas.drawPath(roofPath, roofHighlight);

      // Borde del techo
      final roofBorder = Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawPath(roofPath, roofBorder);

      // ============================================
      // 7. VENTANAS LATERALES
      // ============================================
      // Ventana izquierda
      _drawSideWindow(canvas, cx - roofHW - 1, roofTop + 3, roofBot - 3, -1, halfW * 0.25);
      // Ventana derecha
      _drawSideWindow(canvas, cx + roofHW + 1, roofTop + 3, roofBot - 3, 1, halfW * 0.25);

      // ============================================
      // 8. PARABRISAS TRASERO
      // ============================================
      final rwsTop = roofBot + 1;
      final rwsBot = cy + halfH * 0.35;
      final rwsPath = Path();
      rwsPath.moveTo(cx - halfW * 0.60, rwsTop);
      rwsPath.lineTo(cx + halfW * 0.60, rwsTop);
      rwsPath.lineTo(cx + halfW * 0.50, rwsBot);
      rwsPath.lineTo(cx - halfW * 0.50, rwsBot);
      rwsPath.close();

      final rwsPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - halfW * 0.3, rwsTop),
          Offset(cx + halfW * 0.3, rwsBot),
          [
            glassDark.withOpacity(0.5),
            glassColor.withOpacity(0.3),
          ],
        );
      canvas.drawPath(rwsPath, rwsPaint);
      canvas.drawPath(rwsPath, Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0);

      // ============================================
      // 9. MALETERO (trunk)
      // ============================================
      final trunkTop = rwsBot;
      final trunkBot = cy + halfH * 0.85;
      final trunkPath = Path();
      trunkPath.moveTo(cx - halfW * 0.80, trunkTop);
      trunkPath.lineTo(cx + halfW * 0.80, trunkTop);
      trunkPath.quadraticBezierTo(
        cx + halfW * 0.80, trunkBot,
        cx, trunkBot + 2,
      );
      trunkPath.quadraticBezierTo(
        cx - halfW * 0.80, trunkBot,
        cx - halfW * 0.80, trunkTop,
      );
      trunkPath.close();

      final trunkPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, trunkTop),
          Offset(cx, trunkBot),
          [bodyColor, bodyDark],
        );
      canvas.drawPath(trunkPath, trunkPaint);

      // ============================================
      // 10. LUCES DELANTERAS
      // ============================================
      // Izquierda
      _drawHeadlight(canvas, cx - halfW * 0.72, cy - halfH * 0.78, false);
      // Derecha
      _drawHeadlight(canvas, cx + halfW * 0.72, cy - halfH * 0.78, true);

      // ============================================
      // 11. LUCES TRASERAS
      // ============================================
      // Izquierda
      _drawTaillight(canvas, cx - halfW * 0.72, cy + halfH * 0.72);
      // Derecha
      _drawTaillight(canvas, cx + halfW * 0.72, cy + halfH * 0.72);

      // Línea reflectante trasera (barra de LED entre luces)
      final ledBar = Paint()
        ..color = Colors.red.withOpacity(0.3)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(cx - halfW * 0.55, cy + halfH * 0.72),
        Offset(cx + halfW * 0.55, cy + halfH * 0.72),
        ledBar,
      );

      // ============================================
      // 12. ESPEJOS LATERALES
      // ============================================
      _drawMirror(canvas, cx - halfW - 2, cy - halfH * 0.12, bodyColor);
      _drawMirror(canvas, cx + halfW + 2, cy - halfH * 0.12, bodyColor);

      // ============================================
      // 13. REFLEJO ESPECULAR GLOBAL (brillo de sol)
      // ============================================
      final sunReflection = Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx - size * 0.05, cy - size * 0.12),
          size * 0.25,
          [
            Colors.white.withOpacity(0.12),
            Colors.white.withOpacity(0.0),
          ],
        );
      canvas.drawPath(bodyPath, sunReflection);

      // Renderizar
      final picture = recorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        debugPrint('🚗 Car marker 3D generado programáticamente (${size.toInt()}px)');
        return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint('⚠️ Error generando ícono 3D de carro: $e');
    }
    return null;
  }

  /// Construye el path del cuerpo principal del carro (sedan aerodinámico)
  static Path _buildBodyPath(double cx, double cy, double halfW, double halfH) {
    final path = Path();
    // Punta delantera (nariz aerodinámica)
    path.moveTo(cx, cy - halfH);
    // Lado derecho delantero (curva de la nariz)
    path.cubicTo(
      cx + halfW * 0.4, cy - halfH,
      cx + halfW * 0.85, cy - halfH * 0.85,
      cx + halfW, cy - halfH * 0.55,
    );
    // Lado derecho (línea con ligera curva)
    path.cubicTo(
      cx + halfW * 1.05, cy - halfH * 0.2,
      cx + halfW * 1.05, cy + halfH * 0.3,
      cx + halfW, cy + halfH * 0.55,
    );
    // Cola trasera derecha
    path.cubicTo(
      cx + halfW * 0.85, cy + halfH * 0.85,
      cx + halfW * 0.4, cy + halfH,
      cx, cy + halfH,
    );
    // Cola trasera izquierda
    path.cubicTo(
      cx - halfW * 0.4, cy + halfH,
      cx - halfW * 0.85, cy + halfH * 0.85,
      cx - halfW, cy + halfH * 0.55,
    );
    // Lado izquierdo
    path.cubicTo(
      cx - halfW * 1.05, cy + halfH * 0.3,
      cx - halfW * 1.05, cy - halfH * 0.2,
      cx - halfW, cy - halfH * 0.55,
    );
    // Nariz izquierda
    path.cubicTo(
      cx - halfW * 0.85, cy - halfH * 0.85,
      cx - halfW * 0.4, cy - halfH,
      cx, cy - halfH,
    );
    path.close();
    return path;
  }

  /// Dibuja los huecos de las ruedas (wheel wells)
  static void _drawWheelWells(Canvas canvas, double cx, double cy, double halfW, double halfH) {
    final wheelPaint = Paint()..color = const Color(0xFF111111);
    final tirePaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Ruedas delanteras
    final fWheelY = cy - halfH * 0.48;
    // Izquierda
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - halfW * 0.88, fWheelY), width: 7, height: 14),
      wheelPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - halfW * 0.88, fWheelY), width: 7, height: 14),
      tirePaint,
    );
    // Derecha
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + halfW * 0.88, fWheelY), width: 7, height: 14),
      wheelPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + halfW * 0.88, fWheelY), width: 7, height: 14),
      tirePaint,
    );

    // Ruedas traseras
    final rWheelY = cy + halfH * 0.48;
    // Izquierda
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - halfW * 0.88, rWheelY), width: 7, height: 14),
      wheelPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - halfW * 0.88, rWheelY), width: 7, height: 14),
      tirePaint,
    );
    // Derecha
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + halfW * 0.88, rWheelY), width: 7, height: 14),
      wheelPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + halfW * 0.88, rWheelY), width: 7, height: 14),
      tirePaint,
    );
  }

  /// Dibuja una ventana lateral
  static void _drawSideWindow(Canvas canvas, double x, double top, double bot, int side, double w) {
    final path = Path();
    if (side < 0) {
      // Izquierda
      path.moveTo(x, top + 2);
      path.lineTo(x - w, top + 5);
      path.lineTo(x - w, bot - 5);
      path.lineTo(x, bot - 2);
      path.close();
    } else {
      // Derecha
      path.moveTo(x, top + 2);
      path.lineTo(x + w, top + 5);
      path.lineTo(x + w, bot - 5);
      path.lineTo(x, bot - 2);
      path.close();
    }

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(x, top),
        Offset(x, bot),
        [
          const Color(0xFF5AC8FA).withOpacity(0.35),
          const Color(0xFF007AFF).withOpacity(0.2),
        ],
      );
    canvas.drawPath(path, paint);
    canvas.drawPath(path, Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6);
  }

  /// Dibuja un faro delantero
  static void _drawHeadlight(Canvas canvas, double x, double y, bool isRight) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(x, y),
        6,
        [
          Colors.white.withOpacity(0.95),
          Colors.yellow.withOpacity(0.3),
          Colors.white.withOpacity(0.0),
        ],
        [0.0, 0.5, 1.0],
      );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: 8, height: 10),
      paint,
    );
    // Centro brillante
    canvas.drawCircle(
      Offset(x, y),
      2.5,
      Paint()..color = Colors.white.withOpacity(0.9),
    );
  }

  /// Dibuja una luz trasera
  static void _drawTaillight(Canvas canvas, double x, double y) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(x, y),
        6,
        [
          Colors.red.withOpacity(0.9),
          Colors.red.withOpacity(0.4),
          Colors.red.withOpacity(0.0),
        ],
        [0.0, 0.6, 1.0],
      );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: 7, height: 8),
      paint,
    );
    // Centro rojo brillante
    canvas.drawCircle(
      Offset(x, y),
      2,
      Paint()..color = Colors.red.withOpacity(0.95),
    );
  }

  /// Dibuja un espejo lateral
  static void _drawMirror(Canvas canvas, double x, double y, Color color) {
    final path = Path();
    path.addOval(Rect.fromCenter(center: Offset(x, y), width: 5, height: 8));
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(path, Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5);
  }
}
