// lib/data/models/route_info.dart
// Modelo para información de rutas y cálculo de desvíos

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Información de una ruta entre dos puntos
class RouteInfo {
  /// Polyline codificado de Google
  final String encodedPolyline;

  /// Duración total en segundos
  final int durationSeconds;

  /// Distancia total en metros
  final int distanceMeters;

  /// Puntos decodificados del polyline (para dibujar en el mapa)
  final List<LatLng> polylinePoints;

  /// Resumen de la ruta (ej: "Via Av. 10 de Agosto")
  final String? summary;

  const RouteInfo({
    required this.encodedPolyline,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.polylinePoints,
    this.summary,
  });

  /// Duración en minutos (redondeado hacia arriba)
  int get durationMinutes => (durationSeconds / 60).ceil();

  /// Distancia en kilómetros
  double get distanceKm => distanceMeters / 1000;

  /// Texto formateado de duración
  String get durationText {
    if (durationMinutes < 60) {
      return '$durationMinutes min';
    }
    final hours = durationMinutes ~/ 60;
    final mins = durationMinutes % 60;
    return '${hours}h ${mins}min';
  }

  /// Texto formateado de distancia
  String get distanceText {
    if (distanceMeters < 1000) {
      return '$distanceMeters m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  @override
  String toString() {
    return 'RouteInfo(duration: $durationText, distance: $distanceText)';
  }
}

/// Información de desvío al agregar un punto de recogida
class DeviationInfo {
  /// Duración de la ruta original (directa) en minutos
  final int originalDurationMinutes;

  /// Duración de la ruta con el punto de recogida en minutos
  final int newDurationMinutes;

  /// Diferencia (tiempo extra por el desvío) en minutos
  final int deviationMinutes;

  /// Distancia original en metros
  final int originalDistanceMeters;

  /// Distancia con desvío en metros
  final int newDistanceMeters;

  /// Distancia extra por el desvío en metros
  final int deviationDistanceMeters;

  /// Ruta original (sin desvío)
  final RouteInfo originalRoute;

  /// Ruta con el punto de recogida
  final RouteInfo routeWithPickup;

  const DeviationInfo({
    required this.originalDurationMinutes,
    required this.newDurationMinutes,
    required this.deviationMinutes,
    required this.originalDistanceMeters,
    required this.newDistanceMeters,
    required this.deviationDistanceMeters,
    required this.originalRoute,
    required this.routeWithPickup,
  });

  /// Porcentaje de incremento en tiempo
  double get timeIncreasePercent {
    if (originalDurationMinutes == 0) return 0;
    return (deviationMinutes / originalDurationMinutes) * 100;
  }

  /// Texto formateado del desvío
  String get deviationText => '+$deviationMinutes min';

  /// Si el desvío es significativo (más de 10 minutos o 30%)
  bool get isSignificant =>
      deviationMinutes > 10 || timeIncreasePercent > 30;

  @override
  String toString() {
    return 'DeviationInfo(original: ${originalDurationMinutes}min, '
        'new: ${newDurationMinutes}min, deviation: $deviationText)';
  }
}
