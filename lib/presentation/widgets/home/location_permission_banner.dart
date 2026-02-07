// lib/presentation/widgets/home/location_permission_banner.dart
// Banner de permisos de ubicación estilo Uber
// Muestra cuando la ubicación está deshabilitada
// Detecta cambios cuando el usuario regresa a la app

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class LocationPermissionBanner extends StatefulWidget {
  final VoidCallback? onPermissionGranted;
  final VoidCallback? onPermissionDenied;

  const LocationPermissionBanner({
    super.key,
    this.onPermissionGranted,
    this.onPermissionDenied,
  });

  @override
  State<LocationPermissionBanner> createState() => _LocationPermissionBannerState();
}

class _LocationPermissionBannerState extends State<LocationPermissionBanner>
    with WidgetsBindingObserver {
  bool _isVisible = false;
  bool _isChecking = true;
  bool _wasGrantedBefore = false;

  // Tipo de problema: 'permission' o 'service'
  String _issueType = 'permission';

  @override
  void initState() {
    super.initState();
    // Registrar observer para detectar cuando la app vuelve al primer plano
    WidgetsBinding.instance.addObserver(this);
    _checkLocationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Detecta cuando la app cambia de estado (background/foreground)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Cuando la app vuelve al primer plano, verificar permisos
    if (state == AppLifecycleState.resumed) {
      _checkLocationStatus();
    }
  }

  /// Verifica tanto el permiso como si el servicio de ubicación está activo
  Future<void> _checkLocationStatus() async {
    try {
      // Verificar el permiso de ubicación primero
      final permissionStatus = await Permission.location.status;

      // Verificar si el servicio de ubicación está habilitado
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      // Determinar el tipo de problema
      String issueType = 'permission';
      bool shouldShowBanner = false;

      if (!permissionStatus.isGranted) {
        // Falta el permiso
        issueType = 'permission';
        shouldShowBanner = true;
      } else if (!serviceEnabled) {
        // Tiene permiso pero la ubicación del dispositivo está desactivada
        issueType = 'service';
        shouldShowBanner = true;
      }

      if (mounted) {
        final wasVisibleBefore = _isVisible;

        setState(() {
          _isVisible = shouldShowBanner;
          _issueType = issueType;
          _isChecking = false;
        });

        // Si antes estaba concedido y ahora no, notificar
        if (_wasGrantedBefore && shouldShowBanner) {
          widget.onPermissionDenied?.call();
        }

        // Si antes no estaba concedido y ahora sí, notificar
        if (wasVisibleBefore && !shouldShowBanner) {
          _wasGrantedBefore = true;
          widget.onPermissionGranted?.call();
        }

        // Actualizar estado previo
        if (!shouldShowBanner) {
          _wasGrantedBefore = true;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVisible = true;
          _issueType = 'permission';
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _requestLocationPermission() async {
    // Primero verificar si el servicio de ubicación está habilitado
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      // Abrir configuración de ubicación del dispositivo
      await Geolocator.openLocationSettings();
      return;
    }

    // Verificar el estado actual del permiso
    final currentStatus = await Permission.location.status;

    if (currentStatus.isPermanentlyDenied) {
      // Si fue denegado permanentemente, abrir configuración de la app
      await openAppSettings();
    } else {
      // Solicitar permiso nativo de ubicación
      final status = await Permission.location.request();

      if (status.isGranted) {
        if (mounted) {
          setState(() {
            _isVisible = false;
            _wasGrantedBefore = true;
          });
          widget.onPermissionGranted?.call();
        }
      } else if (status.isPermanentlyDenied) {
        // Si fue denegado permanentemente, abrir configuración
        await openAppSettings();
      }
    }
  }

  // Obtener el título según el tipo de problema
  String get _title {
    if (_issueType == 'service') {
      return 'GPS desactivado';
    } else {
      return 'Permiso de ubicación';
    }
  }

  // Obtener la descripción según el tipo de problema
  String get _description {
    if (_issueType == 'service') {
      return 'Activa el GPS de tu dispositivo';
    } else {
      return 'Toca para otorgar permiso';
    }
  }

  // Obtener el icono según el tipo de problema
  IconData get _icon {
    if (_issueType == 'service') {
      return Icons.gps_off;
    } else {
      return Icons.location_disabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking || !_isVisible) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _requestLocationPermission,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.15),
          border: Border(
            bottom: BorderSide(
              color: AppColors.warning.withOpacity(0.3),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _icon,
                size: 18,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: AppTextStyles.body2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _description,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.warning,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
