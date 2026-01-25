import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import '../models/license_data.dart';
import '../models/vehicle_data.dart';

/// Resultado de la verificación de documento
class DocumentVerificationResult {
  final bool isValid;
  final bool hasText;
  final bool isPotentialScreenPhoto;
  final String? extractedText;
  final List<String> detectedKeywords;
  final String? errorMessage;
  final double confidenceScore;
  final LicenseData? licenseData;
  final VehicleData? vehicleData;

  const DocumentVerificationResult({
    required this.isValid,
    required this.hasText,
    required this.isPotentialScreenPhoto,
    this.extractedText,
    this.detectedKeywords = const [],
    this.errorMessage,
    this.confidenceScore = 0.0,
    this.licenseData,
    this.vehicleData,
  });

  factory DocumentVerificationResult.invalid(String error) {
    return DocumentVerificationResult(
      isValid: false,
      hasText: false,
      isPotentialScreenPhoto: false,
      errorMessage: error,
    );
  }
}

/// Tipo de documento a verificar
enum DocumentType {
  license,      // Licencia de conducir
  registration, // Matrícula vehicular
  vehicle,      // Foto del vehículo (sin OCR, solo anti-spoofing)
}

/// Servicio de verificación de documentos usando ML Kit
/// Implementa OCR y detección básica de anti-spoofing
/// Especializado en documentos ANT Ecuador
class DocumentVerificationService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  // Palabras clave para licencia de conducir ecuatoriana
  static const List<String> _licenseKeywords = [
    'licencia',
    'conducir',
    'ant',
    'tipo',
    'categoria',
    'ecuador',
    'cedula',
    'nombre',
    'apellido',
    'fecha',
    'nacimiento',
    'expedicion',
    'caducidad',
    'vigencia',
    'conducción',
    'transito',
    'agencia nacional',
    'driver',
    'license',
    'republic',
  ];

  // Palabras clave para matrícula vehicular ecuatoriana
  static const List<String> _registrationKeywords = [
    'matricula',
    'placa',
    'vehiculo',
    'marca',
    'modelo',
    'ano',
    'año',
    'color',
    'motor',
    'chasis',
    'cilindraje',
    'propietario',
    'ecuador',
    'ant',
    'revision',
    'técnica',
    'servicio',
    'vin',
    'clase',
    'pasajeros',
  ];

  // Marcas de vehículos conocidas
  static const List<String> _knownBrands = [
    'chevrolet', 'toyota', 'nissan', 'hyundai', 'kia', 'mazda', 'ford',
    'honda', 'volkswagen', 'suzuki', 'renault', 'peugeot', 'mitsubishi',
    'great wall', 'jac', 'chery', 'byd', 'fiat', 'jeep', 'dodge', 'ram',
    'subaru', 'volvo', 'bmw', 'mercedes', 'audi', 'lexus', 'infiniti',
    'land rover', 'mini', 'porsche', 'ferrari', 'hino', 'isuzu', 'dfsk',
    'changhe', 'zotye', 'haval', 'mg', 'geely', 'changan', 'foton',
  ];

  // Colores conocidos
  static const Map<String, String> _knownColors = {
    'blanco': 'BLANCO',
    'negro': 'NEGRO',
    'gris': 'GRIS',
    'plata': 'PLATEADO',
    'plateado': 'PLATEADO',
    'rojo': 'ROJO',
    'azul': 'AZUL',
    'verde': 'VERDE',
    'amarillo': 'AMARILLO',
    'naranja': 'NARANJA',
    'cafe': 'CAFÉ',
    'café': 'CAFÉ',
    'beige': 'BEIGE',
    'dorado': 'DORADO',
    'vino': 'VINO',
    'morado': 'MORADO',
    'celeste': 'CELESTE',
    'crema': 'CREMA',
  };

  // Clases de vehículos
  static const List<String> _vehicleClasses = [
    'automovil', 'camioneta', 'motocicleta', 'jeep', 'furgoneta',
    'bus', 'camion', 'camión', 'suv', 'sedan', 'hatchback', 'pickup',
  ];

  // Tipos de sangre válidos
  static const List<String> _bloodTypes = [
    'O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-',
    'O RH+', 'O RH-', 'A RH+', 'A RH-', 'B RH+', 'B RH-',
  ];

  /// Verificar un documento
  /// Retorna un resultado con información sobre la validez
  Future<DocumentVerificationResult> verifyDocument({
    required File imageFile,
    required DocumentType documentType,
  }) async {
    try {
      // Para fotos de vehículo, solo verificar anti-spoofing
      if (documentType == DocumentType.vehicle) {
        final isSpoofed = await _detectScreenPhoto(imageFile);
        return DocumentVerificationResult(
          isValid: !isSpoofed,
          hasText: false,
          isPotentialScreenPhoto: isSpoofed,
          confidenceScore: isSpoofed ? 0.3 : 0.9,
          errorMessage: isSpoofed
              ? 'La imagen parece ser una foto de otra pantalla. Por favor, toma una foto directa del vehículo.'
              : null,
        );
      }

      // Para documentos, verificar OCR y anti-spoofing
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final extractedText = recognizedText.text;
      final textLower = extractedText.toLowerCase();
      final hasText = extractedText.isNotEmpty && extractedText.length > 20;

      if (!hasText) {
        return DocumentVerificationResult.invalid(
          'No se detectó texto en la imagen. Asegúrate de que el documento sea legible y esté bien iluminado.',
        );
      }

      // Verificar palabras clave según tipo de documento
      final keywords = documentType == DocumentType.license
          ? _licenseKeywords
          : _registrationKeywords;

      final detectedKeywords = <String>[];
      for (final keyword in keywords) {
        if (textLower.contains(keyword)) {
          detectedKeywords.add(keyword);
        }
      }

      // Calcular score de confianza basado en palabras clave detectadas
      final keywordScore = detectedKeywords.length / keywords.length;

      // Verificar anti-spoofing
      final isPotentialScreenPhoto = await _detectScreenPhoto(imageFile);

      // El documento es válido si:
      // 1. Tiene suficientes palabras clave (al menos 3)
      // 2. No parece ser una foto de pantalla
      final isValid = detectedKeywords.length >= 3 && !isPotentialScreenPhoto;

      // Calcular confianza final
      double confidenceScore = keywordScore * 0.7;
      if (!isPotentialScreenPhoto) {
        confidenceScore += 0.3;
      }

      String? errorMessage;
      if (isPotentialScreenPhoto) {
        errorMessage = 'La imagen parece ser una foto de otra pantalla. Por favor, toma una foto directa del documento físico.';
      } else if (detectedKeywords.length < 3) {
        final docName = documentType == DocumentType.license
            ? 'licencia de conducir'
            : 'matrícula vehicular';
        errorMessage = 'No se detectaron suficientes características de una $docName válida. Asegúrate de fotografiar el documento correcto.';
      }

      // Extraer datos específicos según tipo de documento
      LicenseData? licenseData;
      VehicleData? vehicleData;

      if (isValid) {
        if (documentType == DocumentType.license) {
          licenseData = _extractLicenseData(extractedText);
        } else if (documentType == DocumentType.registration) {
          vehicleData = _extractVehicleData(extractedText);
        }
      }

      return DocumentVerificationResult(
        isValid: isValid,
        hasText: hasText,
        isPotentialScreenPhoto: isPotentialScreenPhoto,
        extractedText: extractedText,
        detectedKeywords: detectedKeywords,
        errorMessage: errorMessage,
        confidenceScore: confidenceScore.clamp(0.0, 1.0),
        licenseData: licenseData,
        vehicleData: vehicleData,
      );
    } catch (e) {
      debugPrint('Error en verificación de documento: $e');
      return DocumentVerificationResult.invalid(
        'Error al procesar la imagen. Por favor, intenta de nuevo.',
      );
    }
  }

  /// Extraer datos de Licencia de Conducir ANT Ecuador
  LicenseData _extractLicenseData(String text) {
    final textUpper = text.toUpperCase();
    final textClean = text.replaceAll('\n', ' ').replaceAll('  ', ' ');

    // Extraer número de licencia (10 dígitos - cédula ecuatoriana)
    String? numeroLicencia;
    final licenseRegex = RegExp(r'\b\d{10}\b');
    final licenseMatch = licenseRegex.firstMatch(text);
    if (licenseMatch != null) {
      numeroLicencia = licenseMatch.group(0);
    }

    // Extraer apellidos (después de APELLIDO/FAMILY NAME/APELLIDOS)
    String? apellidos;
    final apellidoPatterns = [
      RegExp(r'APELLIDOS?\s*[:\-]?\s*([A-ZÁÉÍÓÚÑ\s]+)', caseSensitive: false),
      RegExp(r'FAMILY\s*NAME\s*[:\-]?\s*([A-ZÁÉÍÓÚÑ\s]+)', caseSensitive: false),
    ];
    for (final pattern in apellidoPatterns) {
      final match = pattern.firstMatch(textUpper);
      if (match != null && match.group(1) != null) {
        apellidos = match.group(1)!.trim();
        // Limpiar y tomar solo las primeras palabras en mayúscula
        apellidos = _cleanName(apellidos);
        if (apellidos.isNotEmpty) break;
      }
    }

    // Extraer nombres (después de NOMBRE/NAME/NOMBRES)
    String? nombres;
    final nombrePatterns = [
      RegExp(r'NOMBRES?\s*[:\-]?\s*([A-ZÁÉÍÓÚÑ\s]+)', caseSensitive: false),
      RegExp(r'\bNAME\s*[:\-]?\s*([A-ZÁÉÍÓÚÑ\s]+)', caseSensitive: false),
    ];
    for (final pattern in nombrePatterns) {
      final match = pattern.firstMatch(textUpper);
      if (match != null && match.group(1) != null) {
        nombres = match.group(1)!.trim();
        nombres = _cleanName(nombres);
        if (nombres.isNotEmpty) break;
      }
    }

    // Extraer sexo (M o F)
    String? sexo;
    final sexoPatterns = [
      RegExp(r'SEXO\s*[:\-]?\s*([MF])\b', caseSensitive: false),
      RegExp(r'SEX\s*[:\-]?\s*([MF])\b', caseSensitive: false),
      RegExp(r'\b([MF])\s*(MASCULINO|FEMENINO|MALE|FEMALE)', caseSensitive: false),
    ];
    for (final pattern in sexoPatterns) {
      final match = pattern.firstMatch(textUpper);
      if (match != null && match.group(1) != null) {
        sexo = match.group(1)!.toUpperCase();
        break;
      }
    }

    // Extraer fecha de nacimiento
    String? fechaNacimiento;
    final fechaNacPatterns = [
      RegExp(r'NACIMIENTO\s*[:\-]?\s*(\d{1,2}[\-/]\d{1,2}[\-/]\d{4})', caseSensitive: false),
      RegExp(r'DOB\s*[:\-]?\s*(\d{1,2}[\-/]\d{1,2}[\-/]\d{4})', caseSensitive: false),
      RegExp(r'BIRTH\s*[:\-]?\s*(\d{1,2}[\-/]\d{1,2}[\-/]\d{4})', caseSensitive: false),
    ];
    for (final pattern in fechaNacPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        fechaNacimiento = _normalizeDate(match.group(1)!);
        break;
      }
    }

    // Extraer fecha de vencimiento (CRÍTICO)
    String? fechaVencimiento;
    final fechaVencPatterns = [
      RegExp(r'VENCIMIENTO\s*[:\-]?\s*(\d{1,2}[\-/]\d{1,2}[\-/]\d{4})', caseSensitive: false),
      RegExp(r'CADUCIDAD\s*[:\-]?\s*(\d{1,2}[\-/]\d{1,2}[\-/]\d{4})', caseSensitive: false),
      RegExp(r'EXP(?:IRY|IRATION)?\s*[:\-]?\s*(\d{1,2}[\-/]\d{1,2}[\-/]\d{4})', caseSensitive: false),
      RegExp(r'VIGENCIA\s*[:\-]?\s*(\d{1,2}[\-/]\d{1,2}[\-/]\d{4})', caseSensitive: false),
    ];
    for (final pattern in fechaVencPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        fechaVencimiento = _normalizeDate(match.group(1)!);
        break;
      }
    }

    // Extraer categoría (A, B, C, C1, D, E, etc.)
    String? categoria;
    final categoriaPatterns = [
      RegExp(r'CATEGOR[IÍ]A\s*[:\-]?\s*([A-E][1-2]?\s*)+', caseSensitive: false),
      RegExp(r'CATEGORY\s*[:\-]?\s*([A-E][1-2]?\s*)+', caseSensitive: false),
      RegExp(r'TIPO\s*[:\-]?\s*([A-E][1-2]?\s*)+', caseSensitive: false),
      RegExp(r'\b((?:[ABCDE][1-2]?\s*)+)\s*(?:NO\s*PROFESIONAL|PROFESIONAL)?', caseSensitive: false),
    ];
    for (final pattern in categoriaPatterns) {
      final match = pattern.firstMatch(textUpper);
      if (match != null && match.group(1) != null) {
        categoria = match.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (categoria.isNotEmpty) break;
      }
    }

    // Extraer tipo de sangre
    String? tipoSangre;
    for (final bt in _bloodTypes) {
      if (textUpper.contains(bt.replaceAll(' ', ''))) {
        tipoSangre = bt.replaceAll(' RH', '');
        break;
      }
    }
    // Buscar patrón alternativo
    if (tipoSangre == null) {
      final btPattern = RegExp(r'\b(AB?|O)\s*RH?\s*([+-])', caseSensitive: false);
      final btMatch = btPattern.firstMatch(textUpper);
      if (btMatch != null) {
        tipoSangre = '${btMatch.group(1)}${btMatch.group(2)}';
      }
    }

    return LicenseData(
      numeroLicencia: numeroLicencia,
      apellidos: apellidos,
      nombres: nombres,
      sexo: sexo,
      fechaNacimiento: fechaNacimiento,
      fechaVencimiento: fechaVencimiento,
      categoria: categoria,
      tipoSangre: tipoSangre,
    );
  }

  /// Extraer datos de Matrícula Vehicular ANT Ecuador
  VehicleData _extractVehicleData(String text) {
    final textUpper = text.toUpperCase();
    final textLower = text.toLowerCase();

    // Extraer placa (formato ecuatoriano: ABC-1234 o ABC1234)
    String? placa;
    final placaRegex = RegExp(r'\b([A-Z]{3})[\s\-]?(\d{3,4})\b', caseSensitive: false);
    final placaMatch = placaRegex.firstMatch(textUpper);
    if (placaMatch != null) {
      placa = '${placaMatch.group(1)}${placaMatch.group(2)}';
    }

    // Extraer marca
    String? marca;
    for (final brand in _knownBrands) {
      if (textLower.contains(brand)) {
        marca = brand.toUpperCase();
        // Capitalizar primera letra
        marca = marca[0] + marca.substring(1).toLowerCase();
        // Casos especiales
        if (brand == 'great wall') marca = 'Great Wall';
        if (brand == 'land rover') marca = 'Land Rover';
        break;
      }
    }
    // Buscar después de la palabra MARCA
    if (marca == null) {
      final marcaPattern = RegExp(r'MARCA\s*[:\-]?\s*([A-ZÁÉÍÓÚÑ\s]+)', caseSensitive: false);
      final marcaMatch = marcaPattern.firstMatch(textUpper);
      if (marcaMatch != null) {
        marca = marcaMatch.group(1)!.trim().split(RegExp(r'\s+'))[0];
      }
    }

    // Extraer modelo (después de MODELO)
    String? modelo;
    final modeloPatterns = [
      RegExp(r'MODELO\s*[:\-]?\s*([A-Z0-9\s\.\-]+)', caseSensitive: false),
    ];
    for (final pattern in modeloPatterns) {
      final match = pattern.firstMatch(textUpper);
      if (match != null && match.group(1) != null) {
        modelo = match.group(1)!.trim();
        // Limpiar modelo - tomar hasta la siguiente palabra clave
        final endIndex = modelo.indexOf(RegExp(r'\b(AÑO|COLOR|CLASE|MOTOR|CHASIS)\b'));
        if (endIndex > 0) {
          modelo = modelo.substring(0, endIndex).trim();
        }
        if (modelo.isNotEmpty) break;
      }
    }

    // Extraer año
    String? anio;
    final anioPatterns = [
      RegExp(r'A[ÑN]O\s*[:\-]?\s*(19\d{2}|20[0-2]\d)', caseSensitive: false),
      RegExp(r'YEAR\s*[:\-]?\s*(19\d{2}|20[0-2]\d)', caseSensitive: false),
      RegExp(r'\b(19\d{2}|20[0-2]\d)\b'),
    ];
    for (final pattern in anioPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final year = match.group(1) ?? match.group(0);
        final yearInt = int.tryParse(year ?? '');
        if (yearInt != null && yearInt >= 1990 && yearInt <= 2026) {
          anio = year;
          break;
        }
      }
    }

    // Extraer color
    String? color;
    // Primero buscar después de COLOR o COLOR 1
    final colorPatterns = [
      RegExp(r'COLOR\s*1?\s*[:\-]?\s*([A-ZÁÉÍÓÚÑ]+)', caseSensitive: false),
    ];
    for (final pattern in colorPatterns) {
      final match = pattern.firstMatch(textUpper);
      if (match != null && match.group(1) != null) {
        final colorCandidate = match.group(1)!.toLowerCase();
        if (_knownColors.containsKey(colorCandidate)) {
          color = _knownColors[colorCandidate];
          break;
        }
      }
    }
    // Si no encontró, buscar cualquier color conocido
    if (color == null) {
      for (final entry in _knownColors.entries) {
        if (textLower.contains(entry.key)) {
          color = entry.value;
          break;
        }
      }
    }

    // Extraer VIN/Chasis (17 caracteres alfanuméricos)
    String? vinChasis;
    final vinPatterns = [
      RegExp(r'(?:VIN|CHASIS|CHASSIS)\s*[:\-]?\s*([A-Z0-9]{17})\b', caseSensitive: false),
      RegExp(r'\b([A-HJ-NPR-Z0-9]{17})\b'), // VIN no incluye I, O, Q
    ];
    for (final pattern in vinPatterns) {
      final match = pattern.firstMatch(textUpper);
      if (match != null) {
        final vin = match.group(1);
        if (vin != null && vin.length == 17) {
          vinChasis = vin;
          break;
        }
      }
    }

    // Extraer clase de vehículo
    String? claseVehiculo;
    final clasePatterns = [
      RegExp(r'CLASE\s*[:\-]?\s*([A-ZÁÉÍÓÚÑ]+)', caseSensitive: false),
    ];
    for (final pattern in clasePatterns) {
      final match = pattern.firstMatch(textUpper);
      if (match != null && match.group(1) != null) {
        claseVehiculo = match.group(1)!.trim();
        break;
      }
    }
    // Buscar clases conocidas
    if (claseVehiculo == null) {
      for (final vc in _vehicleClasses) {
        if (textLower.contains(vc)) {
          claseVehiculo = vc.toUpperCase();
          break;
        }
      }
    }

    // Extraer número de pasajeros
    String? pasajeros;
    final pasajerosPatterns = [
      RegExp(r'PASAJEROS?\s*[:\-]?\s*(\d+)', caseSensitive: false),
      RegExp(r'CAPACIDAD\s*[:\-]?\s*(\d+)', caseSensitive: false),
    ];
    for (final pattern in pasajerosPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        pasajeros = match.group(1);
        break;
      }
    }

    return VehicleData(
      placa: placa,
      marca: marca,
      modelo: modelo,
      anio: anio,
      color: color,
      vinChasis: vinChasis,
      claseVehiculo: claseVehiculo,
      pasajeros: pasajeros,
    );
  }

  /// Limpiar nombre extraído (quitar palabras extra)
  String _cleanName(String name) {
    // Quitar palabras comunes que no son parte del nombre
    final stopWords = ['NOMBRE', 'NAME', 'APELLIDO', 'FAMILY', 'LICENCIA', 'CONDUCIR', 'ECUADOR'];
    var cleaned = name;
    for (final word in stopWords) {
      cleaned = cleaned.replaceAll(word, '');
    }
    cleaned = cleaned.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Tomar solo las primeras 3-4 palabras
    final words = cleaned.split(' ').where((w) => w.isNotEmpty).take(4).toList();
    return words.join(' ');
  }

  /// Normalizar fecha a formato DD-MM-YYYY
  String _normalizeDate(String date) {
    // Reemplazar / por -
    var normalized = date.replaceAll('/', '-');
    // Asegurar formato DD-MM-YYYY
    final parts = normalized.split('-');
    if (parts.length == 3) {
      final day = parts[0].padLeft(2, '0');
      final month = parts[1].padLeft(2, '0');
      final year = parts[2];
      return '$day-$month-$year';
    }
    return normalized;
  }

  /// Detectar si la imagen es una foto de otra pantalla
  /// Usa análisis de patrones de moiré y distribución de colores
  Future<bool> _detectScreenPhoto(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) return false;

      // Redimensionar para análisis más rápido
      final resized = img.copyResize(image, width: 200);

      // 1. Detectar patrones de moiré (líneas repetitivas de pantalla)
      final hasMoirePattern = _detectMoirePattern(resized);

      // 2. Analizar distribución de brillo (pantallas tienen brillo más uniforme)
      final hasUniformBrightness = _analyzeUniformBrightness(resized);

      // 3. Detectar bordes de pantalla (rectángulos brillantes)
      final hasScreenEdges = _detectScreenEdges(resized);

      // Si 2 o más indicadores son positivos, probablemente es foto de pantalla
      int spoofIndicators = 0;
      if (hasMoirePattern) spoofIndicators++;
      if (hasUniformBrightness) spoofIndicators++;
      if (hasScreenEdges) spoofIndicators++;

      return spoofIndicators >= 2;
    } catch (e) {
      debugPrint('Error en detección anti-spoofing: $e');
      // En caso de error, no bloquear al usuario
      return false;
    }
  }

  /// Detectar patrones de moiré (líneas de pantalla)
  bool _detectMoirePattern(img.Image image) {
    int periodicChanges = 0;
    final width = image.width;
    final height = image.height;

    for (int y = 0; y < height; y += 10) {
      List<int> intensities = [];
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final intensity = (pixel.r + pixel.g + pixel.b) ~/ 3;
        intensities.add(intensity.toInt());
      }

      for (int i = 2; i < intensities.length - 2; i++) {
        final diff1 = (intensities[i] - intensities[i-2]).abs();
        final diff2 = (intensities[i+2] - intensities[i]).abs();
        if (diff1 > 20 && diff2 > 20 && (diff1 - diff2).abs() < 10) {
          periodicChanges++;
        }
      }
    }

    final threshold = (width * height / 100) * 0.3;
    return periodicChanges > threshold;
  }

  /// Analizar si el brillo es demasiado uniforme (característica de pantallas)
  bool _analyzeUniformBrightness(img.Image image) {
    List<int> brightnesses = [];

    final regionSize = 20;
    for (int y = 0; y < image.height; y += regionSize) {
      for (int x = 0; x < image.width; x += regionSize) {
        int regionBrightness = 0;
        int count = 0;

        for (int dy = 0; dy < regionSize && y + dy < image.height; dy++) {
          for (int dx = 0; dx < regionSize && x + dx < image.width; dx++) {
            final pixel = image.getPixel(x + dx, y + dy);
            regionBrightness += ((pixel.r + pixel.g + pixel.b) / 3).toInt();
            count++;
          }
        }

        if (count > 0) {
          brightnesses.add(regionBrightness ~/ count);
        }
      }
    }

    if (brightnesses.isEmpty) return false;

    final mean = brightnesses.reduce((a, b) => a + b) / brightnesses.length;
    final variance = brightnesses.map((b) => pow(b - mean, 2)).reduce((a, b) => a + b) / brightnesses.length;
    final stdDev = sqrt(variance);

    return stdDev < 25 && mean > 150;
  }

  /// Detectar bordes rectangulares brillantes (borde de pantalla)
  bool _detectScreenEdges(img.Image image) {
    final width = image.width;
    final height = image.height;

    int brightEdgePixels = 0;
    int totalEdgePixels = 0;

    for (int x = 0; x < width; x++) {
      for (int y in [0, 1, 2, height - 3, height - 2, height - 1]) {
        if (y >= 0 && y < height) {
          final pixel = image.getPixel(x, y);
          final brightness = (pixel.r + pixel.g + pixel.b) ~/ 3;
          if (brightness > 200) brightEdgePixels++;
          totalEdgePixels++;
        }
      }
    }

    for (int y = 0; y < height; y++) {
      for (int x in [0, 1, 2, width - 3, width - 2, width - 1]) {
        if (x >= 0 && x < width) {
          final pixel = image.getPixel(x, y);
          final brightness = (pixel.r + pixel.g + pixel.b) ~/ 3;
          if (brightness > 200) brightEdgePixels++;
          totalEdgePixels++;
        }
      }
    }

    return totalEdgePixels > 0 && (brightEdgePixels / totalEdgePixels) > 0.4;
  }

  /// Verificar si la imagen es una foto directa (no de pantalla)
  /// Retorna true si es una foto real, false si parece ser foto de pantalla
  Future<bool> detectPhotoOfPhoto(File imageFile) async {
    final isSpoofed = await _detectScreenPhoto(imageFile);
    return !isSpoofed;
  }

  /// Extraer número de placa de la imagen (si es visible)
  Future<String?> extractPlateNumber(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final plateRegex = RegExp(r'[A-Z]{3}[-\s]?\d{3,4}', caseSensitive: false);
      final match = plateRegex.firstMatch(recognizedText.text.toUpperCase());

      return match?.group(0)?.replaceAll(' ', '').replaceAll('-', '');
    } catch (e) {
      debugPrint('Error extrayendo número de placa: $e');
      return null;
    }
  }

  /// Extraer número de licencia de la imagen
  Future<String?> extractLicenseNumber(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final licenseRegex = RegExp(r'\d{10}');
      final match = licenseRegex.firstMatch(recognizedText.text);

      return match?.group(0);
    } catch (e) {
      debugPrint('Error extrayendo número de licencia: $e');
      return null;
    }
  }

  /// Extraer todos los datos de licencia de la imagen
  Future<LicenseData?> extractFullLicenseData(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) return null;

      return _extractLicenseData(recognizedText.text);
    } catch (e) {
      debugPrint('Error extrayendo datos de licencia: $e');
      return null;
    }
  }

  /// Extraer todos los datos de matrícula de la imagen
  Future<VehicleData?> extractFullVehicleData(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) return null;

      return _extractVehicleData(recognizedText.text);
    } catch (e) {
      debugPrint('Error extrayendo datos de vehículo: $e');
      return null;
    }
  }

  /// Liberar recursos
  void dispose() {
    _textRecognizer.close();
  }
}

