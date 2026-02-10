// lib/data/services/pricing_service.dart
// Servicio de cálculo de tarifa inteligente basado en tarifas de taxi de Ecuador
// Usa la fórmula oficial de taxímetro con tarifas diurna y nocturna

/// Resultado del cálculo de tarifa
class FareResult {
  /// Precio calculado en USD
  final double price;

  /// Si es tarifa nocturna
  final bool isNightRate;

  /// Distancia en km usada para el cálculo
  final double distanceKm;

  /// Duración en minutos usada para el cálculo
  final int durationMinutes;

  /// Desglose de la tarifa
  final String breakdown;

  /// Nombre de la tarifa ("Diurna" o "Nocturna")
  final String tariffName;

  /// Horario de la tarifa
  final String tariffSchedule;

  const FareResult({
    required this.price,
    required this.isNightRate,
    required this.distanceKm,
    required this.durationMinutes,
    required this.breakdown,
    required this.tariffName,
    required this.tariffSchedule,
  });
}

/// Servicio de cálculo de precios basado en tarifas oficiales de taxi de Ecuador
///
/// Tarifas oficiales:
/// - Diurna (06:00 - 19:00): Mínimo $1.25, Arranque $0.40, $0.33/km, $0.07/min espera
/// - Nocturna (19:01 - 05:59): Mínimo $1.40, Arranque $0.50, $0.35/km, $0.08/min espera
class PricingService {
  // === TARIFA DIURNA (06:00 - 19:00) ===
  static const double dayMinimumFare = 1.25;
  static const double dayStartFare = 0.40;
  static const double dayPerKm = 0.33;
  static const double dayPerWaitMinute = 0.07;

  // === TARIFA NOCTURNA (19:01 - 05:59) ===
  static const double nightMinimumFare = 1.40;
  static const double nightStartFare = 0.50;
  static const double nightPerKm = 0.35;
  static const double nightPerWaitMinute = 0.08;

  // === DESCUENTO GRUPAL (carpooling) ===
  static const double groupDiscountPerPassenger = 0.08; // 8% por pasajero
  static const double maxGroupDiscount = 0.25;           // Tope 25%

  // === Horarios ===
  static const int dayStartHour = 6;   // 06:00
  static const int dayEndHour = 19;     // 19:00 (inclusive)

  /// Singleton
  static final PricingService _instance = PricingService._();
  factory PricingService() => _instance;
  PricingService._();

  /// Determina si una hora dada es tarifa nocturna
  bool isNightTime([DateTime? dateTime]) {
    final now = dateTime ?? DateTime.now();
    final hour = now.hour;
    // Nocturna: 19:01 - 05:59 → hour >= 19 || hour < 6
    return hour >= dayEndHour || hour < dayStartHour;
  }

  /// Calcula la tarifa basada en distancia, duración y hora
  ///
  /// [distanceKm] — distancia total del viaje en kilómetros
  /// [durationMinutes] — duración estimada en minutos
  /// [departureTime] — hora de salida (para determinar tarifa diurna/nocturna)
  ///
  /// Fórmula completa del taxímetro:
  /// Arranque + (distancia × tarifa/km) + (minutos × tarifa/min espera)
  ///
  /// Los minutos de espera simulan el tiempo en semáforos y tráfico
  /// que el taxímetro real cobra durante el viaje.
  FareResult calculateFare({
    required double distanceKm,
    required int durationMinutes,
    DateTime? departureTime,
  }) {
    final isNight = isNightTime(departureTime);

    final startFare = isNight ? nightStartFare : dayStartFare;
    final perKm = isNight ? nightPerKm : dayPerKm;
    final perWaitMin = isNight ? nightPerWaitMinute : dayPerWaitMinute;
    final minimumFare = isNight ? nightMinimumFare : dayMinimumFare;

    // Estimar minutos de espera (semáforos/tráfico)
    // Velocidad promedio sin tráfico ~30 km/h en ciudad
    // Tiempo puro de movimiento = distancia / 30 * 60 minutos
    // Tiempo de espera = duración total - tiempo de movimiento puro
    final double pureMovementMinutes = (distanceKm / 30.0) * 60.0;
    double waitMinutes = durationMinutes - pureMovementMinutes;
    if (waitMinutes < 0) waitMinutes = 0;

    // Fórmula: Arranque + (distancia × tarifa/km) + (min espera × tarifa/min)
    double calculatedPrice = startFare + (distanceKm * perKm) + (waitMinutes * perWaitMin);

    // Aplicar mínimo
    if (calculatedPrice < minimumFare) {
      calculatedPrice = minimumFare;
    }

    // Redondear a 2 decimales
    calculatedPrice = double.parse(calculatedPrice.toStringAsFixed(2));

    final tariffName = isNight ? 'Nocturna' : 'Diurna';
    final tariffSchedule = isNight ? '19:01 - 05:59' : '06:00 - 19:00';

    final waitMinutesRounded = waitMinutes.round();
    final String breakdown;
    if (isNight) {
      breakdown = 'Arranque \$${nightStartFare.toStringAsFixed(2)} + '
          '${distanceKm.toStringAsFixed(1)} km × \$${nightPerKm.toStringAsFixed(2)}'
          '${waitMinutesRounded > 0 ? ' + $waitMinutesRounded min × \$${nightPerWaitMinute.toStringAsFixed(2)}' : ''}';
    } else {
      breakdown = 'Arranque \$${dayStartFare.toStringAsFixed(2)} + '
          '${distanceKm.toStringAsFixed(1)} km × \$${dayPerKm.toStringAsFixed(2)}'
          '${waitMinutesRounded > 0 ? ' + $waitMinutesRounded min × \$${dayPerWaitMinute.toStringAsFixed(2)}' : ''}';
    }

    return FareResult(
      price: calculatedPrice,
      isNightRate: isNight,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      breakdown: breakdown,
      tariffName: tariffName,
      tariffSchedule: tariffSchedule,
    );
  }

