// lib/data/services/rating_service.dart
// Servicio para guardar y consultar calificaciones en Firestore

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class RatingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _ratingsCollection = 'ratings';
  static const String _usersCollection = 'users';

  /// Enviar una calificación
  /// Escribe a la colección 'ratings' y actualiza el promedio del usuario calificado
  Future<void> submitRating({
    required String tripId,
    required String raterId,
    required String ratedUserId,
    required String raterRole, // 'pasajero' o 'conductor'
    required int stars,
    required List<String> tags,
    String? comment,
  }) async {
    try {
      // 1. Escribir la calificación
      await _firestore.collection(_ratingsCollection).add({
        'tripId': tripId,
        'raterId': raterId,
        'ratedUserId': ratedUserId,
        'raterRole': raterRole,
        'stars': stars,
        'tags': tags,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('⭐ Calificación enviada: $stars estrellas para $ratedUserId');

      // 2. Actualizar promedio del usuario calificado
      await _updateUserAverageRating(ratedUserId);
    } catch (e) {
      debugPrint('Error al enviar calificación: $e');
      rethrow;
    }
  }

  /// Recalcular el promedio de calificación de un usuario
  Future<void> _updateUserAverageRating(String userId) async {
    try {
      final ratingsSnapshot = await _firestore
          .collection(_ratingsCollection)
          .where('ratedUserId', isEqualTo: userId)
          .get();

      if (ratingsSnapshot.docs.isEmpty) return;

      double totalStars = 0;
      int count = 0;

      for (final doc in ratingsSnapshot.docs) {
        final stars = doc.data()['stars'] as int?;
        if (stars != null) {
          totalStars += stars;
          count++;
        }
      }

      if (count == 0) return;

      final average = totalStars / count;

      await _firestore.collection(_usersCollection).doc(userId).update({
        'rating': double.parse(average.toStringAsFixed(2)),
        'totalRatings': count,
      });

      debugPrint('⭐ Rating actualizado: $average ($count calificaciones)');
    } catch (e) {
      debugPrint('Error al actualizar promedio de rating: $e');
    }
  }

  /// Verificar si ya calificó este viaje
  Future<bool> hasRated(String tripId, String raterId) async {
    try {
      final snap = await _firestore
          .collection(_ratingsCollection)
          .where('tripId', isEqualTo: tripId)
          .where('raterId', isEqualTo: raterId)
          .limit(1)
          .get();

      return snap.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error verificando calificación: $e');
      return false;
    }
  }
}
