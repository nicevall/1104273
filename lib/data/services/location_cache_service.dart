// lib/data/services/location_cache_service.dart
// Servicio singleton para cachear la ubicación GPS del usuario
// Se inicializa al detectar sesión activa para acelerar las pantallas que necesitan ubicación

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'google_places_service.dart';

/// Modelo simple para la ubicación cacheada
class CachedLocation {
  final double latitude;
  final double longitude;
  final String? shortName;
  final String? fullAddress;
  final DateTime cachedAt;

  CachedLocation({
    required this.latitude,
    required this.longitude,
    this.shortName,
    this.fullAddress,
    required this.cachedAt,
  });

  /// Si la ubicación fue cacheada hace menos de X minutos
  bool isFresh({int maxAgeMinutes = 5}) {
    return DateTime.now().difference(cachedAt).inMinutes < maxAgeMinutes;
  }

  /// Si la ubicación fue cacheada hace menos de X segundos
  bool isFreshSeconds({int maxAgeSeconds = 60}) {
    return DateTime.now().difference(cachedAt).inSeconds < maxAgeSeconds;
  }
}

/// Servicio singleton para cachear ubicación
class LocationCacheService {
  // Singleton
  static final LocationCacheService _instance = LocationCacheService._internal();
  factory LocationCacheService() => _instance;
  LocationCacheService._internal();

  // Ubicación cacheada
  CachedLocation? _cachedLocation;

  // Estado de carga
  bool _isLoading = false;
  String? _error;

  // Completer para esperar la carga inicial
  Completer<CachedLocation?>? _loadingCompleter;

  // Servicio de Places para reverse geocoding
  final _placesService = GooglePlacesService();

  // Getters
  CachedLocation? get cachedLocation => _cachedLocation;
  bool get isLoading => _isLoading;
  bool get hasLocation => _cachedLocation != null;
  String? get error => _error;

  /// Verifica si hay una ubicación fresca disponible
  bool get hasFreshLocation {
    return _cachedLocation != null && _cachedLocation!.isFresh();
  }

  /// Inicia la obtención de ubicación en background
  /// Llamar esto al detectar sesión activa (ej: en SplashScreen)
  Future<void> initializeLocation() async {
    // Si ya está cargando, esperar esa carga
    if (_isLoading && _loadingCompleter != null) {
      await _loadingCompleter!.future;
      return;
    }

    // Si ya tenemos ubicación fresca, no hacer nada
    if (hasFreshLocation) {
      return;
    }

    _isLoading = true;
    _error = null;
    _loadingCompleter = Completer<CachedLocation?>();

    try {
      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _error = 'Permiso de ubicación denegado';
        _isLoading = false;
        _loadingCompleter?.complete(null);
        return;
      }

      // Obtener posición
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      // Hacer reverse geocoding en paralelo
      String? shortName;
      String? fullAddress;

      try {
        final result = await _placesService.reverseGeocode(
          position.latitude,
          position.longitude,
        );
        if (result != null) {
          shortName = result.shortName;
          fullAddress = result.fullAddress;
        }
      } catch (_) {
        // Si falla el geocoding, igual guardamos las coordenadas
      }

      _cachedLocation = CachedLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        shortName: shortName ?? 'Mi ubicación',
        fullAddress: fullAddress ?? '${position.latitude}, ${position.longitude}',
        cachedAt: DateTime.now(),
      );

      _isLoading = false;
      _loadingCompleter?.complete(_cachedLocation);

    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _loadingCompleter?.complete(null);
    }
  }

  /// Obtiene la ubicación, esperando si está cargando
  /// Útil para pantallas que necesitan la ubicación inmediatamente
  Future<CachedLocation?> getLocation({bool forceRefresh = false}) async {
    // Si forzamos refresh o no hay ubicación fresca
    if (forceRefresh || !hasFreshLocation) {
      await initializeLocation();
    }

    // Si está cargando, esperar
    if (_isLoading && _loadingCompleter != null) {
      return await _loadingCompleter!.future;
    }

    return _cachedLocation;
  }

  /// Actualiza la ubicación con nuevos datos (por ejemplo, si el usuario se mueve)
  void updateLocation({
    required double latitude,
    required double longitude,
    String? shortName,
    String? fullAddress,
  }) {
    _cachedLocation = CachedLocation(
      latitude: latitude,
      longitude: longitude,
      shortName: shortName,
      fullAddress: fullAddress,
      cachedAt: DateTime.now(),
    );
  }

  /// Limpia el caché (llamar al cerrar sesión)
  void clear() {
    _cachedLocation = null;
    _error = null;
    _isLoading = false;
    _loadingCompleter = null;
  }

  /// Libera recursos
  void dispose() {
    _placesService.dispose();
  }
}
