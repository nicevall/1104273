// lib/presentation/widgets/home/notification_permission_banner.dart
// Banner de permisos de notificación estilo Uber
// Muestra cuando las notificaciones están deshabilitadas
// Detecta cambios cuando el usuario regresa a la app

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/services/notification_service.dart';

class NotificationPermissionBanner extends StatefulWidget {
  final VoidCallback? onPermissionGranted;

  const NotificationPermissionBanner({
    super.key,
    this.onPermissionGranted,
  });

  @override
  State<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends State<NotificationPermissionBanner> with WidgetsBindingObserver {
  bool _isVisible = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkNotificationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkNotificationStatus();
    }
  }

  Future<void> _checkNotificationStatus() async {
    try {
      final granted = await NotificationService().isPermissionGranted();
      if (mounted) {
        final wasVisible = _isVisible;
        setState(() {
          _isVisible = !granted;
          _isChecking = false;
        });
        // Si antes estaba visible y ahora no → se concedió el permiso
        if (wasVisible && granted) {
          widget.onPermissionGranted?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVisible = true;
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    final granted = await NotificationService().requestPermission();
    if (granted && mounted) {
      setState(() => _isVisible = false);
      widget.onPermissionGranted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking || !_isVisible) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _requestNotificationPermission,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.info.withOpacity(0.12),
          border: Border(
            bottom: BorderSide(
              color: AppColors.info.withOpacity(0.3),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_off_outlined,
                size: 18,
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notificaciones desactivadas',
                    style: AppTextStyles.body2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Toca para activar y no perderte viajes',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.info,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.info,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