  /// Calcula tarifa rápida solo con distancia en metros
  /// (para uso en pantallas donde ya tenemos distanceMeters del API)
  FareResult calculateFromMeters({
    required int distanceMeters,
    required int durationSeconds,
    DateTime? departureTime,
  }) {
    return calculateFare(
      distanceKm: distanceMeters / 1000.0,
      durationMinutes: (durationSeconds / 60).ceil(),
      departureTime: departureTime,
    );
  }

  /// Calcula tarifa en tiempo real desde datos GPS medidos
  ///
  /// A diferencia de [calculateFare], este método recibe distancia y espera
  /// **medidos realmente por GPS** del taxímetro, no estimados por la API.
  ///
  /// [distanceKm] — km acumulados por GPS (Haversine entre posiciones)
  /// [waitMinutes] — minutos reales donde velocidad < 5 km/h (semáforos/tráfico)
  /// [isNightRate] — tarifa fijada al momento del pickup (no cambia durante el viaje)
  FareResult calculateLiveFare({
    required double distanceKm,
    required double waitMinutes,
    required bool isNightRate,
  }) {
    final startFare = isNightRate ? nightStartFare : dayStartFare;
    final perKm = isNightRate ? nightPerKm : dayPerKm;
    final perWaitMin = isNightRate ? nightPerWaitMinute : dayPerWaitMinute;
    final minimumFare = isNightRate ? nightMinimumFare : dayMinimumFare;

    // Fórmula: Arranque + (distancia × tarifa/km) + (min espera × tarifa/min)
    double calculatedPrice = startFare + (distanceKm * perKm) + (waitMinutes * perWaitMin);

    // Aplicar mínimo
    if (calculatedPrice < minimumFare) {
      calculatedPrice = minimumFare;
    }

    // Redondear a 2 decimales
    calculatedPrice = double.parse(calculatedPrice.toStringAsFixed(2));

    final tariffName = isNightRate ? 'Nocturna' : 'Diurna';
    final tariffSchedule = isNightRate ? '19:01 - 05:59' : '06:00 - 19:00';

    final waitMinutesRounded = waitMinutes.round();
    final String breakdown;
    if (isNightRate) {
      breakdown = 'Arranque \$${nightStartFare.toStringAsFixed(2)} + '
          '${distanceKm.toStringAsFixed(1)} km × \$${nightPerKm.toStringAsFixed(2)}'
          '${waitMinutesRounded > 0 ? ' + $waitMinutesRounded min × \$${nightPerWaitMinute.toStringAsFixed(2)}' : ''}';
    } else {
      breakdown = 'Arranque \$${dayStartFare.toStringAsFixed(2)} + '
          '${distanceKm.toStringAsFixed(1)} km × \$${dayPerKm.toStringAsFixed(2)}'
          '${waitMinutesRounded > 0 ? ' + $waitMinutesRounded min × \$${dayPerWaitMinute.toStringAsFixed(2)}' : ''}';
    }

    return FareResult(
      price: calculatedPrice,
      isNightRate: isNightRate,
      distanceKm: distanceKm,
      durationMinutes: waitMinutesRounded,
      breakdown: breakdown,
      tariffName: tariffName,
      tariffSchedule: tariffSchedule,
    );
  }

  /// Obtiene un texto descriptivo de la tarifa actual
  String getCurrentRateDescription() {
    final isNight = isNightTime();
    if (isNight) {
      return 'Tarifa nocturna (19:01 - 05:59)';
    }
    return 'Tarifa diurna (06:00 - 19:00)';
  }

  /// Obtiene el precio mínimo según la hora actual
  double getCurrentMinimumFare() {
    return isNightTime() ? nightMinimumFare : dayMinimumFare;
  }

  // ============================================================
  // DESCUENTO GRUPAL
  // ============================================================

  /// Calcular porcentaje de descuento grupal
  /// [passengerCount] = número de pasajeros picked_up en el carro
  static double getGroupDiscountPercent(int passengerCount) {
    if (passengerCount <= 0) return 0.0;
    final discount = passengerCount * groupDiscountPerPassenger;
    return discount.clamp(0.0, maxGroupDiscount);
  }

  /// Aplicar descuento grupal a una tarifa
  /// Retorna la tarifa con descuento (sobre el total final, después del mínimo)
  static double applyGroupDiscount(double fare, int passengerCount) {
    final discountPercent = getGroupDiscountPercent(passengerCount);
    return double.parse((fare * (1.0 - discountPercent)).toStringAsFixed(2));
  }

  /// Redondear al alza al múltiplo de $0.05 más cercano (para pago en efectivo)
  /// En Ecuador nadie maneja monedas de 1 centavo
  /// Ej: $1.52 → $1.55, $1.50 → $1.50, $1.41 → $1.45
  static double roundUpToNickel(double fare) {
    return (fare * 20).ceil() / 20.0;
  }
}
