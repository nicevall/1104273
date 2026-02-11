import 'dart:io';
import 'dart:convert'; // Para base64Encode, jsonEncode
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
  license, // Licencia de conducir (Frente)
  licenseBack, // Licencia de conducir (Reverso)
  registration, // Matrícula vehicular
  vehicle, // Foto del vehículo (sin OCR, solo anti-spoofing)
}

/// Servicio de verificación de documentos usando ML Kit
/// Implementa OCR y detección básica de anti-spoofing
/// Especializado en documentos ANT Ecuador
class DocumentVerificationService {
  // URL base de la API de Vision
  static const _baseUrl = 'https://vision.googleapis.com/v1/images:annotate';

  // Obtener API Key de variables de entorno
  String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  /// Verificar un documento llamando directamente a Google Cloud Vision API
  Future<DocumentVerificationResult> verifyDocument({
    required File imageFile,
    required DocumentType documentType,
  }) async {
    try {
      debugPrint('--- INICIANDO VERIFICACIÓN DE DOCUMENTO: $documentType ---');
      if (_apiKey.isEmpty) {
        return DocumentVerificationResult.invalid(
          'Falta configurar la API Key de Google Cloud.',
        );
      }

      // 1. Convertir imagen a Base64
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // 2. Preparar el Request Body
      final requestBody = {
        "requests": [
          {
            "image": {"content": base64Image},
            "features": [
              {"type": "TEXT_DETECTION"},
              {
                "type": "LABEL_DETECTION"
              } // Útil para verificar si es un auto/documento
            ]
          }
        ]
      };

      // 3. Hacer la llamada HTTP POST
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        debugPrint('Error Vision API: ${response.body}');
        return DocumentVerificationResult.invalid(
          'Error al conectar con el servicio de reconocimiento (${response.statusCode}).',
        );
      }

      // 4. Parsear la respuesta
      final jsonResponse = jsonDecode(response.body);
      final responses = jsonResponse['responses'] as List;
      if (responses.isEmpty)
        return DocumentVerificationResult.invalid(
            'No se recibió respuesta válida.');

      final firstResponse = responses[0];
      final fullTextAnnotation = firstResponse['fullTextAnnotation'];
      final text = fullTextAnnotation != null
          ? fullTextAnnotation['text'] as String
          : '';

      // Etiquetas (Labels) para validación extra
      final labelAnnotations = firstResponse['labelAnnotations'] as List?;
      final labels = labelAnnotations
              ?.map((l) => l['description'].toString().toLowerCase())
              .toList() ??
          [];

      // 5. Procesar el texto según el tipo de documento
      if (documentType == DocumentType.license) {
        return _processLicenseFront(text, labels);
      } else if (documentType == DocumentType.licenseBack) {
        return _processLicenseBack(text, labels);
      } else if (documentType == DocumentType.registration) {
        return _processRegistration(text, labels);
      } else {
        // Para foto de vehículo, solo validación básica (aunque Vision API podría detectar "Car")
        return DocumentVerificationResult(
          isValid: true,
          hasText: false,
          isPotentialScreenPhoto: false,
        );
      }
    } catch (e) {
      debugPrint('Error en verificación Directa: $e');
      return DocumentVerificationResult.invalid(
        'Error de conexión. Verifica tu internet e intenta de nuevo.',
      );
    }
  }

