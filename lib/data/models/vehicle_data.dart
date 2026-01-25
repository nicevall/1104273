/// Modelo de datos extraídos de Matrícula Vehicular (ANT Ecuador)
/// Campos extraídos mediante OCR de documento oficial
class VehicleData {
  final String? placa;              // ABC1234 o ABC-1234 (3 letras + 3-4 números)
  final String? marca;              // TOYOTA, CHEVROLET, etc.
  final String? modelo;             // Descripción del modelo
  final String? anio;               // Año de fabricación (1990-2026)
  final String? color;              // COLOR principal
  final String? vinChasis;          // 17 caracteres alfanuméricos
  final String? claseVehiculo;      // AUTOMOVIL, CAMIONETA, etc.
  final String? pasajeros;          // Capacidad de pasajeros

  const VehicleData({
    this.placa,
    this.marca,
    this.modelo,
    this.anio,
    this.color,
    this.vinChasis,
    this.claseVehiculo,
    this.pasajeros,
  });

  /// Crear desde Map (útil para JSON/Firestore)
  factory VehicleData.fromMap(Map<String, dynamic> map) {
    return VehicleData(
      placa: map['placa'] as String?,
      marca: map['marca'] as String?,
      modelo: map['modelo'] as String?,
      anio: map['anio'] as String? ?? map['año'] as String?,
      color: map['color'] as String?,
      vinChasis: map['vin_chasis'] as String?,
      claseVehiculo: map['clase_vehiculo'] as String?,
      pasajeros: map['pasajeros'] as String?,
    );
  }

  /// Crear desde Map<String, String> (compatibilidad con flujo actual)
  factory VehicleData.fromStringMap(Map<String, String> map) {
    return VehicleData(
      placa: map['placa'],
      marca: map['marca'],
      modelo: map['modelo'],
      anio: map['año'] ?? map['anio'],
      color: map['color'],
      vinChasis: map['vin_chasis'],
      claseVehiculo: map['clase_vehiculo'],
      pasajeros: map['pasajeros'],
    );
  }

  /// Convertir a Map para Firestore
  Map<String, dynamic> toMap() {
    return {
      'placa': placa,
      'marca': marca,
      'modelo': modelo,
      'anio': anio,
      'color': color,
      'vin_chasis': vinChasis,
      'clase_vehiculo': claseVehiculo,
      'pasajeros': pasajeros,
    };
  }

  /// Convertir a Map<String, String> (compatibilidad con flujo actual)
  Map<String, String> toStringMap() {
    final map = <String, String>{};
    if (placa != null) map['placa'] = placa!;
    if (marca != null) map['marca'] = marca!;
    if (modelo != null) map['modelo'] = modelo!;
    if (anio != null) map['año'] = anio!;
    if (color != null) map['color'] = color!;
    if (vinChasis != null) map['vin_chasis'] = vinChasis!;
    if (claseVehiculo != null) map['clase_vehiculo'] = claseVehiculo!;
    if (pasajeros != null) map['pasajeros'] = pasajeros!;
    return map;
  }

  /// Verificar si tiene los campos mínimos requeridos
  bool get hasMinimumFields {
    return placa != null && marca != null;
  }

  // TODO: Implementar validación de formato de placa ecuatoriana
  // bool get isValidPlate {
  //   if (placa == null) return false;
  //   final cleanPlate = placa!.replaceAll('-', '').toUpperCase();
  //   // Formato: 3 letras + 3-4 números
  //   final plateRegex = RegExp(r'^[A-Z]{3}\d{3,4}$');
  //   return plateRegex.hasMatch(cleanPlate);
  // }

  // TODO: Implementar validación de VIN/Chasis
  // bool get isValidVin {
  //   if (vinChasis == null) return false;
  //   return vinChasis!.length == 17;
  // }

  // TODO: Implementar validación de año dentro de rango
  // bool get isValidYear {
  //   if (anio == null) return false;
  //   final year = int.tryParse(anio!);
  //   if (year == null) return false;
  //   final currentYear = DateTime.now().year;
  //   return year >= 1990 && year <= currentYear + 1;
  // }

  // TODO: Implementar validación de clase de vehículo permitida
  // static const allowedClasses = ['AUTOMOVIL', 'CAMIONETA', 'JEEP', 'SUV'];
  // bool get isAllowedClass {
  //   if (claseVehiculo == null) return true; // No bloquear si no se detectó
  //   return allowedClasses.contains(claseVehiculo!.toUpperCase());
  // }

  @override
  String toString() {
    return 'VehicleData(placa: $placa, marca: $marca, modelo: $modelo, año: $anio, color: $color)';
  }
}
