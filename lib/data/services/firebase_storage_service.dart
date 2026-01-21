import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

/// Servicio para subir archivos a Firebase Storage
/// Maneja fotos de perfil, vehículos y licencias
class FirebaseStorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Rutas de carpetas en Storage
  static const String _profilePhotosPath = 'profile_photos';
  static const String _vehiclePhotosPath = 'vehicle_photos';
  static const String _licensePhotosPath = 'license_photos';

  /// Subir foto de perfil del usuario
  ///
  /// Sube a: profile_photos/{userId}/profile.jpg
  /// Retorna URL de descarga
  /// Sobrescribe foto anterior si existe
  Future<String> uploadProfilePhoto({
    required String userId,
    required File imageFile,
  }) async {
    try {
      // Generar ruta única
      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('$_profilePhotosPath/$userId/$fileName');

      // Configurar metadata
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'userId': userId,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      // Subir archivo
      final uploadTask = ref.putFile(imageFile, metadata);

      // Esperar a que complete
      final snapshot = await uploadTask.whenComplete(() {});

      // Obtener URL de descarga
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } on FirebaseException catch (e) {
      throw _handleStorageError(e);
    } catch (e) {
      throw Exception('Error al subir foto de perfil: $e');
    }
  }

  /// Subir foto del vehículo
  ///
  /// Sube a: vehicle_photos/{userId}/vehicle_{timestamp}.jpg
  /// Retorna URL de descarga
  Future<String> uploadVehiclePhoto({
    required String userId,
    required File imageFile,
  }) async {
    try {
      final fileName = 'vehicle_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('$_vehiclePhotosPath/$userId/$fileName');

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'userId': userId,
          'uploadedAt': DateTime.now().toIso8601String(),
          'type': 'vehicle',
        },
      );

      final uploadTask = ref.putFile(imageFile, metadata);
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } on FirebaseException catch (e) {
      throw _handleStorageError(e);
    } catch (e) {
      throw Exception('Error al subir foto de vehículo: $e');
    }
  }

  /// Subir foto de licencia de conducir
  ///
  /// Sube a: license_photos/{userId}/license_{timestamp}.jpg
  /// Retorna URL de descarga
  /// IMPORTANTE: Datos sensibles, debe tener permisos restrictivos
  Future<String> uploadLicensePhoto({
    required String userId,
    required File imageFile,
  }) async {
    try {
      final fileName = 'license_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('$_licensePhotosPath/$userId/$fileName');

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'userId': userId,
          'uploadedAt': DateTime.now().toIso8601String(),
          'type': 'license',
          'sensitive': 'true', // Marcador para datos sensibles
        },
      );

      final uploadTask = ref.putFile(imageFile, metadata);
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } on FirebaseException catch (e) {
      throw _handleStorageError(e);
    } catch (e) {
      throw Exception('Error al subir foto de licencia: $e');
    }
  }

  /// Eliminar foto por URL
  ///
  /// Útil para eliminar fotos antiguas al actualizar
  Future<void> deletePhoto(String photoUrl) async {
    try {
      // Extraer ruta del archivo desde la URL
      final ref = _storage.refFromURL(photoUrl);
      await ref.delete();
    } on FirebaseException catch (e) {
      // Si el archivo no existe, no lanzar error
      if (e.code != 'object-not-found') {
        throw _handleStorageError(e);
      }
    } catch (e) {
      throw Exception('Error al eliminar foto: $e');
    }
  }

  /// Eliminar todas las fotos de perfil del usuario
  ///
  /// Útil al eliminar cuenta
  Future<void> deleteAllUserPhotos(String userId) async {
    try {
      // Eliminar fotos de perfil
      final profileRef = _storage.ref().child('$_profilePhotosPath/$userId');
      await _deleteFolder(profileRef);

      // Eliminar fotos de vehículo
      final vehicleRef = _storage.ref().child('$_vehiclePhotosPath/$userId');
      await _deleteFolder(vehicleRef);

      // Eliminar fotos de licencia
      final licenseRef = _storage.ref().child('$_licensePhotosPath/$userId');
      await _deleteFolder(licenseRef);
    } catch (e) {
      throw Exception('Error al eliminar fotos del usuario: $e');
    }
  }

  /// Obtener metadata de una foto
  Future<FullMetadata> getPhotoMetadata(String photoUrl) async {
    try {
      final ref = _storage.refFromURL(photoUrl);
      return await ref.getMetadata();
    } on FirebaseException catch (e) {
      throw _handleStorageError(e);
    } catch (e) {
      throw Exception('Error al obtener metadata: $e');
    }
  }

  /// Eliminar carpeta completa (helper privado)
  Future<void> _deleteFolder(Reference folderRef) async {
    try {
      final listResult = await folderRef.listAll();

      // Eliminar todos los archivos
      for (final fileRef in listResult.items) {
        await fileRef.delete();
      }

      // Eliminar subcarpetas recursivamente
      for (final subfolderRef in listResult.prefixes) {
        await _deleteFolder(subfolderRef);
      }
    } catch (e) {
      // Si la carpeta no existe, no hacer nada
      if (e is FirebaseException && e.code == 'object-not-found') {
        return;
      }
      rethrow;
    }
  }

  /// Manejo de errores de Storage
  String _handleStorageError(FirebaseException e) {
    switch (e.code) {
      case 'object-not-found':
        return 'Archivo no encontrado';
      case 'unauthorized':
        return 'No autorizado. Inicia sesión nuevamente.';
      case 'canceled':
        return 'Subida cancelada';
      case 'unknown':
        return 'Error desconocido al subir archivo';
      case 'retry-limit-exceeded':
        return 'Tiempo de espera agotado. Intenta de nuevo.';
      case 'invalid-checksum':
        return 'Archivo corrupto. Intenta de nuevo.';
      case 'quota-exceeded':
        return 'Cuota de almacenamiento excedida';
      default:
        return e.message ?? 'Error al subir archivo';
    }
  }
}
