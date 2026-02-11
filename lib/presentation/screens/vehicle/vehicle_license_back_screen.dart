import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/license_data.dart';
import '../../../data/services/document_verification_service.dart';
import '../../widgets/common/custom_button.dart';

/// Pantalla para capturar foto del REVERSO de la licencia de conducir
class VehicleLicenseBackScreen extends StatefulWidget {
  final String userId;
  final String role;
  final String vehicleOwnership;
  final String driverRelation;
  final String matriculaPhotoPath;
  final Map<String, String> vehicleData;
  final String licenseFrontPhotoPath;
  final Map<String, dynamic> licenseFrontData;

  const VehicleLicenseBackScreen({
    super.key,
    required this.userId,
    required this.role,
    required this.vehicleOwnership,
    required this.driverRelation,
    required this.matriculaPhotoPath,
    required this.vehicleData,
    required this.licenseFrontPhotoPath,
    required this.licenseFrontData,
  });

  @override
  State<VehicleLicenseBackScreen> createState() =>
      _VehicleLicenseBackScreenState();
}

class _VehicleLicenseBackScreenState extends State<VehicleLicenseBackScreen> {
  final _imagePicker = ImagePicker();
  final _documentService = DocumentVerificationService();

  File? _photo;
  bool _isVerifying = false;
  bool _isVerified = false;
  LicenseData? _licenseBackData;

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
        _licenseBackData = null;
      });

      await _verifyDocument(File(image.path));
    }
  }

  Future<void> _verifyDocument(File imageFile) async {
    try {
      // Usamos licenseBack para que busque Categoría
      final result = await _documentService.verifyDocument(
        imageFile: imageFile,
        documentType: DocumentType.licenseBack,
      );

      if (!mounted) return;

      if (result.isValid && result.licenseData != null) {
        setState(() {
          _isVerifying = false;
          _isVerified = true;
          _licenseBackData = result.licenseData;
        });
      } else {
        setState(() {
          _isVerifying = false;
          _isVerified = false;
          _photo = null;
        });

        _showRetakeDialog(result.errorMessage ?? 'No se detectó la categoría.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _isVerified = false;
          _photo = null;
        });
        _showRetakeDialog('Error al procesar la imagen');
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
          'Para verificar tu licencia, necesitamos acceso a la cámara.',
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
        icon: const Icon(Icons.warning_amber_rounded,
            color: AppColors.warning, size: 48),
        title: const Text('Reverso no válido'),
        content: Text(
          '$message\n\nAsegúrate de que:\n'
          '• Se vea claramente el "TIPO" o "CATEGORÍA"\n'
          '• Haya buena iluminación\n'
          '• Sea el documento físico',
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
    if (!_isVerified || _licenseBackData == null) return;

    // FUSIONAR DATOS (Frente + Reverso)
    final frontData = widget.licenseFrontData;
    final backData =
        _licenseBackData!.toMap(); // Mapa con categoria, tipoSangre

    // Crear mapa final combinado
    final finalLicenseData = Map<String, dynamic>.from(frontData);
    finalLicenseData['categoria'] = backData['categoria'];
    finalLicenseData['tipo_sangre'] = backData['tipo_sangre'];

    // Enviar TODO al siguiente paso (Foto Vehículo)
    // Nota: Pasamos licenseFrontPhotoPath como la "foto de licencia" principal
    // (o podríamos pasar ambas, pero el RegisterVehicleEvent solo pide licensePhotoUrl singular.
    // Como las deshabilitamos, no importa mucho, pero pasamos la del frente por consistencia).

    context.push('/register/vehicle/photo', extra: {
      'userId': widget.userId,
      'role': widget.role,
      'vehicleOwnership': widget.vehicleOwnership,
      'driverRelation': widget.driverRelation,
      'matriculaPhoto': widget.matriculaPhotoPath,
      'vehicleData': widget.vehicleData,
      'licensePhoto': widget.licenseFrontPhotoPath,
      'licenseData': finalLicenseData,
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
          'Reverso de Licencia',
          style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProgressIndicator(3, 4), // Paso 3 de 4 (aprox)
              const SizedBox(height: AppDimensions.spacingL),

              Text('Reverso de tu licencia', style: AppTextStyles.h1),
              const SizedBox(height: AppDimensions.spacingS),
              Text(
                'Toma una foto del REVERSO donde aparece la CATEGORÍA (Tipo B)',
                style: AppTextStyles.body1
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppDimensions.spacingL),

              Expanded(child: _buildPhotoArea()),
              const SizedBox(height: AppDimensions.spacingL),

              if (_isVerified && _licenseBackData != null) ...[
                _buildLicenseInfoCard(),
                const SizedBox(height: AppDimensions.spacingL),
              ],

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
              color: isCompleted || isCurrent
                  ? AppColors.primary
                  : AppColors.border,
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
                    borderRadius:
                        BorderRadius.circular(AppDimensions.borderRadius - 2),
                    child: Image.file(_photo!, fit: BoxFit.cover),
                  ),
                  if (_isVerifying)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadius - 2),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'Analizando reverso...',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('Verificado',
                                style: TextStyle(color: Colors.white)),
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
                    child: const Icon(Icons.flip_camera_android,
                        size: 40, color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Toca para tomar foto del reverso',
                    style: AppTextStyles.body1
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLicenseInfoCard() {
    final data = _licenseBackData;
    if (data == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppDimensions.paddingM),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                'Datos de Reverso Detectados',
                style: AppTextStyles.label.copyWith(color: AppColors.success),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Mostrar datos extraídos
          if (data.categoria != null)
            _buildLicenseDataRow('Categoría', data.categoria!),
          if (data.tipoSangre != null)
            _buildLicenseDataRow('Tipo sangre', data.tipoSangre!),
        ],
      ),
    );
  }

  Widget _buildLicenseDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