// TODO: VALIDACIONES PENDIENTES DE IMPLEMENTAR
// ============================================
//
// 1. VALIDACIÓN DE LICENCIA VENCIDA
//    - Comparar fecha_vencimiento con fecha actual
//    - Rechazar automáticamente licencias vencidas
//    - Mostrar mensaje: "Tu licencia está vencida desde {fecha}"
//
// 2. VALIDACIÓN DE CATEGORÍA B REQUERIDA
//    - UniRide requiere licencia tipo B para conductores
//    - Si categoria no contiene 'B', rechazar
//    - Mostrar mensaje: "Se requiere licencia tipo B para conducir"
//
// 3. VALIDACIÓN DE FORMATO DE PLACA ECUATORIANA
//    - Formato válido: 3 letras + 3-4 números (ABC1234)
//    - Primera letra indica provincia (P=Pichincha, G=Guayas, etc.)
//    - Rechazar placas con formato inválido
//
// 4. VALIDACIÓN DE VIN/CHASIS
//    - Debe tener exactamente 17 caracteres
//    - No debe contener I, O, Q (estándar internacional)
//    - Validar dígito verificador (posición 9)
//
// 5. VALIDACIÓN DE AÑO DEL VEHÍCULO
//    - Debe estar entre 1990 y año actual + 1
//    - Opcionalmente: rechazar vehículos muy antiguos para UniRide
//
// 6. VALIDACIÓN CRUZADA NOMBRE-CÉDULA
//    - Opcional: Verificar con API del Registro Civil
//    - Confirmar que el nombre coincide con la cédula
//
// 7. VALIDACIÓN DE CLASE DE VEHÍCULO PERMITIDA
//    - Solo permitir: AUTOMOVIL, CAMIONETA, JEEP, SUV
//    - Rechazar: MOTOCICLETA, BUS, CAMIÓN
//
// 8. DETECCIÓN DE DOCUMENTOS DUPLICADOS
//    - Verificar si la placa ya está registrada por otro usuario
//    - Verificar si la licencia ya está registrada
//    - Evitar registros fraudulentos
