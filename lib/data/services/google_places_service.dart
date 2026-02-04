// lib/data/services/google_places_service.dart
// Servicio para Google Places API
// Proporciona autocompletado de direcciones y detalles de lugares

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_webservice/places.dart' as gmaps;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GooglePlacesService {
  // API Key de Google Maps - cargada desde .env
  static String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  late final gmaps.GoogleMapsPlaces _places;

  GooglePlacesService() {
    _places = gmaps.GoogleMapsPlaces(apiKey: _apiKey);
  }

  /// Buscar lugares con autocompletado
  ///
  /// [query] - Texto de búsqueda
  /// [location] - Ubicación para sesgar resultados (opcional)
  /// [radius] - Radio en metros para sesgar resultados (opcional)
  /// [language] - Idioma de los resultados (default: español)
  /// [country] - Código de país para restringir resultados (default: Ecuador)
  Future<List<PlaceSuggestion>> searchPlaces({
    required String query,
    gmaps.Location? location,
    int radius = 50000, // 50km por defecto
    String language = 'es',
    String country = 'ec',
  }) async {
    if (query.isEmpty || query.length < 2) {
      return [];
    }

    try {
      final response = await _places.autocomplete(
        query,
        location: location,
        radius: radius,
        language: language,
        components: [gmaps.Component(gmaps.Component.country, country)],
      );

      if (response.isOkay) {
        return response.predictions.map((prediction) {
          return PlaceSuggestion(
            placeId: prediction.placeId ?? '',
            description: prediction.description ?? '',
            mainText: prediction.structuredFormatting?.mainText ?? prediction.description ?? '',
            secondaryText: prediction.structuredFormatting?.secondaryText ?? '',
          );
        }).toList();
      } else {
        print('Error en Places API: ${response.errorMessage}');
        return [];
      }
    } catch (e) {
      print('Error al buscar lugares: $e');
      return [];
    }
  }

  /// Obtener detalles de un lugar por su placeId
  ///
  /// Retorna coordenadas y dirección completa
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    if (placeId.isEmpty) return null;

    try {
      final response = await _places.getDetailsByPlaceId(
        placeId,
        language: 'es',
      );

      if (response.isOkay && response.result != null) {
        final result = response.result!;
        final lat = result.geometry?.location.lat;
        final lng = result.geometry?.location.lng;

        if (lat == null || lng == null) {
          print('Error: No se encontraron coordenadas para el lugar');
          return null;
        }

        return PlaceDetails(
          placeId: placeId,
          name: result.name ?? 'Sin nombre',
          address: result.formattedAddress ?? '',
          latitude: lat,
          longitude: lng,
        );
      } else {
        print('Error al obtener detalles: ${response.errorMessage}');
        return null;
      }
    } catch (e) {
      print('Error al obtener detalles del lugar: $e');
      return null;
    }
  }

  /// Verifica si un texto es un Plus Code (Open Location Code)
  /// Formato: XXXX+XXX o similar (ej: XRP3+589)
  bool _isPlusCode(String? text) {
    if (text == null || text.isEmpty) return false;
    // Plus Codes tienen formato: 4-8 caracteres + signo + + 2-4 caracteres
    return RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}', caseSensitive: false).hasMatch(text);
  }

  /// Limpia una dirección removiendo Plus Codes
  String _cleanAddress(String address) {
    // Remover Plus Codes del formato "XRP3+589, Ciudad, País"
    final parts = address.split(',').map((s) => s.trim()).toList();
    final cleanParts = parts.where((part) => !_isPlusCode(part)).toList();
    return cleanParts.join(', ');
  }

  /// Reverse geocoding usando Google Geocoding API
  /// Obtiene la dirección a partir de coordenadas
  Future<ReverseGeocodeResult?> reverseGeocode(double latitude, double longitude) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=$latitude,$longitude'
        '&language=es'
        '&key=$_apiKey'
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['results'] != null && data['results'].isNotEmpty) {
          // Buscar en múltiples resultados para encontrar la mejor dirección
          String? bestRoute;
          String? bestStreetNumber;
          String? bestSublocality;
          String? bestLocality;
          String? bestNeighborhood;
          String? bestFormattedAddress;

          for (var result in data['results']) {
            final types = List<String>.from(result['types'] ?? []);

            // Priorizar resultados de tipo street_address o route
            bool isGoodResult = types.contains('street_address') ||
                                types.contains('route') ||
                                types.contains('premise') ||
                                types.contains('subpremise');

            for (var component in result['address_components'] ?? []) {
              final componentTypes = List<String>.from(component['types'] ?? []);
              final longName = component['long_name'] as String?;

              // Ignorar Plus Codes
              if (longName != null && _isPlusCode(longName)) continue;

              if (componentTypes.contains('street_number') && bestStreetNumber == null) {
                bestStreetNumber = longName;
              } else if (componentTypes.contains('route') && bestRoute == null) {
                bestRoute = longName;
              } else if ((componentTypes.contains('neighborhood') || componentTypes.contains('sublocality_level_1')) && bestNeighborhood == null) {
                bestNeighborhood = longName;
              } else if (componentTypes.contains('sublocality') && bestSublocality == null) {
                bestSublocality = longName;
              } else if (componentTypes.contains('locality') && bestLocality == null) {
                bestLocality = longName;
              }
            }

            // Guardar la mejor dirección formateada (sin Plus Code)
            if (bestFormattedAddress == null && result['formatted_address'] != null) {
              final cleaned = _cleanAddress(result['formatted_address']);
              if (cleaned.isNotEmpty) {
                bestFormattedAddress = cleaned;
              }
            }

            // Si ya encontramos una calle, salir del loop
            if (bestRoute != null) break;
          }

          // Construir nombre corto priorizando: calle > barrio > sublocality > locality
          String shortName = '';
          if (bestRoute != null && bestRoute.isNotEmpty && !_isPlusCode(bestRoute)) {
            shortName = bestRoute;
            if (bestStreetNumber != null && bestStreetNumber.isNotEmpty && !_isPlusCode(bestStreetNumber)) {
              shortName = '$bestRoute $bestStreetNumber';
            }
          } else if (bestNeighborhood != null && bestNeighborhood.isNotEmpty && !_isPlusCode(bestNeighborhood)) {
            shortName = bestNeighborhood;
          } else if (bestSublocality != null && bestSublocality.isNotEmpty && !_isPlusCode(bestSublocality)) {
            shortName = bestSublocality;
          } else if (bestLocality != null && bestLocality.isNotEmpty) {
            shortName = bestLocality;
          } else {
            shortName = bestFormattedAddress ?? 'Ubicación actual';
          }

          // Dirección completa formateada (limpia de Plus Codes)
          String fullAddress = bestFormattedAddress ?? '';

          print('📍 Google Geocoding result (cleaned):');
          print('  route: $bestRoute');
          print('  streetNumber: $bestStreetNumber');
          print('  neighborhood: $bestNeighborhood');
          print('  sublocality: $bestSublocality');
          print('  locality: $bestLocality');
          print('  shortName: $shortName');
          print('  fullAddress: $fullAddress');

          return ReverseGeocodeResult(
            shortName: shortName,
            fullAddress: fullAddress,
            route: bestRoute,
            streetNumber: bestStreetNumber,
            sublocality: bestSublocality,
            locality: bestLocality,
          );
        } else {
          print('Geocoding API error: ${data['status']}');
          return null;
        }
      } else {
        print('HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error en reverse geocoding: $e');
      return null;
    }
  }

  /// Liberar recursos
  void dispose() {
    _places.dispose();
  }
}

/// Resultado del reverse geocoding
class ReverseGeocodeResult {
  final String shortName;
  final String fullAddress;
  final String? route;
  final String? streetNumber;
  final String? sublocality;
  final String? locality;

  ReverseGeocodeResult({
    required this.shortName,
    required this.fullAddress,
    this.route,
    this.streetNumber,
    this.sublocality,
    this.locality,
  });
}

/// Modelo para sugerencias de lugares
class PlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
}

/// Modelo para detalles de lugar
class PlaceDetails {
  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}
