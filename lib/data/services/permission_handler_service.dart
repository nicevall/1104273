import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Servicio para manejar permisos del dispositivo
/// Solicita permisos de cámara, galería y ubicación
/// Muestra diálogos educativos antes de solicitar permisos
class PermissionHandlerService {
  /// Solicitar permiso de cámara
  ///
  /// Retorna true si el permiso fue otorgado
  /// Muestra configuración si el permiso fue denegado permanentemente
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      // Usuario negó permanentemente, abrir configuración
      await openAppSettings();
      return false;
    }

    return false;
  }

  /// Solicitar permiso de galería/fotos
  ///
  /// En Android 13+: photos, en versiones anteriores: storage
  Future<bool> requestGalleryPermission() async {
    // Android 13+ usa Permission.photos
    // Android < 13 usa Permission.storage
    Permission permission;

    // Determinar qué permiso usar según versión Android
    if (await Permission.photos.isPermanentlyDenied) {
      permission = Permission.photos;
    } else {
      permission = Permission.storage;
    }

    final status = await permission.request();

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  /// Solicitar permiso de ubicación
  ///
  /// Solicita ubicación mientras usa la app (whenInUse)
  /// Retorna true si el permiso fue otorgado
  Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  /// Solicitar ubicación en segundo plano (opcional)
  ///
  /// Necesario para tracking GPS en tiempo real
  /// IMPORTANTE: Solo solicitar cuando el usuario esté en un viaje activo
  Future<bool> requestBackgroundLocationPermission() async {
    // Primero verificar que tenga permiso de ubicación normal
    final locationStatus = await Permission.location.status;

    if (!locationStatus.isGranted) {
      return false;
    }

    // Luego solicitar ubicación en segundo plano
    final status = await Permission.locationAlways.request();

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  /// Verificar si tiene permiso específico
  ///
  /// Útil para verificar antes de mostrar funcionalidad
  Future<bool> hasPermission(Permission permission) async {
    final status = await permission.status;
    return status.isGranted;
  }

  /// Verificar estado de permiso
  ///
  /// Retorna el estado actual del permiso
  Future<PermissionStatus> getPermissionStatus(Permission permission) async {
    return await permission.status;
  }

  /// Abrir configuración de la app
  ///
  /// Útil cuando el usuario negó permisos permanentemente
  Future<void> openAppSettings() async {
    await openAppSettings();
  }

  /// Mostrar bottom sheet educativo antes de solicitar permiso
  ///
  /// Explica por qué la app necesita el permiso
  /// Mejora tasa de aceptación de permisos
  ///
  /// Retorna true si el usuario aceptó el permiso después del diálogo
  Future<bool> showPermissionBottomSheet({
    required BuildContext context,
    required String title,
    required String message,
    required Permission permission,
    String? icon,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icono
            if (icon != null)
              Text(
                icon,
                style: const TextStyle(fontSize: 48),
              ),
            const SizedBox(height: 16),

            // Título
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Mensaje
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Botones
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Permitir'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // Si el usuario aceptó el diálogo, solicitar permiso
    if (result == true) {
      final status = await permission.request();
      return status.isGranted;
    }

    return false;
  }

  /// Verificar y solicitar permiso de cámara con diálogo educativo
  Future<bool> requestCameraWithDialog(BuildContext context) async {
    // Verificar si ya tiene el permiso
    if (await hasPermission(Permission.camera)) {
      return true;
    }

    // Mostrar diálogo educativo
    return await showPermissionBottomSheet(
      context: context,
      title: 'Permiso de Cámara',
      message: 'UniRide necesita acceso a tu cámara para tomar fotos de tu vehículo y licencia de conducir.',
      permission: Permission.camera,
      icon: '📷',
    );
  }

  /// Verificar y solicitar permiso de galería con diálogo educativo
  Future<bool> requestGalleryWithDialog(BuildContext context) async {
    final permission = await _getGalleryPermission();

    // Verificar si ya tiene el permiso
    if (await hasPermission(permission)) {
      return true;
    }

    // Mostrar diálogo educativo
    final accepted = await showPermissionBottomSheet(
      context: context,
      title: 'Permiso de Galería',
      message: 'UniRide necesita acceso a tus fotos para que puedas seleccionar imágenes de tu vehículo.',
      permission: permission,
      icon: '🖼️',
    );

    return accepted;
  }

  /// Verificar y solicitar permiso de ubicación con diálogo educativo
  Future<bool> requestLocationWithDialog(BuildContext context) async {
    // Verificar si ya tiene el permiso
    if (await hasPermission(Permission.location)) {
      return true;
    }

    // Mostrar diálogo educativo
    return await showPermissionBottomSheet(
      context: context,
      title: 'Permiso de Ubicación',
      message: 'UniRide necesita tu ubicación para mostrarte viajes cercanos y calcular rutas.',
      permission: Permission.location,
      icon: '📍',
    );
  }

  /// Obtener el permiso de galería correcto según versión Android
  Future<Permission> _getGalleryPermission() async {
    // Android 13+ (API 33+) usa Permission.photos
    // Android < 13 usa Permission.storage
    if (await Permission.photos.isPermanentlyDenied ||
        await Permission.photos.isGranted) {
      return Permission.photos;
    }
    return Permission.storage;
  }

  /// Verificar todos los permisos necesarios para conductor
  ///
  /// Retorna mapa con estado de cada permiso
  Future<Map<String, bool>> checkDriverPermissions() async {
    return {
      'camera': await hasPermission(Permission.camera),
      'gallery': await hasPermission(await _getGalleryPermission()),
      'location': await hasPermission(Permission.location),
    };
  }

  /// Verificar todos los permisos necesarios para pasajero
  ///
  /// Solo necesita ubicación
  Future<Map<String, bool>> checkPassengerPermissions() async {
    return {
      'location': await hasPermission(Permission.location),
    };
  }
}
