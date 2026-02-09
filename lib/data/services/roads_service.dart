// lib/data/services/roads_service.dart
// Servicio para Google Roads API — Snap to Roads
// Ajusta coordenadas GPS a la carretera más cercana

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class RoadsService {
  static String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  /// Ajusta un punto GPS a la carretera más cercana
  /// Retorna la posición ajustada o la original si falla
  static Future<LatLng> snapToRoad(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://roads.googleapis.com/v1/snapToRoads'
        '?path=$lat,$lng'
        '&key=$_apiKey',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 3),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final points = data['snappedPoints'] as List?;
        if (points != null && points.isNotEmpty) {
          final loc = points[0]['location'];
          return LatLng(
            loc['latitude'] as double,
            loc['longitude'] as double,
          );
        }
      } else {
        debugPrint('⚠️ Roads API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Snap to road error: $e');
    }
    // Fallback: devolver la posición original
    return LatLng(lat, lng);
  }

  /// Ajusta múltiples puntos GPS a las carreteras más cercanas
  /// Soporta hasta 100 puntos por petición
  /// Retorna las posiciones ajustadas en el mismo orden
  static Future<List<LatLng>> snapMultipleToRoad(List<LatLng> points) async {
    if (points.isEmpty) return points;
    if (points.length > 100) {
      // Roads API soporta máximo 100 puntos
      points = points.sublist(points.length - 100);
    }

    try {
      final pathStr = points
          .map((p) => '${p.latitude},${p.longitude}')
          .join('|');

      final url = Uri.parse(
        'https://roads.googleapis.com/v1/snapToRoads'
        '?interpolate=true'
        '&path=$pathStr'
        '&key=$_apiKey',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final snappedPoints = data['snappedPoints'] as List?;
        if (snappedPoints != null && snappedPoints.isNotEmpty) {
          return snappedPoints.map((p) {
            final loc = p['location'];
            return LatLng(
              loc['latitude'] as double,
              loc['longitude'] as double,
            );
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Snap multiple to road error: $e');
    }
    return points;
  }
}
