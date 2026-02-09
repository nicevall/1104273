// lib/data/services/tts_service.dart
// Servicio de Text-to-Speech para navegación GPS y lectura de solicitudes
// Usa flutter_tts para sintetizar voz en español

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  // Singleton
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeakingNavigation = false;

  /// Inicializar el servicio TTS
  Future<void> init() async {
    if (_isInitialized) return;

    await _tts.setLanguage('es-ES');
    await _tts.setSpeechRate(0.5); // Velocidad moderada para que se entienda
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Android: usar el motor TTS del sistema
    await _tts.setQueueMode(1); // 1 = ADD (agrega a cola, no interrumpe)

    _tts.setCompletionHandler(() {
      _isSpeakingNavigation = false;
    });

    _isInitialized = true;
  }

  /// Hablar instrucción de navegación (PRIORIDAD ALTA)
  /// Interrumpe cualquier cosa que se esté diciendo
  Future<void> speakNavigation(String instruction) async {
    await init();
    _isSpeakingNavigation = true;
    await _tts.stop(); // Interrumpe lo anterior
    await _tts.speak(instruction);
  }

  /// Leer detalles de una solicitud de pasajero (PRIORIDAD NORMAL)
  /// Solo habla si no hay navegación activa
  Future<void> speakRequest(String text) async {
    await init();
    if (_isSpeakingNavigation) return; // No interrumpir navegación
    await _tts.speak(text);
  }

  /// Anuncio general (ej: "Ruta actualizada", "Pasajero agregado")
  Future<void> speakAnnouncement(String text) async {
    await init();
    await _tts.stop();
    await _tts.speak(text);
  }

  /// Parar todo el habla
  Future<void> stop() async {
    _isSpeakingNavigation = false;
    await _tts.stop();
  }

  /// Liberar recursos
  Future<void> dispose() async {
    await _tts.stop();
    _isInitialized = false;
  }
}
