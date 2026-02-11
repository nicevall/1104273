/// Modelo de datos extraídos de Licencia de Conducir (ANT Ecuador)
/// Campos extraídos mediante OCR de documento oficial
class LicenseData {
  final String? numeroLicencia; // 10 dígitos (cédula)
  final String? apellidos; // APELLIDO/FAMILY NAME
  final String? nombres; // NOMBRE/NAME
  final String? sexo; // M o F
  final String? fechaNacimiento; // DD-MM-YYYY
  final String? fechaVencimiento; // DD-MM-YYYY (CRÍTICO para validación)
  final String? categoria; // A, B, C, C1, D, E, etc.
  final String? tipoSangre; // O+, O-, A+, A-, B+, B-, AB+, AB-

  const LicenseData({
    this.numeroLicencia,
    this.apellidos,
    this.nombres,
    this.sexo,
    this.fechaNacimiento,
    this.fechaVencimiento,
    this.categoria,
    this.tipoSangre,
  });

  /// Crear desde Map (útil para JSON/Firestore)
  factory LicenseData.fromMap(Map<String, dynamic> map) {
    return LicenseData(
      numeroLicencia: map['numero_licencia'] as String?,
      apellidos: map['apellidos'] as String?,
      nombres: map['nombres'] as String?,
      sexo: map['sexo'] as String?,
      fechaNacimiento: map['fecha_nacimiento'] as String?,
      fechaVencimiento: map['fecha_vencimiento'] as String?,
      categoria: map['categoria'] as String?,
      tipoSangre: map['tipo_sangre'] as String?,
    );
  }

  /// Convertir a Map para Firestore
  Map<String, dynamic> toMap() {
    return {
      'numero_licencia': numeroLicencia,
      'apellidos': apellidos,
      'nombres': nombres,
      'sexo': sexo,
      'fecha_nacimiento': fechaNacimiento,
      'fecha_vencimiento': fechaVencimiento,
      'categoria': categoria,
      'tipo_sangre': tipoSangre,
    };
  }

  /// Verificar si tiene los campos mínimos requeridos
  bool get hasMinimumFields {
    return numeroLicencia != null &&
        numeroLicencia!.length == 10 &&
        categoria != null;
  }

  // TODO: Implementar validación de licencia vencida
  // bool get isExpired {
  //   if (fechaVencimiento == null) return true;
  //   final parts = fechaVencimiento!.split('-');
  //   if (parts.length != 3) return true;
  //   final expDate = DateTime(
  //     int.parse(parts[2]), // año
  //     int.parse(parts[1]), // mes
  //     int.parse(parts[0]), // día
  //   );
  //   return DateTime.now().isAfter(expDate);
  // }

  // TODO: Implementar validación de categoría B requerida para UniRide
  // bool get hasCategoryB {
  //   if (categoria == null) return false;
  //   return categoria!.toUpperCase().contains('B');
  // }

  @override
  String toString() {
    return 'LicenseData(numero: $numeroLicencia, nombres: $nombres, apellidos: $apellidos, cat: $categoria)';
  }
}