// ...

  // 1. PROCESAMIENTO FRONTAl (Identificación, Nombres, Vencimiento)
  DocumentVerificationResult _processLicenseFront(
      String text, List<String> labels) {
    if (text.isEmpty)
      return DocumentVerificationResult.invalid('No se detectó texto legible.');

    // Normalización: Mayúsculas, quitar caracteres basura, unificar espacios
    final normalizedText = text
        .toUpperCase()
        .replaceAll(
            RegExp(r'[^A-Z0-9\s\n\.\-]'), '') // Dejar puntos para "1." "4b."
        .replaceAll(RegExp(r' {2,}'), ' ');

    final lines = normalizedText.split('\n').map((l) => l.trim()).toList();

    debugPrint('\n=== DATOS OCR LICENCIA FRENTE (EXPERT) ===');
    debugPrint('Texto Normalizado:\n$normalizedText');

    String? idNumber; // Campo 8
    String? lastNames; // Campo 1
    String? names; // Campo 2
    String? expiration; // Campo 4b

    // Regex auxiliares
    final digit10Regex = RegExp(r'\b\d{10}\b');
    // DD/MM/YYYY (permitir 1-2 dígitos para día/mes)
    final dateRegex = RegExp(r'\b(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})\b');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // ... LOGIN NOMBRES/APELLIDOS ... (Mantener código existente, solo mostrando donde insertaríamos si fuera diff contextual, pero reemplazamos bloque grande)
      // Insertando lógica de CATEGORIA como bloque nuevo dentro del loop:

      // 1. APELLIDOS
      // ESTRATEGIA A: Formato Numerado (1. XXXXX)
      if (line.startsWith('1.') ||
          line.startsWith('1 ') ||
          line.startsWith('I.') ||
          line.startsWith('l.')) {
        lastNames = line.replaceFirst(RegExp(r'^[1Il][\.\s]+'), '').trim();
      }
      // ESTRATEGIA B: Formato Etiquetas (APELLIDO / FAMILY NAME) - Formato 2
      else if (line.contains('APELLIDO')) {
        // En Formato 2, el valor suele estar en la línea siguiente
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1];
          // Validar que no sea otra etiqueta o basura
          if (!nextLine.contains('NOMBRE') && !nextLine.contains('2.')) {
            // Si ya teníamos un candidato malo, este lo sobrescribe porque es más explícito por etiqueta
            lastNames = nextLine.trim();
          }
        }
      }

      // Limpieza adicional de Apellidos
      lastNames = lastNames
          ?.replaceAll(RegExp(r'\s+(?:DE\s+)?[\d\.\-\/]+.*$'), '')
          .trim();

      // 2. NOMBRES
      // ESTRATEGIA A: Formato Numerado (2. XXXXX)
      if (line.startsWith('2.') || line.startsWith('2 ')) {
        // Cortar cualquier referencia al campo 3 (FECHA NAC) si aparece en la misma línea
        String tempName = line;
        if (tempName.contains('3.')) tempName = tempName.split('3.')[0];
        if (tempName.contains('3 ')) tempName = tempName.split('3 ')[0];

        names = tempName.replaceFirst(RegExp(r'^2[\.\s]+'), '').trim();
      }
      // ESTRATEGIA B: Formato Etiquetas (NOMBRE / NAME) - Formato 2
      else if (line.contains('NOMBRE') && !line.contains('APELLIDO')) {
        // Evitar "APELLIDO Y NOMBRE"
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1];
          if (!nextLine.contains('FECHA') && !nextLine.contains('3.')) {
            names = nextLine.trim();
          }
        }
      }

      // Limpieza de Nombres
      names =
          names?.replaceAll(RegExp(r'\s+(?:DE\s+)?[\d\.\-\/]+.*$'), '').trim();

      // Fallback Cruzado: Si tenemos Nombres (por etiqueta) pero no Apellidos
      // Buscar hacia atrás desde la línea de la etiqueta "NOMBRE"
      if (names != null && lastNames == null && line.contains('NOMBRE')) {
        // En formato 2:
        // Linea N: APELLIDO
        // Linea N+1: VALOR APELLIDO
        // Linea N+2: NOMBRE  <-- Estamos aquí (line) o en la anterior
        // A veces el OCR lee distinto.

        // Intentar buscar hacia atrás un texto que parezca apellido
        if (i > 1) {
          final prevLine = lines[i - 1];
          // Si la linea anterior no es etiqueta "APELLIDO", podría ser el valor del apellido
          if (!prevLine.contains('APELLIDO') && prevLine.length > 3) {
            lastNames = prevLine.trim();
          }
        }
      }

      // Backward Scan para Formato 1 (Numerado)
      if (names != null &&
          lastNames == null &&
          (line.startsWith('2.') || line.startsWith('2 '))) {
        if (i > 0) {
          final prevLine = lines[i - 1];
          if (prevLine.startsWith('1.') ||
              prevLine.startsWith('1 ') ||
              prevLine.startsWith('I.')) {
            lastNames =
                prevLine.replaceFirst(RegExp(r'^[1I][\.\s]+'), '').trim();
            lastNames = lastNames
                ?.replaceAll(RegExp(r'\s+(?:DE\s+)?[\d\.\-\/]+.*$'), '')
                .trim();
          } else if (!prevLine.contains('APELLIDOS') &&
              !prevLine.contains('NOMBRES')) {
            if (prevLine.length > 2) lastNames = prevLine.trim();
          }
        }
      }

      // 4b. VENCIMIENTO
      // Puede ser "4B.", "VENCIMIENTO", "HASTA", "CADUCA"
      if (line.contains('4B') ||
          line.contains('VENCIMIENTO') ||
          line.contains('HASTA') ||
          line.contains('CADUCA')) {
        final dateMatch = dateRegex.firstMatch(line);
        if (dateMatch != null) {
          expiration = dateMatch.group(0);
        } else if (i + 1 < lines.length) {
          final nextLine = lines[i + 1];
          final nextMatch = dateRegex.firstMatch(nextLine);
          if (nextMatch != null) expiration = nextMatch.group(0);
        }
      }

      // Fallback Vencimiento: buscar fecha aislada en las ultimas lineas si aun es null
      if (expiration == null && i > lines.length - 4) {
        final dateMatch = dateRegex.firstMatch(line);
        if (dateMatch != null) expiration = dateMatch.group(0);
      }

      // 8. IDENTIFICACIÓN (CÉDULA)
      // El usuario reporta que está seguido de "9." o cerca
      // Tambien buscar "NO.", "IDENTIFICACION", "CEDULA"
      if (line.contains('8.') ||
          line.contains('NO.') ||
          line.contains('9.') ||
          line.contains('IDENTIFICACION') ||
          line.contains('LICENCIA') ||
          line.contains('NUMBER')) {
        final idMatch = digit10Regex.firstMatch(line);
        if (idMatch != null) {
          idNumber = idMatch.group(0);
        } else if (i + 1 < lines.length) {
          final nextLine = lines[i + 1];
          final nextMatch = digit10Regex.firstMatch(nextLine);
          if (nextMatch != null)
            idNumber = nextMatch.group(0);
          else if (i > 0) {
            // A veces está antes (ej: 9. 1234567890)
            final prevLine = lines[i - 1];
            final prevMatch = digit10Regex.firstMatch(prevLine);
            if (prevMatch != null) idNumber = prevMatch.group(0);
          }
        }
      }

      // Fallback ID: Si encontramos un numero de 10 digitos aislado y no tenemos ID
      if (idNumber == null) {
        final idMatch = digit10Regex.firstMatch(line);
        if (idMatch != null) idNumber = idMatch.group(0);
      }
    }

    final isExpired = _isLicenseExpired(expiration);
    final isValidExpiration = expiration != null && !isExpired;

    final isValidId = idNumber != null;
    final isValidNames = names != null && names.isNotEmpty;
    final isValidLastNames = lastNames != null && lastNames.isNotEmpty;

    final isValid =
        isValidExpiration && isValidId && isValidNames && isValidLastNames;

    String? errorMessage;
    if (!isValid) {
      final missing = <String>[];
      if (!isValidId) missing.add('Cédula');
      if (!isValidNames) missing.add('Nombres');
      if (!isValidLastNames) missing.add('Apellidos');

      if (expiration == null) {
        missing.add('Vencimiento');
      } else if (isExpired) {
        return DocumentVerificationResult.invalid(
            'Licencia Vencida ($expiration)');
      }

      errorMessage = 'Faltan datos en el frente: ${missing.join(", ")}.';
    }

    final result = DocumentVerificationResult(
      isValid: isValid,
      hasText: true,
      isPotentialScreenPhoto: false,
      extractedText: normalizedText,
      errorMessage: errorMessage,
      licenseData: LicenseData(
        numeroLicencia: idNumber,
        nombres: names,
        apellidos: lastNames,
        fechaVencimiento: expiration,
        categoria: null, // Se lee atrás (o se ignora según pedido)
        tipoSangre: null, // Se lee atrás
      ),
    );

    debugPrint('Datos Estructurados (FRENTE): ${result.licenseData}');
    debugPrint('Es Válido: ${result.isValid}');
    debugPrint('========================\n');
    return result;
  }

  // 2. PROCESAMIENTO REVERSO (Categoría, Tipo Sangre)
  DocumentVerificationResult _processLicenseBack(
      String text, List<String> labels) {
    if (text.isEmpty)
      return DocumentVerificationResult.invalid('No se detectó texto.');

    final uppercasedText = text.toUpperCase();
    debugPrint('\n=== DATOS OCR LICENCIA REVERSO (BLOCK STRATEGY) ===');
    debugPrint('Texto Crudo: $uppercasedText');

    // 1. Detección de Tipo de Sangre (Independiente del bloque)
    String? bloodType;
    final bloodRegex = RegExp(r'\b(AB|A|B|O)\s*([+-])');
    final bloodMatch = bloodRegex.firstMatch(uppercasedText);
    if (bloodMatch != null) {
      bloodType = '${bloodMatch.group(1)}${bloodMatch.group(2)}';
    }

    // -------------------------------------------------------------------------
    // ESTRATEGIA: Parsing por Bloques / Filas Virtuales
    // 1. No eliminar espacios ni saltos de línea agresivamente.
    // 2. Buscar candidatos a Categoría (A, B, C, D, E, F, G, A1, ...).
    // 3. Validar co-ocurrencia en ventana +/- N caracteres con:
    //    - TIPO (PARTICULAR/COMERCIAL/etc)
    //    - FECHA (DD-MMM-YYYY o similar)
    // -------------------------------------------------------------------------

    // Limpieza suave: Unificar espacios
    String workingText = uppercasedText
        .replaceAll(RegExp(r'\r\n'), ' ')
        .replaceAll(RegExp(r'\n'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    // Normalización INTELIGENTE de OCR
    // 1. Recuperar categorías rotas (CI -> C1, etc)
    workingText = workingText
        .replaceAll(RegExp(r'\bA[I|l]\b'), 'A1')
        .replaceAll(RegExp(r'\bC[I|l]\b'), 'C1')
        .replaceAll(RegExp(r'\bD[I|l]\b'), 'D1')
        .replaceAll(RegExp(r'\bE[I|l]\b'), 'E1');

    // 2. Recuperar ceros en fechas (O5-JAN -> 05-JAN) - Solo patterns muy claros
    workingText = workingText.replaceAllMapped(
        RegExp(r'\b([O0-9]{2})[\.\-\s]+([A-Z]{3})'),
        (m) => '${m.group(1)!.replaceAll('O', '0')}-${m.group(2)}');

    debugPrint('=== TEXTO NORMALIZADO (WINDOW SEARCH) ===');
    debugPrint(workingText);

    // Listado COMPLETISIMO de categorías válidas (incluyendo las básicas)
    final validCats = [
      'A',
      'A1',
      'B',
      'C',
      'C1',
      'D',
      'D1',
      'E',
      'E1',
      'F',
      'G'
    ];
    final detectedCategories = <String>{};

    // 1. Tipo de Uso
    final usageTypes = ['PARTICULAR', 'COMERCIAL', 'ESTATAL'];

    // Regex Fecha: DD-MMM-YY, DD-MM-YYYY
    final datePattern =
        RegExp(r'(\d{1,2}|O\d|\dO)[\.\-\s]+([A-Z]{3}|\d{2})[\.\-\s]+(\d{2,4})');

    // --- ESTRATEGIA: ANCLAJE POR USO (Usage-First Anchor) ---
    // 1. Una categoría SOLO existe si tiene un TIPO DE USO (Particular/Comercial) inmediatamente asociado.
    // 2. Las fechas se asignan a estas categorías validadas.

    // A. Mapear Categorías Candidatas
    final catMatches = <Map<String, dynamic>>[];
    for (final cat in validCats) {
      final matches = RegExp(r'\b' + cat + r'\b').allMatches(workingText);
      for (final m in matches) {
        catMatches.add({
          'cat': cat,
          'start': m.start,
          'end': m.end,
          'usage': null, // Se llenará si encuentra
          'dates': <DateTime>[],
        });
      }
    }
    catMatches.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));

    // B. Mapear Usos y asignarlos al vecino más cercano
    // Regla: El uso suele estar ANTES (Izquierda) o DESPUES (Derecha) muy cerca.
    // Asignaremos cada USO a la Categoría más cercana (distancia absoluta).
    for (final uType in usageTypes) {
      final matches = RegExp(r'\b' + uType + r'\b').allMatches(workingText);
      for (final m in matches) {
        Map<String, dynamic>? bestCat;
        int minDistance = 9999;

        // Buscar candidato a izquierda o derecha
        for (final cat in catMatches) {
          final catStart = cat['start'] as int;
          final catEnd = cat['end'] as int;

          // Distancia a izq (Uso ... Cat)
          int distBefore = (m.end - catStart).abs();
          // Distancia a der (Cat ... Uso)
          int distAfter = (m.start - catEnd).abs();

          int localDist = (distBefore < distAfter) ? distBefore : distAfter;

          // Umbral estricto: deben estar visualmente juntos (< 80 chars)
          if (localDist < 80 && localDist < minDistance) {
            minDistance = localDist;
            bestCat = cat;
          }
        }

        // Asignar (Gana el más cercano)
        // Nota: Podríamos sobreescribir si un uso está más cerca,
        // pero aquí un uso potencia una categoría.
        // Si el 'bestCat' ya tenía uso, no importa, lo reafirma.
        // Lo importante es eliminar candidatos sin uso.
        if (bestCat != null) {
          bestCat['usage'] = uType;
        }
      }
    }

    // C. Filtrar Candidatos: Solo sobreviven los que tienen Uso (o Vehículo, como backup?)
    // El usuario dijo "Part/Com/Estatal" son los anclas.
    // D1 (ruido) no tendrá uso cerca si C ya se lo llevó (por ser más cercano a ESTATAL).
    final activeCats = catMatches.where((c) => c['usage'] != null).toList();

    // D. Asignar Fechas a los Candidatos Activos
    final allDateMatches = datePattern.allMatches(workingText);
    final monthMap = {
      'JAN': '01',
      'ENE': '01',
      'FEB': '02',
      'MAR': '03',
      'APR': '04',
      'ABR': '04',
      'MAY': '05',
      'JUN': '06',
      'JUL': '07',
      'AUG': '08',
      'AGO': '08',
      'SEP': '09',
      'OCT': '10',
      'NOV': '11',
      'DEC': '12',
      'DIC': '12'
    };

    for (final m in allDateMatches) {
      DateTime? d;
      try {
        String dayS = m.group(1)!.replaceAll('O', '0');
        String monthS = m.group(2)!;
        String yearS = m.group(3)!.replaceAll('O', '0');
        if (yearS.length == 2) yearS = '20$yearS';
        String monthNum = monthS;
        if (monthMap.containsKey(monthS)) monthNum = monthMap[monthS]!;
        d = DateTime(int.parse(yearS), int.parse(monthNum), int.parse(dayS));
      } catch (_) {}

      if (d != null) {
        // Asignar a la Categoría ACTIVA más cercana a la IZQUIERDA
        Map<String, dynamic>? bestCat;
        int minDistance = 9999;

        for (final cat in activeCats) {
          final catEnd = cat['end'] as int;
          if (catEnd < m.start) {
            final dist = m.start - catEnd;
            // Umbral mayor para fechas (pueden estar a derecha)
            if (dist < 150 && dist < minDistance) {
              minDistance = dist;
              bestCat = cat;
            }
          }
        }
        if (bestCat != null) {
          (bestCat['dates'] as List<DateTime>).add(d);
        }
      }
    }

    // E. Generar salida
    for (final cat in activeCats) {
      final dates = cat['dates'] as List<DateTime>;

      // Debe tener fechas (Validación final)
      if (dates.isNotEmpty) {
        detectedCategories.add(cat['cat'] as String);
      }
    }

    final sortedCats = detectedCategories.toList()..sort();
    final categoriesStr = sortedCats.join(', ');

    debugPrint('Categorías (Anchor Logic): $categoriesStr');

    final isValid = detectedCategories.isNotEmpty;
    String? errorMessage;
    if (!isValid)
      errorMessage =
          'No se detectaron categorías válidas con Uso y Fecha asociados.';

    final result = DocumentVerificationResult(
      isValid: isValid,
      hasText: true,
      isPotentialScreenPhoto: false,
      extractedText: workingText,
      errorMessage: errorMessage,
      licenseData: LicenseData(
        categoria: isValid ? categoriesStr : null,
        tipoSangre: bloodType,
      ),
    );

    debugPrint('Datos Estructurados (REVERSO): ${result.licenseData}');
    debugPrint('Es Válido: ${result.isValid}');
    debugPrint('========================\n');
    return result;
  }

  DocumentVerificationResult _processRegistration(
      String text, List<String> labels) {
    if (text.isEmpty)
      return DocumentVerificationResult.invalid('No se detectó texto legible.');

    // 1. Normalización
    // Convertir a mayúsculas, eliminar caracteres especiales innecesarios (solo dejar A-Z, 0-9, espacios, saltos de línea y guiones)
    // Unificar espacios múltiples
    final normalizedText = text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9\s\n\-]'), '')
        .replaceAll(RegExp(r' {2,}'), ' ');

    final lines = normalizedText.split('\n').map((l) => l.trim()).toList();

    debugPrint('\n=== DATOS OCR MATRÍCULA (EXPERT SYSTEM) ===');
    debugPrint('Texto Normalizado:\n$normalizedText');

    String? plate;
    String? brand;
    String? model;
    String? year;
    String? passengers;
    String? vin;

    // RegEx Patterns
    final plateRegex = RegExp(r'\b([A-Z]{3})[\s\-]?(\d{3,4})\b');
    final yearRegex = RegExp(r'\b(19\d{2}|20[0-2]\d)\b');
    final vinRegex = RegExp(r'\b([A-Z0-9]{17})\b');

    // 2. Extracción de Datos
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // A. PLACA (Prioridad Máxima: detectar en todas las líneas)
      final plateMatches = plateRegex.allMatches(line);
      for (final match in plateMatches) {
        final candidate = match.group(0);
        if (candidate != null) {
          // Elegir la coincidencia más completa (mayor longitud)
          if (plate == null || candidate.length > plate!.length) {
            String cleanPlate =
                candidate.replaceAll(' ', '').replaceAll('-', '');
            // Formatear estándar: ABC-1234
            if (cleanPlate.length >= 6) {
              plate =
                  '${cleanPlate.substring(0, 3)}-${cleanPlate.substring(3)}';
            }
          }
        }
      }

      // B. AÑO y VIN (Búsqueda auxiliar en todas las líneas)
      if (year == null) {
        final yMatch = yearRegex.firstMatch(line);
        if (yMatch != null) year = yMatch.group(0);
      }
      if (vin == null) {
        final vMatch = vinRegex.firstMatch(line);
        if (vMatch != null) vin = vMatch.group(0);
      }

      // C. Lógica Contextual (Línea Siguiente)
      if (i + 1 < lines.length) {
        final nextLine = lines[i + 1];

        // MARCA: Línea inmediatamente posterior a "MARCA"
        if (line.contains('MARCA') && !line.contains('AÑO')) {
          if (brand == null && nextLine.isNotEmpty) {
            brand = nextLine;
          }
        }

        // MODELO: Línea inmediatamente posterior a "MODELO" o "AÑO MODELO"
        // A veces Vision API separa "AÑO" y "MODELO" en líneas distintas, o solo dice "MODELO"
        if (line.contains('MODELO')) {
          if (model == null && nextLine.isNotEmpty) {
            // Evitar confundir con el año si aparece ahí
            if (!nextLine.contains('19') && !nextLine.contains('20')) {
              model = nextLine;
            }
          }
        }

        // PASAJEROS: Línea siguiente a "PASAJEROS", número entero positivo
        if (line.contains('PASAJEROS')) {
          final passMatch = RegExp(r'\b(\d+)\b').firstMatch(nextLine);
          if (passMatch != null) {
            final val = int.tryParse(passMatch.group(1) ?? '');
            if (val != null && val > 0 && val < 60) {
              passengers = val.toString();
            }
          }
        }
      }
    }

    // 3. Validación Estricta
    final isValidPlate = plate != null;
    final isValidBrand = brand != null && brand.isNotEmpty;
    final isValidModel = model != null && model.isNotEmpty;
    final isValidPassengers = passengers != null;

    final isValid =
        isValidPlate && isValidBrand && isValidModel && isValidPassengers;

    String? errorMessage;
    if (!isValid) {
      final missing = <String>[];
      if (!isValidPlate) missing.add('Placa');
      if (!isValidBrand) missing.add('Marca');
      if (!isValidModel) missing.add('Modelo');
      if (!isValidPassengers) missing.add('Pasajeros');
      errorMessage =
          'Faltan datos obligatorios: ${missing.join(", ")}. Intenta mejorar la foto.';
    }

    final result = DocumentVerificationResult(
      isValid: isValid,
      hasText: true,
      isPotentialScreenPhoto: false,
      extractedText: normalizedText,
      errorMessage: errorMessage,
      vehicleData: VehicleData(
        placa: plate,
        marca: brand,
        modelo: model,
        anio: year,
        vinChasis: vin,
        pasajeros: passengers,
      ),
    );

    debugPrint('Datos Estructurados: ${result.vehicleData}');
    debugPrint('Es Válido (Strict): ${result.isValid}');
    debugPrint('Error: ${result.errorMessage}');
    debugPrint('========================\n');

    return result;
  }

  // Helpers

  bool _isLicenseExpired(String? dateStr) {
    if (dateStr == null)
      return true; // Asumir vencida si no lee fecha (o falta)

    try {
      final parts = dateStr.replaceAll('/', '-').split('-');
      if (parts.length != 3) {
        debugPrint('Fecha mal formada: $dateStr');
        return true;
      }
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final expDate = DateTime(year, month, day);
      final now = DateTime.now();

      final isExpired = now.isAfter(expDate);
      debugPrint(
          'Fecha Vencimiento: $expDate vs Hoy: $now -> Vencida: $isExpired');
      return isExpired;
    } catch (e) {
      debugPrint('Error parseando fecha: $e');
      return true;
    }
  }

  Future<bool> detectPhotoOfPhoto(File imageFile) async {
    return true;
  }

  void dispose() {}
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
