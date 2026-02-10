// lib/data/services/taximeter_service.dart
// Servicio local de taxímetro — corre SOLO en el teléfono del conductor
// Maneja sesiones in-memory por cada pasajero a bordo
// NO accede a Firebase; solo calcula con GPS local

import 'dart:math';
import 'pricing_service.dart';

/// Sesión individual de taxímetro para un pasajero
class TaximeterSession {
  final String passengerId;
  final DateTime startTime;
  final double startLat;
  final double startLng;
  final bool isNightTariff;

  double totalDistanceKm;
  double totalWaitMinutes;
  double currentFare;
  String breakdown;

  /// Campos de descuento grupal
  int groupSize;              // Número actual de pasajeros en el carro
  double discountPercent;     // % descuento aplicado (0.08, 0.16, etc.)
  double fareBeforeDiscount;  // Tarifa sin descuento (para mostrar en UI)

  double _lastLat;
  double _lastLng;
  DateTime _lastUpdateTime;
  DateTime? lastFirestoreSync;

  TaximeterSession({
    required this.passengerId,
    required this.startTime,
    required this.startLat,
    required this.startLng,
    required this.isNightTariff,
    this.groupSize = 1,
  })  : totalDistanceKm = 0.0,
        totalWaitMinutes = 0.0,
        currentFare = isNightTariff
            ? PricingService.nightStartFare
            : PricingService.dayStartFare,
        fareBeforeDiscount = isNightTariff
            ? PricingService.nightStartFare
            : PricingService.dayStartFare,
        discountPercent = PricingService.getGroupDiscountPercent(1),
        breakdown = '',
        _lastLat = startLat,
        _lastLng = startLng,
        _lastUpdateTime = startTime;

  /// Tiempo transcurrido desde el inicio
  Duration get elapsed => DateTime.now().difference(startTime);

  /// Minutos transcurridos
  int get elapsedMinutes => elapsed.inMinutes;

  /// Formato mm:ss del tiempo transcurrido
  String get elapsedFormatted {
    final d = elapsed;
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Si necesita sincronizar a Firestore (>30 seg desde última sync)
  bool get needsFirestoreSync {
    if (lastFirestoreSync == null) return true;
    return DateTime.now().difference(lastFirestoreSync!).inSeconds >= 30;
  }

  /// Procesar una actualización GPS
  void processGpsUpdate(double lat, double lng, DateTime timestamp) {
    // Calcular distancia desde última posición (Haversine)
    final distanceKm = _haversineDistanceKm(_lastLat, _lastLng, lat, lng);

    // Calcular tiempo transcurrido desde última actualización
    final timeDeltaSeconds = timestamp.difference(_lastUpdateTime).inMilliseconds / 1000.0;

    if (timeDeltaSeconds <= 0) return;

    // Calcular velocidad en km/h
    final timeDeltaHours = timeDeltaSeconds / 3600.0;
    final speedKmh = timeDeltaHours > 0 ? distanceKm / timeDeltaHours : 0.0;

    // Si velocidad < 5 km/h → es espera (semáforo, tráfico, detenido)
    if (speedKmh < 5.0) {
      totalWaitMinutes += timeDeltaSeconds / 60.0;
    }

    // Acumular distancia (filtrar ruido GPS: ignorar si < 5 metros)
    if (distanceKm >= 0.005) {
      totalDistanceKm += distanceKm;
    }

    // Actualizar última posición
    _lastLat = lat;
    _lastLng = lng;
    _lastUpdateTime = timestamp;

    // Recalcular tarifa
    _recalculateFare();
  }

  /// Recalcular la tarifa actual con PricingService + descuento grupal
  void _recalculateFare() {
    final result = PricingService().calculateLiveFare(
      distanceKm: totalDistanceKm,
      waitMinutes: totalWaitMinutes,
      isNightRate: isNightTariff,
    );
    fareBeforeDiscount = result.price;
    discountPercent = PricingService.getGroupDiscountPercent(groupSize);
    currentFare = PricingService.applyGroupDiscount(result.price, groupSize);
    breakdown = result.breakdown;
  }

  /// Actualizar el tamaño del grupo (recalcula descuento)
  void updateGroupSize(int newSize) {
    if (newSize != groupSize) {
      groupSize = newSize;
      _recalculateFare();
    }
  }

  /// Distancia Haversine entre dos puntos en km
  static double _haversineDistanceKm(
    double lat1, double lon1, double lat2, double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180.0);
}

/// Servicio de taxímetro — gestiona múltiples sesiones simultáneas
///
/// Corre SOLO en el dispositivo del conductor.
/// Cada pasajero a bordo tiene su propia sesión con distancia y tiempo independientes.
class TaximeterService {
  final Map<String, TaximeterSession> _sessions = {};

