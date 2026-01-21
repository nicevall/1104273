import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/vehicle_model.dart';

/// Servicio para operaciones con Firestore Database
/// Maneja CRUD de usuarios y vehículos
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Nombres de colecciones
  static const String _usersCollection = 'users';
  static const String _vehiclesCollection = 'vehicles';

  /// Obtener usuario por ID
  ///
  /// Retorna [UserModel] si existe, null si no
  /// Lanza [FirebaseException] si hay error
  Future<UserModel?> getUser(String userId) async {
    try {
      final doc = await _firestore
          .collection(_usersCollection)
          .doc(userId)
          .get();

      if (!doc.exists) {
        return null;
      }

      return UserModel.fromJson(doc.data()!);
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al obtener usuario: $e');
    }
  }

  /// Stream de usuario en tiempo real
  ///
  /// Emite null si el usuario no existe
  /// Útil para actualizar UI en tiempo real
  Stream<UserModel?> getUserStream(String userId) {
    try {
      return _firestore
          .collection(_usersCollection)
          .doc(userId)
          .snapshots()
          .map((doc) {
        if (!doc.exists) return null;
        return UserModel.fromJson(doc.data()!);
      });
    } catch (e) {
      throw Exception('Error en stream de usuario: $e');
    }
  }

  /// Actualizar datos del usuario
  ///
  /// Solo actualiza campos permitidos (no modifica userId, email, createdAt)
  /// Actualiza automáticamente el campo updatedAt
  Future<void> updateUser(UserModel user) async {
    try {
      final data = user.toJson();
      // Actualizar timestamp
      data['updatedAt'] = Timestamp.now();
      // No permitir cambiar userId, email, createdAt
      data.remove('userId');
      data.remove('email');
      data.remove('createdAt');

      await _firestore
          .collection(_usersCollection)
          .doc(user.userId)
          .update(data);
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al actualizar usuario: $e');
    }
  }

  /// Actualizar campos específicos del usuario
  ///
  /// Útil para actualizaciones parciales sin necesidad de UserModel completo
  Future<void> updateUserFields(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    try {
      fields['updatedAt'] = Timestamp.now();

      await _firestore
          .collection(_usersCollection)
          .doc(userId)
          .update(fields);
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al actualizar campos: $e');
    }
  }

  /// Obtener vehículo del usuario
  ///
  /// Busca vehículo donde ownerId == userId
  /// Retorna null si el usuario no tiene vehículo registrado
  Future<VehicleModel?> getUserVehicle(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_vehiclesCollection)
          .where('ownerId', isEqualTo: userId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      return VehicleModel.fromJson(querySnapshot.docs.first.data());
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al obtener vehículo: $e');
    }
  }

  /// Obtener vehículo por ID
  Future<VehicleModel?> getVehicle(String vehicleId) async {
    try {
      final doc = await _firestore
          .collection(_vehiclesCollection)
          .doc(vehicleId)
          .get();

      if (!doc.exists) {
        return null;
      }

      return VehicleModel.fromJson(doc.data()!);
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al obtener vehículo: $e');
    }
  }

  /// Actualizar vehículo
  ///
  /// Solo el dueño puede actualizar (validar en Security Rules)
  Future<void> updateVehicle(VehicleModel vehicle) async {
    try {
      final data = vehicle.toJson();
      data['updatedAt'] = Timestamp.now();
      data.remove('vehicleId');
      data.remove('ownerId');
      data.remove('createdAt');

      await _firestore
          .collection(_vehiclesCollection)
          .doc(vehicle.vehicleId)
          .update(data);
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al actualizar vehículo: $e');
    }
  }

  /// Eliminar vehículo
  ///
  /// Solo el dueño puede eliminar (validar en Security Rules)
  Future<void> deleteVehicle(String vehicleId) async {
    try {
      await _firestore
          .collection(_vehiclesCollection)
          .doc(vehicleId)
          .delete();
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al eliminar vehículo: $e');
    }
  }

  /// Verificar si usuario existe
  Future<bool> userExists(String userId) async {
    try {
      final doc = await _firestore
          .collection(_usersCollection)
          .doc(userId)
          .get();

      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Obtener usuarios por rol (útil para admin)
  ///
  /// Roles: 'pasajero', 'conductor', 'ambos'
  Future<List<UserModel>> getUsersByRole(String role) async {
    try {
      final querySnapshot = await _firestore
          .collection(_usersCollection)
          .where('role', isEqualTo: role)
          .get();

      return querySnapshot.docs
          .map((doc) => UserModel.fromJson(doc.data()))
          .toList();
    } on FirebaseException catch (e) {
      throw _handleFirestoreError(e);
    } catch (e) {
      throw Exception('Error al obtener usuarios: $e');
    }
  }

  /// Manejo de errores de Firestore
  String _handleFirestoreError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permiso denegado';
      case 'not-found':
        return 'Documento no encontrado';
      case 'already-exists':
        return 'El documento ya existe';
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
