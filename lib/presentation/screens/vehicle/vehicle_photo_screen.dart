import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/services/document_verification_service.dart';
import '../../widgets/common/custom_button.dart';

/// Pantalla para capturar foto del vehículo
/// Verifica que sea una foto real (anti-spoofing)
class VehiclePhotoScreen extends StatefulWidget {
  final String userId;
  final String role;
  final String vehicleOwnership;
  final String driverRelation;
  final String matriculaPhotoPath;
  final String licensePhotoPath;
  final Map<String, dynamic>? licenseData;
  final Map<String, String> vehicleData;

  const VehiclePhotoScreen({
    super.key,
    required this.userId,
    required this.role,
    required this.vehicleOwnership,
    required this.driverRelation,
    required this.matriculaPhotoPath,
    required this.licensePhotoPath,
    this.licenseData,
    required this.vehicleData,
  });

  @override
  State<VehiclePhotoScreen> createState() => _VehiclePhotoScreenState();
}

class _VehiclePhotoScreenState extends State<VehiclePhotoScreen> {
  final _imagePicker = ImagePicker();
  final _documentService = DocumentVerificationService();

  File? _photo;
  bool _isVerifying = false;
  bool _isVerified = false;

  @override
  void dispose() {
    _documentService.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final status = await Permission.camera.status;

    if (status.isDenied) {
      final result = await Permission.camera.request();
      if (result.isDenied) {
        _showPermissionDeniedDialog();
        return;
      }
    }

    if (status.isPermanentlyDenied) {
      _showPermissionPermanentlyDeniedDialog();
      return;
    }

    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );

    if (image != null) {
      setState(() {
        _photo = File(image.path);
        _isVerifying = true;
        _isVerified = false;
      });

      await _verifyPhoto(File(image.path));
    }
  }

  Future<void> _verifyPhoto(File imageFile) async {
    try {
      // Verificar anti-spoofing (que no sea foto de pantalla)
      final isReal = await _documentService.detectPhotoOfPhoto(imageFile);

      if (!mounted) return;

      if (isReal) {
        setState(() {
          _isVerifying = false;
          _isVerified = true;
        });
      } else {
        setState(() {
          _isVerifying = false;
          _isVerified = false;
          _photo = null;
        });

        _showRetakeDialog('Parece ser una foto de pantalla o imagen impresa');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _isVerified = false;
          _photo = null;
        });
        _showRetakeDialog('Error al verificar la imagen');
      }
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.camera_alt, color: AppColors.warning, size: 48),
        title: const Text('Permiso de cámara requerido'),
        content: const Text(
          'Para tomar foto del vehículo, necesitamos acceso a la cámara.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _showPermissionPermanentlyDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.camera_alt, color: AppColors.error, size: 48),
        title: const Text('Cámara bloqueada'),
        content: const Text(
          'El permiso de cámara fue denegado. Habilítalo manualmente en configuración.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Abrir configuración'),
          ),
        ],
      ),
    );
  }

  void _showRetakeDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 48),
        title: const Text('Foto no válida'),
        content: Text(
          '$message\n\nAsegúrate de que:\n'
          '• Sea una foto directa del vehículo\n'
          '• No sea una foto de pantalla\n'
          '• Haya buena iluminación\n'
          '• El vehículo sea claramente visible',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _takePhoto();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Volver a tomar foto'),
          ),
        ],
      ),
    );
  }

  void _handleContinue() {
    if (!_isVerified) return;

    context.push('/register/vehicle/summary', extra: {
      'userId': widget.userId,
      'role': widget.role,
      'vehicleOwnership': widget.vehicleOwnership,
      'driverRelation': widget.driverRelation,
      'matriculaPhoto': widget.matriculaPhotoPath,
      'licensePhoto': widget.licensePhotoPath,
      'licenseData': widget.licenseData,
      'vehicleData': widget.vehicleData,
      'vehiclePhoto': _photo!.path,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Foto del vehículo',
          style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProgressIndicator(3, 4),
              const SizedBox(height: AppDimensions.spacingL),

              Text('Foto de tu vehículo', style: AppTextStyles.h1),
              const SizedBox(height: AppDimensions.spacingS),
              Text(
                'Toma una foto clara del exterior de tu vehículo',
                style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppDimensions.spacingL),

              Expanded(child: _buildPhotoArea()),
              const SizedBox(height: AppDimensions.spacingL),

              // Tips
              _buildTipsCard(),
              const SizedBox(height: AppDimensions.spacingL),

              if (_photo == null)
                CustomButton.primary(
                  text: 'Tomar foto',
                  onPressed: _takePhoto,
                  icon: Icons.camera_alt,
                )
              else if (_isVerified)
                CustomButton.primary(
                  text: 'Continuar',
                  onPressed: _handleContinue,
                )
              else if (!_isVerifying)
                CustomButton.primary(
                  text: 'Volver a tomar foto',
                  onPressed: _takePhoto,
                  icon: Icons.refresh,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(int current, int total) {
    return Row(
      children: List.generate(total, (index) {
        final isCompleted = index < current;
        final isCurrent = index == current - 1;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index < total - 1 ? 8 : 0),
            decoration: BoxDecoration(
              color: isCompleted || isCurrent ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPhotoArea() {
    return GestureDetector(
      onTap: _isVerifying ? null : _takePhoto,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          border: Border.all(
            color: _isVerified ? AppColors.success : AppColors.border,
            width: 2,
          ),
        ),
        child: _photo != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimensions.borderRadius - 2),
                    child: Image.file(_photo!, fit: BoxFit.cover),
                  ),
                  if (_isVerifying)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(AppDimensions.borderRadius - 2),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'Verificando foto...',
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_isVerified)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('Verificado', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.directions_car, size: 40, color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Toca para tomar foto',
                    style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTipsCard() {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.paddingM),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: AppColors.info, size: 20),
              const SizedBox(width: 8),
              Text(
                'Consejos para la foto',
                style: AppTextStyles.label.copyWith(color: AppColors.info),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• Incluye la placa visible\n'
            '• Toma la foto de frente o 3/4\n'
            '• Asegúrate de buena iluminación',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