  /// Intervalo mínimo entre sincronizaciones a Firestore
  static const Duration firestoreSyncInterval = Duration(seconds: 30);

  /// Iniciar un nuevo taxímetro para un pasajero
  TaximeterSession startMeter({
    required String passengerId,
    required double lat,
    required double lng,
    int groupSize = 1,
  }) {
    final isNight = PricingService().isNightTime();
    final session = TaximeterSession(
      passengerId: passengerId,
      startTime: DateTime.now(),
      startLat: lat,
      startLng: lng,
      isNightTariff: isNight,
      groupSize: groupSize,
    );
    _sessions[passengerId] = session;
    return session;
  }

  /// Restaurar un taxímetro desde datos de Firestore (tras reconexión/restart)
  /// Recrea la sesión con los datos acumulados que ya tenía
  TaximeterSession restoreMeter({
    required String passengerId,
    required DateTime startTime,
    required double startLat,
    required double startLng,
    required bool isNightTariff,
    double distanceKm = 0,
    double waitMinutes = 0,
    double fare = 0,
    required double currentLat,
    required double currentLng,
    int groupSize = 1,
  }) {
    final session = TaximeterSession(
      passengerId: passengerId,
      startTime: startTime,
      startLat: startLat,
      startLng: startLng,
      isNightTariff: isNightTariff,
      groupSize: groupSize,
    );
    // Restaurar acumulados
    session.totalDistanceKm = distanceKm;
    session.totalWaitMinutes = waitMinutes;
    session.currentFare = fare > 0 ? fare : session.currentFare;
    _sessions[passengerId] = session;
    return session;
  }

  /// Procesar actualización GPS para TODAS las sesiones activas
  ///
  /// [groupSize] = número de pasajeros picked_up (para descuento grupal)
  /// Retorna mapa de passengerId → sesión actualizada
  Map<String, TaximeterSession> onGpsUpdate(
    double lat, double lng, DateTime timestamp, {
    int groupSize = 1,
  }) {
    for (final session in _sessions.values) {
      session.updateGroupSize(groupSize);
      session.processGpsUpdate(lat, lng, timestamp);
    }
    return Map.unmodifiable(_sessions);
  }

  /// Detener taxímetro de un pasajero y retornar sesión final
  TaximeterSession? stopMeter(String passengerId) {
    return _sessions.remove(passengerId);
  }

  /// Obtener sesiones que necesitan sincronización a Firestore
  List<TaximeterSession> getSessionsNeedingSync() {
    return _sessions.values.where((s) => s.needsFirestoreSync).toList();
  }

  /// Marcar sesión como sincronizada
  void markSynced(String passengerId) {
    _sessions[passengerId]?.lastFirestoreSync = DateTime.now();
  }

  /// Obtener sesión de un pasajero específico
  TaximeterSession? getSession(String passengerId) {
    return _sessions[passengerId];
  }

  /// Todas las sesiones activas
  List<TaximeterSession> get activeSessions => _sessions.values.toList();

  /// Número de taxímetros corriendo
  int get activeCount => _sessions.length;

  /// Si hay al menos un taxímetro corriendo
  bool get hasActiveSessions => _sessions.isNotEmpty;

  /// Detener todos los taxímetros
  Map<String, TaximeterSession> stopAll() {
    final all = Map<String, TaximeterSession>.from(_sessions);
    _sessions.clear();
    return all;
  }

  /// Limpiar todo
  void dispose() {
    _sessions.clear();
  }
}
