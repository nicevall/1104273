// lib/data/services/trips_service.dart
// Servicio para operaciones CRUD de viajes en Firestore

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/trip_model.dart';

/// Servicio para operaciones con la colección 'trips' en Firestore
/// Maneja CRUD de viajes, búsqueda geográfica y gestión de pasajeros
class TripsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _tripsCollection = 'trips';

  // ==================== CRUD Básico ====================

  /// Crear un nuevo viaje
  ///
  /// Retorna el tripId generado por Firestore
  Future<String> createTrip(TripModel trip) async {
    try {
      final docRef = _firestore.collection(_tripsCollection).doc();
      final tripWithId = trip.copyWith(tripId: docRef.id);

      await docRef.set(tripWithId.toJson());

      return docRef.id;
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al crear viaje: $e');
    }
  }

  /// Obtener viaje por ID
  ///
  /// Retorna [TripModel] si existe, null si no
  Future<TripModel?> getTrip(String tripId) async {
    try {
      final doc = await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .get();

      if (!doc.exists) {
        return null;
      }

      return TripModel.fromFirestore(doc);
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al obtener viaje: $e');
    }
  }

  /// Stream de un viaje en tiempo real
  ///
  /// Útil para ver cambios en solicitudes de pasajeros
  Stream<TripModel?> getTripStream(String tripId) {
    try {
      return _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .snapshots()
          .map((doc) {
        if (!doc.exists) return null;
        return TripModel.fromFirestore(doc);
      });
    } catch (e) {
      throw Exception('Error en stream de viaje: $e');
    }
  }

  /// Actualizar viaje completo
  ///
  /// No modifica tripId, driverId, createdAt
  Future<void> updateTrip(TripModel trip) async {
    try {
      final data = trip.toJson();
      data.remove('tripId');
      data.remove('driverId');
      data.remove('createdAt');

      await _firestore
          .collection(_tripsCollection)
          .doc(trip.tripId)
          .update(data);
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al actualizar viaje: $e');
    }
  }

  /// Cancelar viaje
  ///
  /// Solo cancela si el viaje está en estado 'scheduled'
  Future<void> cancelTrip(String tripId) async {
    try {
      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .update({
        'status': 'cancelled',
        'completedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al cancelar viaje: $e');
    }
  }

  /// Eliminar viaje permanentemente
  ///
  /// SOLO para uso de desarrollo/testing
  Future<void> deleteTrip(String tripId) async {
    try {
      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .delete();
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al eliminar viaje: $e');
    }
  }

  /// Eliminar todos los viajes de un conductor
  ///
  /// SOLO para uso de desarrollo/testing
  Future<int> deleteAllDriverTrips(String driverId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_tripsCollection)
          .where('driverId', isEqualTo: driverId)
          .get();

      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      return querySnapshot.docs.length;
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al eliminar viajes: $e');
    }
  }

  // ==================== Consultas del Conductor ====================

  /// Verificar si el conductor tiene un viaje instantáneo activo
  ///
  /// Retorna el viaje activo si existe, null si no
  Future<TripModel?> getActiveInstantTrip(String driverId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_tripsCollection)
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      return TripModel.fromFirestore(querySnapshot.docs.first);
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al verificar viaje activo: $e');
    }
  }

  /// Obtener viajes del conductor (una sola vez)
  ///
  /// Filtrados por status opcionales, ordenados por fecha de salida
  Future<List<TripModel>> getDriverTrips(
    String driverId, {
    List<String>? statusFilter,
  }) async {
    try {
      Query query = _firestore
          .collection(_tripsCollection)
          .where('driverId', isEqualTo: driverId);

      if (statusFilter != null && statusFilter.isNotEmpty) {
        query = query.where('status', whereIn: statusFilter);
      }

      query = query.orderBy('departureTime', descending: false);

      final querySnapshot = await query.get();

      return querySnapshot.docs
          .map((doc) => TripModel.fromFirestore(doc))
          .toList();
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al obtener viajes del conductor: $e');
    }
  }

  /// Stream de viajes del conductor en tiempo real
  ///
  /// Se actualiza automáticamente cuando hay cambios
  Stream<List<TripModel>> getDriverTripsStream(
    String driverId, {
    List<String>? statusFilter,
  }) {
    try {
      Query query = _firestore
          .collection(_tripsCollection)
          .where('driverId', isEqualTo: driverId);

      if (statusFilter != null && statusFilter.isNotEmpty) {
        query = query.where('status', whereIn: statusFilter);
      }

      query = query.orderBy('departureTime', descending: false);

      return query.snapshots().map((snapshot) {
        return snapshot.docs
            .map((doc) => TripModel.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      throw Exception('Error en stream de viajes del conductor: $e');
    }
  }

  // ==================== Búsqueda de Viajes (Pasajero) ====================

  /// Buscar viajes disponibles cerca del origen y destino del pasajero
  ///
  /// Usa filtro por fecha/status en Firestore + filtro geográfico client-side (Haversine)
  /// Suficiente para comunidad universitaria (área geográfica limitada)
  ///
  /// [originLat], [originLng] - Ubicación de origen del pasajero
  /// [destLat], [destLng] - Ubicación de destino del pasajero
  /// [departureDate] - Fecha deseada de salida
  /// [radiusKm] - Radio de búsqueda en kilómetros (default 5km)
  Future<List<TripModel>> searchTrips({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required DateTime departureDate,
    double radiusKm = 5.0,
  }) async {
    try {
      // Rango de fecha: desde inicio del día hasta fin del día
      final startOfDay = DateTime(
        departureDate.year,
        departureDate.month,
        departureDate.day,
      );
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Query Firestore: viajes scheduled del día con asientos disponibles
      final querySnapshot = await _firestore
          .collection(_tripsCollection)
          .where('status', isEqualTo: 'scheduled')
          .where('departureTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('departureTime',
              isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      // Filtro client-side: proximidad geográfica + asientos disponibles
      final results = <TripModel>[];

      for (final doc in querySnapshot.docs) {
        final trip = TripModel.fromFirestore(doc);

        // Saltar viajes sin asientos
        if (trip.availableSeats <= 0) continue;

        // Calcular distancia del origen del viaje al origen del pasajero
        final originDistance = _haversineDistance(
          trip.origin.latitude,
          trip.origin.longitude,
          originLat,
          originLng,
        );

        // Calcular distancia del destino del viaje al destino del pasajero
        final destDistance = _haversineDistance(
          trip.destination.latitude,
          trip.destination.longitude,
          destLat,
          destLng,
        );

        // Ambos deben estar dentro del radio
        if (originDistance <= radiusKm && destDistance <= radiusKm) {
          results.add(trip);
        }
      }

      // Ordenar por hora de salida más cercana
      results.sort((a, b) => a.departureTime.compareTo(b.departureTime));

      return results;
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al buscar viajes: $e');
    }
  }

  // ==================== Gestión de Pasajeros ====================

  /// Solicitar unirse a un viaje (lado pasajero)
  ///
  /// Agrega un TripPassenger con status 'pending' al array de passengers
  /// y decrementa availableSeats
  Future<void> requestToJoin(String tripId, TripPassenger passenger) async {
    try {
      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .update({
        'passengers': FieldValue.arrayUnion([passenger.toJson()]),
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al solicitar viaje: $e');
    }
  }

  /// Aceptar pasajero (lado conductor)
  ///
  /// Cambia status del pasajero a 'accepted' y decrementa availableSeats
  Future<void> acceptPassenger(String tripId, String passengerId) async {
    try {
      final trip = await getTrip(tripId);
      if (trip == null) throw Exception('Viaje no encontrado');

      final updatedPassengers = trip.passengers.map((p) {
        if (p.userId == passengerId && p.status == 'pending') {
          return p.copyWith(status: 'accepted');
        }
        return p;
      }).toList();

      final newAvailableSeats = trip.totalCapacity -
          updatedPassengers
              .where((p) => p.status == 'accepted' || p.status == 'picked_up')
              .length;

      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .update({
        'passengers': updatedPassengers.map((p) => p.toJson()).toList(),
        'availableSeats': newAvailableSeats,
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al aceptar pasajero: $e');
    }
  }

  /// Rechazar pasajero (lado conductor)
  ///
  /// Cambia status del pasajero a 'rejected' con razón opcional
  Future<void> rejectPassenger(
    String tripId,
    String passengerId, {
    String? reason,
  }) async {
    try {
      final trip = await getTrip(tripId);
      if (trip == null) throw Exception('Viaje no encontrado');

      final updatedPassengers = trip.passengers.map((p) {
        if (p.userId == passengerId && p.status == 'pending') {
          return p.copyWith(
            status: 'rejected',
            rejectionReason: reason,
          );
        }
        return p;
      }).toList();

      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .update({
        'passengers': updatedPassengers.map((p) => p.toJson()).toList(),
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al rechazar pasajero: $e');
    }
  }

  /// Iniciar viaje (conductor comienza la ruta)
  Future<void> startTrip(String tripId) async {
    try {
      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .update({
        'status': 'active',
        'startedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al iniciar viaje: $e');
    }
  }

  /// Completar viaje
  Future<void> completeTrip(String tripId) async {
    try {
      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .update({
        'status': 'completed',
        'completedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al completar viaje: $e');
    }
  }

  /// Actualizar estado de un pasajero
  ///
  /// Estados válidos: 'picked_up', 'no_show', 'dropped_off'
  /// - picked_up: El pasajero subió al vehículo
  /// - no_show: El pasajero no apareció en el punto de recogida
  /// - dropped_off: El pasajero llegó a su destino
  Future<void> updatePassengerStatus(
    String tripId,
    String passengerId,
    String newStatus,
  ) async {
    try {
      final trip = await getTrip(tripId);
      if (trip == null) throw Exception('Viaje no encontrado');

      final updatedPassengers = trip.passengers.map((p) {
        if (p.userId == passengerId) {
          return p.copyWith(status: newStatus);
        }
        return p;
      }).toList();

      // Si el pasajero no apareció, liberar el asiento
      int newAvailableSeats = trip.availableSeats;
      if (newStatus == 'no_show') {
        newAvailableSeats = trip.totalCapacity -
            updatedPassengers
                .where((p) => p.status == 'accepted' || p.status == 'picked_up')
                .length;
      }

      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .update({
        'passengers': updatedPassengers.map((p) => p.toJson()).toList(),
        'availableSeats': newAvailableSeats,
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al actualizar estado del pasajero: $e');
    }
  }

  // ==================== Utilidades ====================

  /// Fórmula de Haversine para calcular distancia entre dos coordenadas
  ///
  /// Retorna distancia en kilómetros
  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // Radio de la Tierra en km

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
        return 'Viaje no encontrado';
      case 'already-exists':
        return 'El viaje ya existe';
      case 'unavailable':
        return 'Servicio no disponible. Intenta más tarde.';
      case 'deadline-exceeded':
        return 'Tiempo de espera agotado';
      case 'cancelled':
        return 'Operación cancelada';
      default:
        return e.message ?? 'Error de base de datos';
    }
  }
}
