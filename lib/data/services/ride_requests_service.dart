// lib/data/services/ride_requests_service.dart
// Servicio para operaciones CRUD de solicitudes de viaje
// Colección: ride_requests

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ride_request_model.dart';
import '../models/trip_model.dart';

/// Servicio para operaciones con la colección 'ride_requests'
/// Maneja solicitudes de pasajeros que buscan conductores
class RideRequestsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _requestsCollection = 'ride_requests';
  static const int _defaultExpiryMinutes = 3; // Las solicitudes expiran en 3 min

  // ==================== CRUD Básico ====================

  /// Crear nueva solicitud de viaje (pasajero)
  ///
  /// Cancela solicitudes activas previas antes de crear la nueva.
  /// Retorna el requestId generado.
  Future<String> createRequest(RideRequestModel request) async {
    try {
      // Cancelar solicitudes activas previas del mismo pasajero
      await _cancelPreviousActiveRequests(request.passengerId);

      final docRef = _firestore.collection(_requestsCollection).doc();
      final requestWithId = request.copyWith(requestId: docRef.id);

      await docRef.set(requestWithId.toJson());

      return docRef.id;
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al crear solicitud: $e');
    }
  }

  /// Cancelar todas las solicitudes activas previas de un pasajero
  Future<void> _cancelPreviousActiveRequests(String passengerId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_requestsCollection)
          .where('passengerId', isEqualTo: passengerId)
          .where('status', isEqualTo: 'searching')
          .get();

      if (querySnapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.update(doc.reference, {
          'status': 'cancelled',
          'completedAt': Timestamp.now(),
        });
      }
      await batch.commit();
    } catch (e) {
      // No bloquear la creación si falla la cancelación
      // Las solicitudes viejas expirarán solas
    }
  }

  /// Obtener solicitud por ID
  Future<RideRequestModel?> getRequest(String requestId) async {
    try {
      final doc = await _firestore
          .collection(_requestsCollection)
          .doc(requestId)
          .get();

      if (!doc.exists) return null;

      return RideRequestModel.fromFirestore(doc);
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al obtener solicitud: $e');
    }
  }

  /// Stream de una solicitud en tiempo real
  ///
  /// Útil para que el pasajero vea cuando un conductor acepta
  Stream<RideRequestModel?> getRequestStream(String requestId) {
    try {
      return _firestore
          .collection(_requestsCollection)
          .doc(requestId)
          .snapshots()
          .map((doc) {
        if (!doc.exists) return null;
        return RideRequestModel.fromFirestore(doc);
      });
    } catch (e) {
      throw Exception('Error en stream de solicitud: $e');
    }
  }

  /// Cancelar solicitud (pasajero)
  Future<void> cancelRequest(String requestId) async {
    try {
      await _firestore
          .collection(_requestsCollection)
          .doc(requestId)
          .update({
        'status': 'cancelled',
        'completedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al cancelar solicitud: $e');
    }
  }

  // ==================== Conductor: Buscar solicitudes ====================

  /// Buscar solicitudes activas que coincidan con la ruta del conductor
  ///
  /// Usa filtro por status en Firestore + filtro geográfico client-side
  /// [driverOrigin] - Origen del viaje del conductor
  /// [driverDestination] - Destino del viaje del conductor
  /// [radiusKm] - Radio de búsqueda en km
  Future<List<RideRequestModel>> findMatchingRequests({
    required TripLocation driverOrigin,
    required TripLocation driverDestination,
    double radiusKm = 5.0,
  }) async {
    try {
      // Query: solicitudes activas (searching) que no hayan expirado
      final querySnapshot = await _firestore
          .collection(_requestsCollection)
          .where('status', isEqualTo: 'searching')
          .where('expiresAt', isGreaterThan: Timestamp.now())
          .get();

      final results = <RideRequestModel>[];

      for (final doc in querySnapshot.docs) {
        final request = RideRequestModel.fromFirestore(doc);

        // Verificar si el origen del pasajero está cerca de la ruta del conductor
        final originDistance = _haversineDistance(
          request.origin.latitude,
          request.origin.longitude,
          driverOrigin.latitude,
          driverOrigin.longitude,
        );

        // Verificar si el destino del pasajero está cerca del destino del conductor
        final destDistance = _haversineDistance(
          request.destination.latitude,
          request.destination.longitude,
          driverDestination.latitude,
          driverDestination.longitude,
        );

        // Ambos deben estar dentro del radio
        if (originDistance <= radiusKm && destDistance <= radiusKm) {
          results.add(request);
        }
      }

      // Ordenar por hora de solicitud (más recientes primero)
      results.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

      return results;
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al buscar solicitudes: $e');
    }
  }

  /// Stream de solicitudes que coinciden con la ruta del conductor
  ///
  /// Se actualiza en tiempo real cuando hay nuevas solicitudes
  Stream<List<RideRequestModel>> getMatchingRequestsStream({
    required TripLocation driverOrigin,
    required TripLocation driverDestination,
    double radiusKm = 5.0,
  }) {
    try {
      // Capturar timestamp UNA sola vez para evitar crear queries nuevas en cada tick
      final now = Timestamp.now();

      return _firestore
          .collection(_requestsCollection)
          .where('status', isEqualTo: 'searching')
          .where('expiresAt', isGreaterThan: now)
          .snapshots()
          .map((snapshot) {
        final results = <RideRequestModel>[];

        for (final doc in snapshot.docs) {
          final request = RideRequestModel.fromFirestore(doc);

          final originDistance = _haversineDistance(
            request.origin.latitude,
            request.origin.longitude,
            driverOrigin.latitude,
            driverOrigin.longitude,
          );

          final destDistance = _haversineDistance(
            request.destination.latitude,
            request.destination.longitude,
            driverDestination.latitude,
            driverDestination.longitude,
          );

          if (originDistance <= radiusKm && destDistance <= radiusKm) {
            results.add(request);
          }
        }

        results.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
        return results;
      });
    } catch (e) {
      throw Exception('Error en stream de solicitudes: $e');
    }
  }

  // ==================== Conductor: Aceptar solicitud ====================

  /// Aceptar una solicitud (conductor)
  ///
  /// Actualiza la solicitud con los datos del conductor y viaje
  Future<void> acceptRequest({
    required String requestId,
    required String driverId,
    required String tripId,
    required double agreedPrice,
  }) async {
    try {
      // Verificar que la solicitud aún esté disponible
      final request = await getRequest(requestId);
      if (request == null) {
        throw Exception('Solicitud no encontrada');
      }
      if (request.status != 'searching') {
        throw Exception('Esta solicitud ya no está disponible');
      }

      // Actualizar solicitud
      await _firestore
          .collection(_requestsCollection)
          .doc(requestId)
          .update({
        'status': 'accepted',
        'driverId': driverId,
        'tripId': tripId,
        'agreedPrice': agreedPrice,
        'acceptedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al aceptar solicitud: $e');
    }
  }

  /// Completar solicitud (cuando el viaje termina)
  Future<void> completeRequest(String requestId) async {
    try {
      await _firestore
          .collection(_requestsCollection)
          .doc(requestId)
          .update({
        'status': 'completed',
        'completedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al completar solicitud: $e');
    }
  }

  // ==================== Pasajero: Mis solicitudes ====================

  /// Obtener solicitudes activas del pasajero
  Future<List<RideRequestModel>> getPassengerActiveRequests(
    String passengerId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection(_requestsCollection)
          .where('passengerId', isEqualTo: passengerId)
          .where('status', whereIn: ['searching', 'accepted'])
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => RideRequestModel.fromFirestore(doc))
          .toList();
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al obtener solicitudes del pasajero: $e');
    }
  }

  /// Stream de solicitudes del pasajero
  Stream<List<RideRequestModel>> getPassengerRequestsStream(
    String passengerId,
  ) {
    try {
      return _firestore
          .collection(_requestsCollection)
          .where('passengerId', isEqualTo: passengerId)
          .where('status', whereIn: ['searching', 'accepted'])
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => RideRequestModel.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      throw Exception('Error en stream de solicitudes del pasajero: $e');
    }
  }

  // ==================== Utilidades ====================

  /// Crear solicitud con valores por defecto
  RideRequestModel createRequestModel({
    required String passengerId,
    required TripLocation origin,
    required TripLocation destination,
    required TripLocation pickupPoint,
    String? referenceNote,
    List<String> preferences = const ['mochila'],
    String? objectDescription,
    String? petType,
    String? petSize,
    String? petDescription,
    String paymentMethod = 'Efectivo',
    double? maxPrice,
    DateTime? departureTime,
    int expiryMinutes = _defaultExpiryMinutes,
  }) {
    final now = DateTime.now();
    return RideRequestModel(
      requestId: '', // Se asigna en createRequest
      passengerId: passengerId,
      status: 'searching',
      origin: origin,
      destination: destination,
      pickupPoint: pickupPoint,
      referenceNote: referenceNote,
      preferences: preferences,
      objectDescription: objectDescription,
      petType: petType,
      petSize: petSize,
      petDescription: petDescription,
      paymentMethod: paymentMethod,
      maxPrice: maxPrice,
      requestedAt: now,
      departureTime: departureTime,
      expiresAt: now.add(Duration(minutes: expiryMinutes)),
      createdAt: now,
    );
  }

  /// Fórmula de Haversine para calcular distancia
  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371;

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Manejo de errores de Firestore
  String _handleFirestoreError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permiso denegado';
      case 'not-found':
        return 'Solicitud no encontrada';
      case 'already-exists':
        return 'La solicitud ya existe';
      case 'unavailable':
        return 'Servicio no disponible. Intenta más tarde.';
      default:
        return e.message ?? 'Error de base de datos';
    }
  }
}
