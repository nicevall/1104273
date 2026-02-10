// lib/data/services/trips_service.dart
// Servicio para operaciones CRUD de viajes en Firestore

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
  /// Cancela el viaje y limpia todas las ride_requests asociadas
  Future<void> cancelTrip(String tripId) async {
    try {
      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .update({
        'status': 'cancelled',
        'completedAt': Timestamp.now(),
      });

      // Limpiar ride_requests asociadas a este viaje
      await _cleanupRideRequests(tripId, 'cancelled');
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

  /// Actualizar estado de pago de un pasajero
  ///
  /// [paymentNote] opcional: razón de falta de pago (cuando status = 'unpaid')
  Future<void> updatePassengerPaymentStatus(
    String tripId,
    String passengerId,
    String newPaymentStatus, {
    String? paymentNote,
  }) async {
    try {
      final tripDoc = await _firestore.collection(_tripsCollection).doc(tripId).get();
      if (!tripDoc.exists) return;

      final tripData = tripDoc.data()!;
      final passengers = (tripData['passengers'] as List<dynamic>)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();

      final idx = passengers.indexWhere((p) => p['userId'] == passengerId);
      if (idx >= 0) {
        passengers[idx]['paymentStatus'] = newPaymentStatus;
        if (paymentNote != null) {
          passengers[idx]['paymentNote'] = paymentNote;
        }
        await _firestore.collection(_tripsCollection).doc(tripId).update({
          'passengers': passengers,
        });
      }
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al actualizar pago: $e');
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
    // Validar que el pasajero tenga userId
    if (passenger.userId.isEmpty) {
      debugPrint('⚠️ requestToJoin: ignorando pasajero con userId vacío');
      throw Exception('No se puede agregar pasajero sin userId');
    }

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
        'status': 'in_progress',
        'startedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al iniciar viaje: $e');
    }
  }

  /// Actualizar ubicación del conductor en tiempo real
  ///
  /// Solo actualiza 3 campos (eficiente para Firestore)
  /// Llamar cada ~10 segundos durante viaje activo
  Future<void> updateDriverLocation(
    String tripId, {
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .update({
        'driverLatitude': latitude,
        'driverLongitude': longitude,
        'driverLocationUpdatedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al actualizar ubicación del conductor: $e');
    }
  }

  /// Completar viaje y limpiar ride_requests asociadas
  Future<void> completeTrip(String tripId) async {
    try {
      await _firestore
          .collection(_tripsCollection)
          .doc(tripId)
          .update({
        'status': 'completed',
        'completedAt': Timestamp.now(),
      });

      // Limpiar ride_requests asociadas a este viaje
      await _cleanupRideRequests(tripId, 'completed');
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al completar viaje: $e');
    }
  }

  /// Limpiar TODAS las ride_requests asociadas a un viaje
  /// Busca por tripId Y por passengerId de cada pasajero
  Future<void> _cleanupRideRequests(String tripId, String newStatus) async {
    try {
      // 1. Buscar ride_requests que referencian este tripId
      final byTripId = await _firestore
          .collection('ride_requests')
          .where('tripId', isEqualTo: tripId)
          .where('status', whereIn: ['searching', 'reviewing', 'accepted'])
          .get();

      for (final doc in byTripId.docs) {
        await doc.reference.update({
          'status': newStatus,
          'completedAt': Timestamp.now(),
        });
      }

      // 2. Buscar por passengerId de los pasajeros del viaje
      final tripDoc = await _firestore.collection(_tripsCollection).doc(tripId).get();
      if (tripDoc.exists) {
        final passengers = tripDoc.data()?['passengers'] as List<dynamic>? ?? [];
        for (final p in passengers) {
          final pMap = p as Map<String, dynamic>;
          final passengerId = pMap['userId'] as String? ?? '';
          if (passengerId.isEmpty) continue;

          final byPassenger = await _firestore
              .collection('ride_requests')
              .where('passengerId', isEqualTo: passengerId)
              .where('status', whereIn: ['searching', 'reviewing', 'accepted'])
              .get();

          for (final doc in byPassenger.docs) {
            await doc.reference.update({
              'status': newStatus,
              'completedAt': Timestamp.now(),
            });
          }
        }
      }

      debugPrint('🧹 Limpieza ride_requests para trip $tripId ($newStatus)');
    } catch (e) {
      // No lanzar — la limpieza es best-effort
      debugPrint('⚠️ Error limpiando ride_requests: $e');
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

      // Limpiar ride_request cuando el pasajero sale del viaje
      if (newStatus == 'no_show' || newStatus == 'cancelled' || newStatus == 'dropped_off') {
        _cleanupPassengerRideRequest(passengerId, newStatus == 'dropped_off' ? 'completed' : 'cancelled');
      }
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al actualizar estado del pasajero: $e');
    }
  }

  // ==================== Taxímetro ====================

  /// Iniciar taxímetro para un pasajero (al marcar picked_up)
  ///
  /// Registra: pickedUpAt, pickupLatitude, pickupLongitude, isNightTariff
  /// La tarifa se fija al momento del pickup y no cambia durante el viaje
  Future<void> startPassengerMeter(
    String tripId,
    String passengerId, {
    required double pickupLatitude,
    required double pickupLongitude,
    required bool isNightTariff,
  }) async {
    try {
      final trip = await getTrip(tripId);
      if (trip == null) throw Exception('Viaje no encontrado');

      final updatedPassengers = trip.passengers.map((p) {
        if (p.userId == passengerId) {
          return p.copyWith(
            pickedUpAt: DateTime.now(),
            pickupLatitude: pickupLatitude,
            pickupLongitude: pickupLongitude,
            isNightTariff: isNightTariff,
            meterFare: isNightTariff ? 0.50 : 0.40, // Arranque inicial
            meterDistanceKm: 0.0,
            meterWaitMinutes: 0.0,
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
      throw Exception('Error al iniciar taxímetro: $e');
    }
  }

  /// Sincronizar datos del taxímetro a Firestore (cada ~30 seg)
  ///
  /// Actualiza: meterDistanceKm, meterWaitMinutes, meterFare, meterLastUpdated
  /// El pasajero lee estos valores desde su app para ver la tarifa en tiempo real
  Future<void> updatePassengerMeter(
    String tripId,
    String passengerId, {
    required double meterDistanceKm,
    required double meterWaitMinutes,
    required double meterFare,
    double discountPercent = 0.0,
    double fareBeforeDiscount = 0.0,
  }) async {
    try {
      final trip = await getTrip(tripId);
      if (trip == null) return;

      final updatedPassengers = trip.passengers.map((p) {
        if (p.userId == passengerId) {
          return p.copyWith(
            meterDistanceKm: meterDistanceKm,
            meterWaitMinutes: meterWaitMinutes,
            meterFare: meterFare,
            meterLastUpdated: DateTime.now(),
            discountPercent: discountPercent,
            fareBeforeDiscount: fareBeforeDiscount,
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
      // Silenciar errores de sync — no es crítico si falla uno
      debugPrint('Error al sincronizar taxímetro: $e');
    }
  }

  /// Bajar pasajero — congelar tarifa final del taxímetro
  ///
  /// Cambia status a 'dropped_off', fija price = finalFare,
  /// registra ubicación y hora de bajada
  Future<void> dropOffPassenger(
    String tripId,
    String passengerId, {
    required double finalFare,
    required double dropoffLatitude,
    required double dropoffLongitude,
    required double totalDistanceKm,
    required double totalWaitMinutes,
  }) async {
    try {
      final trip = await getTrip(tripId);
      if (trip == null) throw Exception('Viaje no encontrado');

      final updatedPassengers = trip.passengers.map((p) {
        if (p.userId == passengerId) {
          return p.copyWith(
            status: 'dropped_off',
            price: finalFare,
            droppedOffAt: DateTime.now(),
            dropoffLatitude: dropoffLatitude,
            dropoffLongitude: dropoffLongitude,
            meterDistanceKm: totalDistanceKm,
            meterWaitMinutes: totalWaitMinutes,
            meterFare: finalFare,
            meterLastUpdated: DateTime.now(),
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

      // Limpiar ride_request del pasajero que fue bajado
      _cleanupPassengerRideRequest(passengerId, 'completed');
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al bajar pasajero: $e');
    }
  }

  /// Limpiar ride_request de un pasajero específico
  Future<void> _cleanupPassengerRideRequest(String passengerId, String newStatus) async {
    try {
      final snap = await _firestore
          .collection('ride_requests')
          .where('passengerId', isEqualTo: passengerId)
          .where('status', whereIn: ['searching', 'reviewing', 'accepted'])
          .get();

      for (final doc in snap.docs) {
        await doc.reference.update({
          'status': newStatus,
          'completedAt': Timestamp.now(),
        });
      }
      if (snap.docs.isNotEmpty) {
        debugPrint('🧹 Limpieza ride_request de pasajero $passengerId ($newStatus)');
      }
    } catch (e) {
      debugPrint('⚠️ Error limpiando ride_request del pasajero: $e');
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

  // ==================== Destinos Recientes ====================

  /// Obtener últimos destinos únicos del pasajero (para "recientes" en home)
  ///
  /// Consulta ride_requests completadas → fetch trips → deduplica por nombre
  Future<List<Map<String, dynamic>>> getRecentPassengerDestinations(
    String passengerId, {
    int limit = 5,
  }) async {
    try {
      // 1. Query ride_requests completadas del pasajero
      final reqSnap = await _firestore
          .collection('ride_requests')
          .where('passengerId', isEqualTo: passengerId)
          .where('status', isEqualTo: 'completed')
          .get();

      // 2. Extraer tripIds únicos
      final tripIds = reqSnap.docs
          .map((d) => d.data()['tripId'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet();

      if (tripIds.isEmpty) return [];

      // 3. Fetch trips
      final trips = <TripModel>[];
      for (final tripId in tripIds) {
        try {
          final doc =
              await _firestore.collection(_tripsCollection).doc(tripId).get();
          if (doc.exists) {
            trips.add(TripModel.fromFirestore(doc));
          }
        } catch (_) {
          // Skip trips que no se pueden cargar
        }
      }

      // 4. Ordenar por fecha más reciente
      trips.sort((a, b) {
        final aTime = a.completedAt ?? a.departureTime;
        final bTime = b.completedAt ?? b.departureTime;
        return bTime.compareTo(aTime);
      });

      // 5. Deduplicar por nombre de destino (quedarse con el más reciente)
      final seen = <String>{};
      final results = <Map<String, dynamic>>[];
      for (final trip in trips) {
        final key = trip.destination.name.toLowerCase().trim();
        if (seen.contains(key)) continue;
        seen.add(key);
        results.add({
          'name': trip.destination.name,
          'address': trip.destination.address,
          'latitude': trip.destination.latitude,
          'longitude': trip.destination.longitude,
        });
        if (results.length >= limit) break;
      }
      return results;
    } catch (e) {
      debugPrint('Error cargando destinos recientes: $e');
      return [];
    }
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
