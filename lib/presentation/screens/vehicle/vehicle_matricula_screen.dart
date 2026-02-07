import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/vehicle_data.dart';
import '../../../data/services/document_verification_service.dart';
import '../../widgets/common/custom_button.dart';

/// Pantalla para capturar foto de la matrícula vehicular
/// Extrae datos mediante OCR: marca, modelo, año, color, placa
class VehicleMatriculaScreen extends StatefulWidget {
  final String userId;
  final String role;
  final String vehicleOwnership;
  final String driverRelation;

  const VehicleMatriculaScreen({
    super.key,
    required this.userId,
    required this.role,
    required this.vehicleOwnership,
    required this.driverRelation,
  });

  @override
  State<VehicleMatriculaScreen> createState() => _VehicleMatriculaScreenState();
}

class _VehicleMatriculaScreenState extends State<VehicleMatriculaScreen> {
  final _imagePicker = ImagePicker();
  final _documentService = DocumentVerificationService();

  File? _photo;
  bool _isVerifying = false;
  bool _isVerified = false;
  String? _errorMessage;

  // Datos extraídos del documento
  VehicleData? _vehicleData;

  @override
  void dispose() {
    _documentService.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    // Verificar permiso de cámara
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

    // Tomar foto
    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );

    if (image != null) {
      setState(() {
        _photo = File(image.path);
        _isVerifying = true;
        _isVerified = false;
        _errorMessage = null;
        _vehicleData = null;
      });

      await _verifyDocument(File(image.path));
    }
  }

  Future<void> _verifyDocument(File imageFile) async {
    try {
      final result = await _documentService.verifyDocument(
        imageFile: imageFile,
        documentType: DocumentType.registration,
      );

      if (!mounted) return;

      if (result.isValid && result.vehicleData != null) {
        setState(() {
          _isVerifying = false;
          _isVerified = true;
          _vehicleData = result.vehicleData;
        });
      } else {
        setState(() {
          _isVerifying = false;
          _isVerified = false;
          _errorMessage = result.errorMessage ?? 'No se pudo verificar el documento';
          _photo = null;
        });

        _showRetakeDialog(result.errorMessage ?? 'Documento no válido');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _isVerified = false;
          _errorMessage = 'Error al procesar la imagen';
          _photo = null;
        });
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
          'Para verificar tus documentos, necesitamos acceso a la cámara. Por favor, permite el acceso cuando se te solicite.',
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
          'El permiso de cámara fue denegado permanentemente. Para continuar, debes habilitarlo manualmente en la configuración de tu dispositivo.',
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
        title: const Text('Documento no válido'),
        content: Text(
          '$message\n\nPor favor, vuelve a tomar la foto asegurándote de que:\n'
          '• El documento esté completo y visible\n'
          '• Haya buena iluminación\n'
          '• La imagen no esté borrosa\n'
          '• Sea el documento físico, no una foto de pantalla',
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
    if (!_isVerified || _vehicleData == null) return;

    context.push('/register/vehicle/license', extra: {
      'userId': widget.userId,
      'role': widget.role,
      'vehicleOwnership': widget.vehicleOwnership,
      'driverRelation': widget.driverRelation,
      'matriculaPhoto': _photo!.path,
      'vehicleData': _vehicleData!.toStringMap(),
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
          'Matrícula vehicular',
          style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contenido scrollable
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Progress indicator
                      _buildProgressIndicator(1, 4),
                      const SizedBox(height: AppDimensions.spacingL),

                      // Título
                      Text('Foto de la matrícula', style: AppTextStyles.h1),
                      const SizedBox(height: AppDimensions.spacingS),
                      Text(
                        'Toma una foto clara de la matrícula de tu vehículo',
                        style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: AppDimensions.spacingL),

                      // Área de foto
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: _buildPhotoArea(),
                      ),
                      const SizedBox(height: AppDimensions.spacingL),

                      // Datos extraídos
                      if (_isVerified && _vehicleData != null) ...[
                        _buildExtractedDataCard(),
                        const SizedBox(height: AppDimensions.spacingL),
                      ],
                    ],
                  ),
                ),
              ),

              // Botones fijos abajo
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
            color: _isVerified
                ? AppColors.success
                : (_errorMessage != null ? AppColors.error : AppColors.border),
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
                              'Verificando documento...',
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Extrayendo información',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
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
                    child: const Icon(
                      Icons.description,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Toca para tomar foto',
                    style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Solo se permite cámara',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildExtractedDataCard() {
    final data = _vehicleData;
    if (data == null) return const SizedBox.shrink();

    // Construir lista de chips con los datos extraídos
    final chips = <Widget>[];
    if (data.placa != null) chips.add(_buildDataChip('Placa', data.placa!));
    if (data.marca != null) chips.add(_buildDataChip('Marca', data.marca!));
    if (data.modelo != null) chips.add(_buildDataChip('Modelo', data.modelo!));
    if (data.anio != null) chips.add(_buildDataChip('Año', data.anio!));
    if (data.color != null) chips.add(_buildDataChip('Color', data.color!));
    if (data.claseVehiculo != null) chips.add(_buildDataChip('Clase', data.claseVehiculo!));
    if (data.vinChasis != null) chips.add(_buildDataChip('VIN', data.vinChasis!));
    if (data.pasajeros != null) chips.add(_buildDataChip('Pasajeros', data.pasajeros!));

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
              const Icon(Icons.check_circle, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                'Datos extraídos',
                style: AppTextStyles.label.copyWith(color: AppColors.success),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (chips.isNotEmpty)
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: chips,
            )
          else
            Text(
              'No se pudieron extraer datos específicos, pero el documento es válido.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildDataChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${label.toUpperCase()}: ',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
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
