// lib/data/services/notification_service.dart
// Servicio de notificaciones push (FCM + flutter_local_notifications)
// Maneja: inicialización, token, foreground display, deep linking, supresión

import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_service.dart';
import '../../firebase_options.dart';

/// Background message handler — DEBE ser top-level (no método de instancia)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // FCM auto-muestra la notificación en background/killed via payload 'notification'
  debugPrint('🔔 Background message: ${message.data['type']}');
}

/// Servicio singleton para notificaciones push
class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirestoreService _firestoreService = FirestoreService();

  GoRouter? _router;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _currentUserId;
  bool _initialized = false;

  /// Tipos de notificación suprimidos (pantallas activas los registran)
  final Set<String> _suppressedTypes = {};

  /// Stream para notificar a pantallas activas que deben abrir el chat
  /// Emite {tripId, passengerId} cuando el usuario toca una notificación de chat
  final _openChatController = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get onOpenChatRequested => _openChatController.stream;

  // ============================================================
  // CANALES DE NOTIFICACIÓN ANDROID
  // ============================================================

  static const AndroidNotificationChannel _tripChannel =
      AndroidNotificationChannel(
    'uniride_trips',
    'Viajes',
    description: 'Notificaciones de viajes en curso',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _chatChannel =
      AndroidNotificationChannel(
    'uniride_chat_v2',
    'Mensajes',
    description: 'Mensajes de chat con conductor/pasajero',
    importance: Importance.high,
  );

  // ============================================================
  // INICIALIZACIÓN
  // ============================================================

  /// Inicializar FCM, canales, listeners.
  /// Llamar en main.dart después de Firebase.initializeApp()
  Future<void> initialize(GoRouter router) async {
    if (_initialized) return;
    _router = router;

    // Crear canales de notificación Android
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(_tripChannel);
      await androidPlugin.createNotificationChannel(_chatChannel);
    }

    // Inicializar flutter_local_notifications
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    // Configurar presentación de notificaciones en foreground
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false, // No auto-mostrar, lo manejamos con flutter_local_notifications
      badge: false,
      sound: false,
    );

    // Listener de mensajes en foreground
    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Listener de notificaciones tapeadas (app en background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Verificar si la app se abrió desde una notificación (app killed)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // Delay para que el router esté listo
      Future.delayed(const Duration(seconds: 2), () {
        _handleNotificationTap(initialMessage);
      });
    }

    _initialized = true;
    debugPrint('🔔 NotificationService inicializado');
  }

  // ============================================================
  // TOKEN MANAGEMENT
  // ============================================================

  /// Obtener FCM token y guardarlo en Firestore.
  /// También escucha cambios de token.
  Future<void> saveTokenForUser(String userId) async {
    _currentUserId = userId;

    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _firestoreService.updateFcmToken(userId, token);
        debugPrint('🔔 FCM token guardado para $userId');
      }
    } catch (e) {
      debugPrint('🔔 Error guardando FCM token: $e');
    }

    // Escuchar cambios de token (rotación automática)
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
      try {
        await _firestoreService.updateFcmToken(userId, newToken);
        debugPrint('🔔 FCM token actualizado (refresh)');
      } catch (e) {
        debugPrint('🔔 Error actualizando token refresh: $e');
      }
    });
  }

  // ============================================================
  // PERMISOS
  // ============================================================

  /// Verificar si las notificaciones están autorizadas (sin pedir permiso).
  Future<bool> isPermissionGranted() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Solicitar permiso POST_NOTIFICATIONS (Android 13+).
  /// Retorna true si fue concedido.
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: false,
      sound: true,
      provisional: false,
    );

    debugPrint(
        '🔔 Permiso de notificaciones: ${settings.authorizationStatus}');
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  /// Solicitar permiso solo una vez (para llamada automática en initState).
  Future<void> requestPermissionIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyAsked = prefs.getBool('notification_permission_asked') ?? false;
    if (alreadyAsked) return;

    await requestPermission();
    await prefs.setBool('notification_permission_asked', true);
  }

  // ============================================================
  // SUPRESIÓN (pantallas activas evitan notificaciones redundantes)
  // ============================================================

  /// Suprimir un tipo de notificación (llamar en initState de pantallas)
  void suppressType(String type) => _suppressedTypes.add(type);

  /// Dejar de suprimir (llamar en dispose de pantallas)
  void unsuppressType(String type) => _suppressedTypes.remove(type);

  // ============================================================
  // FOREGROUND MESSAGE HANDLER
  // ============================================================

  void _onForegroundMessage(RemoteMessage message) {
    final type = message.data['type'] as String? ?? '';

    // Si este tipo está suprimido (la pantalla relevante ya está visible), ignorar
    if (_suppressedTypes.contains(type)) {
      debugPrint('🔔 Notificación suprimida (foreground): $type');
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    // Determinar canal según tipo
    final channelId =
        type == 'new_chat_message' ? _chatChannel.id : _tripChannel.id;

    // Mostrar notificación local
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId == _chatChannel.id ? _chatChannel.name : _tripChannel.name,
          channelDescription: channelId == _chatChannel.id
              ? _chatChannel.description
              : _tripChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(message.data),
    );

    debugPrint('🔔 Notificación foreground mostrada: $type');
  }

  // ============================================================
  // NOTIFICATION TAP HANDLER (deep linking)
  // ============================================================

  /// Cuando el usuario toca una notificación (app en background)
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    _navigateFromData(data);
  }

  /// Cuando el usuario toca una notificación local (foreground)
  void _onLocalNotificationTapped(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _navigateFromData(data);
    } catch (e) {
      debugPrint('🔔 Error parseando payload de notificación: $e');
    }
  }

  /// Navegar según el tipo de notificación
  void _navigateFromData(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    final tripId = data['tripId'] as String? ?? '';
    final senderRole = data['senderRole'] as String? ?? '';
    final router = _router;
    if (router == null) return;

    debugPrint('🔔 Navegando desde notificación: $type (tripId: $tripId)');

    switch (type) {
      case 'new_chat_message':
        // Solo chat hace deep link — abre el bottom sheet en la pantalla activa
        final chatPassengerId = data['senderId'] as String? ?? '';
        if (tripId.isNotEmpty) {
          _openChatController.add({
            'tripId': tripId,
            'passengerId': senderRole == 'pasajero' ? chatPassengerId : '',
            'senderRole': senderRole,
          });
          debugPrint('🔔 Emitido evento openChat: tripId=$tripId, senderId=$chatPassengerId');
        }
        break;

      default:
        // Todas las demás notificaciones solo abren la app (sin navegar)
        debugPrint('🔔 Notificación tocada ($type) — solo abrir app');
        break;
    }
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  void dispose() {
    _foregroundSub?.cancel();
    _tokenRefreshSub?.cancel();
    _suppressedTypes.clear();
    _openChatController.close();
  }
}
