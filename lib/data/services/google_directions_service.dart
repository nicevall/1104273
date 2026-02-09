// lib/data/services/google_directions_service.dart
// Servicio para obtener rutas, navegación turn-by-turn y calcular desvíos
// usando Google Directions API

import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/route_info.dart';
import '../models/trip_model.dart';

class GoogleDirectionsService {
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/directions/json';

  final String _apiKey;

  GoogleDirectionsService()
      : _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  /// Obtener ruta entre dos puntos
  Future<RouteInfo?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Google Maps API key no configurada');
    }

    final url = Uri.parse(
      '$_baseUrl?'
      'origin=$originLat,$originLng'
      '&destination=$destLat,$destLng'
      '&mode=driving'
      '&language=es'
      '&key=$_apiKey',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Error en API: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['status'] != 'OK') {
        if (data['status'] == 'ZERO_RESULTS') {
          return null;
        }
        throw Exception('Directions API error: ${data['status']}');
      }

      final route = data['routes'][0];
      final legs = route['legs'] as List;

      final encodedPolyline = route['overview_polyline']['points'] as String;
      final polylinePoints = _decodePolyline(encodedPolyline);

      // Extraer pasos de navegación de todos los legs
      final steps = _parseStepsFromLegs(legs);

      return RouteInfo(
        encodedPolyline: encodedPolyline,
        durationSeconds: legs[0]['duration']['value'] as int,
        distanceMeters: legs[0]['distance']['value'] as int,
        polylinePoints: polylinePoints,
        summary: route['summary'] as String?,
        steps: steps,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Obtener ruta con un waypoint (punto de recogida)
  Future<RouteInfo?> getRouteWithWaypoint({
    required double originLat,
    required double originLng,
    required double waypointLat,
    required double waypointLng,
    required double destLat,
    required double destLng,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Google Maps API key no configurada');
    }

    final url = Uri.parse(
      '$_baseUrl?'
      'origin=$originLat,$originLng'
      '&destination=$destLat,$destLng'
      '&waypoints=$waypointLat,$waypointLng'
      '&mode=driving'
      '&language=es'
      '&key=$_apiKey',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Error en API: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['status'] != 'OK') {
        if (data['status'] == 'ZERO_RESULTS') {
          return null;
        }
        throw Exception('Directions API error: ${data['status']}');
      }

      final route = data['routes'][0];
      final legs = route['legs'] as List;

      // Con waypoint, hay múltiples legs - sumar duración y distancia
      int totalDuration = 0;
      int totalDistance = 0;

      for (final leg in legs) {
        totalDuration += leg['duration']['value'] as int;
        totalDistance += leg['distance']['value'] as int;
      }

      final encodedPolyline = route['overview_polyline']['points'] as String;
      final polylinePoints = _decodePolyline(encodedPolyline);

      // Extraer pasos de navegación de todos los legs
      final steps = _parseStepsFromLegs(legs);

      return RouteInfo(
        encodedPolyline: encodedPolyline,
        durationSeconds: totalDuration,
        distanceMeters: totalDistance,
        polylinePoints: polylinePoints,
        summary: route['summary'] as String?,
        steps: steps,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Obtener ruta con múltiples waypoints (varios pasajeros)
  Future<RouteInfo?> getRouteWithMultipleWaypoints({
    required double originLat,
    required double originLng,
    required List<LatLng> waypoints,
    required double destLat,
    required double destLng,
    bool optimizeWaypoints = false,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Google Maps API key no configurada');
    }

    if (waypoints.isEmpty) {
      return getRoute(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
      );
    }

    // Construir string de waypoints
    final waypointsStr = waypoints
        .map((wp) => '${wp.latitude},${wp.longitude}')
        .join('|');

    final optimizeParam = optimizeWaypoints ? 'optimize:true|' : '';

    final url = Uri.parse(
      '$_baseUrl?'
      'origin=$originLat,$originLng'
      '&destination=$destLat,$destLng'
      '&waypoints=$optimizeParam$waypointsStr'
      '&mode=driving'
      '&language=es'
      '&key=$_apiKey',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Error en API: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['status'] != 'OK') {
        if (data['status'] == 'ZERO_RESULTS') {
          return null;
        }
        throw Exception('Directions API error: ${data['status']}');
      }

      final route = data['routes'][0];
      final legs = route['legs'] as List;

      int totalDuration = 0;
      int totalDistance = 0;

      for (final leg in legs) {
        totalDuration += leg['duration']['value'] as int;
        totalDistance += leg['distance']['value'] as int;
      }

      final encodedPolyline = route['overview_polyline']['points'] as String;
      final polylinePoints = _decodePolyline(encodedPolyline);

      // Extraer pasos de navegación de todos los legs
      final steps = _parseStepsFromLegs(legs);

      return RouteInfo(
        encodedPolyline: encodedPolyline,
        durationSeconds: totalDuration,
        distanceMeters: totalDistance,
        polylinePoints: polylinePoints,
        summary: route['summary'] as String?,
        steps: steps,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Calcular el desvío al agregar un punto de recogida
  Future<DeviationInfo?> calculateDeviation({
    required TripLocation origin,
    required TripLocation destination,
    required TripLocation pickup,
  }) async {
    final originalRoute = await getRoute(
      originLat: origin.latitude,
      originLng: origin.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );

    if (originalRoute == null) return null;

    final routeWithPickup = await getRouteWithWaypoint(
      originLat: origin.latitude,
      originLng: origin.longitude,
      waypointLat: pickup.latitude,
      waypointLng: pickup.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );

    if (routeWithPickup == null) return null;

    final deviationMinutes =
        routeWithPickup.durationMinutes - originalRoute.durationMinutes;
    final deviationMeters =
        routeWithPickup.distanceMeters - originalRoute.distanceMeters;

    return DeviationInfo(
      originalDurationMinutes: originalRoute.durationMinutes,
      newDurationMinutes: routeWithPickup.durationMinutes,
      deviationMinutes: deviationMinutes < 0 ? 0 : deviationMinutes,
      originalDistanceMeters: originalRoute.distanceMeters,
      newDistanceMeters: routeWithPickup.distanceMeters,
      deviationDistanceMeters: deviationMeters < 0 ? 0 : deviationMeters,
      originalRoute: originalRoute,
      routeWithPickup: routeWithPickup,
    );
  }

  /// Calcular desvío total con múltiples pasajeros aceptados
  Future<DeviationInfo?> calculateTotalDeviation({
    required TripLocation origin,
    required TripLocation destination,
    required List<TripLocation> acceptedPickups,
    required TripLocation newPickup,
  }) async {
    final currentWaypoints =
        acceptedPickups.map((p) => LatLng(p.latitude, p.longitude)).toList();

    final currentRoute = await getRouteWithMultipleWaypoints(
      originLat: origin.latitude,
      originLng: origin.longitude,
      waypoints: currentWaypoints,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );

    if (currentRoute == null) return null;

    final newWaypoints = [
      ...currentWaypoints,
      LatLng(newPickup.latitude, newPickup.longitude),
    ];

    final newRoute = await getRouteWithMultipleWaypoints(
      originLat: origin.latitude,
      originLng: origin.longitude,
      waypoints: newWaypoints,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );

    if (newRoute == null) return null;

    final deviationMinutes =
        newRoute.durationMinutes - currentRoute.durationMinutes;
    final deviationMeters =
        newRoute.distanceMeters - currentRoute.distanceMeters;

    return DeviationInfo(
      originalDurationMinutes: currentRoute.durationMinutes,
      newDurationMinutes: newRoute.durationMinutes,
      deviationMinutes: deviationMinutes < 0 ? 0 : deviationMinutes,
      originalDistanceMeters: currentRoute.distanceMeters,
      newDistanceMeters: newRoute.distanceMeters,
      deviationDistanceMeters: deviationMeters < 0 ? 0 : deviationMeters,
      originalRoute: currentRoute,
      routeWithPickup: newRoute,
    );
  }

  // ============================================================
  // HELPERS PRIVADOS
  // ============================================================

  /// Parsea los pasos de navegación de todos los legs de la respuesta
  List<NavigationStep> _parseStepsFromLegs(List legs) {
    final steps = <NavigationStep>[];

    for (final leg in legs) {
      final legSteps = leg['steps'] as List? ?? [];

      for (final step in legSteps) {
        final htmlInstruction = step['html_instructions'] as String? ?? '';
        final instruction = stripHtmlTags(htmlInstruction);

        if (instruction.isEmpty) continue;

        final startLoc = step['start_location'];
        final endLoc = step['end_location'];

        steps.add(NavigationStep(
          instruction: instruction,
          distanceMeters: step['distance']?['value'] as int? ?? 0,
          durationSeconds: step['duration']?['value'] as int? ?? 0,
          startLocation: LatLng(
            (startLoc['lat'] as num).toDouble(),
            (startLoc['lng'] as num).toDouble(),
          ),
          endLocation: LatLng(
            (endLoc['lat'] as num).toDouble(),
            (endLoc['lng'] as num).toDouble(),
          ),
          maneuver: step['maneuver'] as String?,
        ));
      }
    }

    return steps;
  }

  /// Decodificar polyline de Google a lista de LatLng
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += deltaLat;

      shift = 0;
      result = 0;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += deltaLng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  /// Método público para decodificar polyline
  List<LatLng> decodePolyline(String encoded) => _decodePolyline(encoded);
}
