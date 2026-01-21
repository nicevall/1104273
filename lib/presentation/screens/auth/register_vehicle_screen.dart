import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/services/permission_handler_service.dart';
import '../../blocs/registration/registration_bloc.dart';
import '../../blocs/registration/registration_event.dart';
import '../../blocs/registration/registration_state.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_text_field.dart';
import '../../widgets/common/loading_indicator.dart';

/// Pantalla de registro de vehículo
/// Solo para rol 'conductor' o 'ambos'
/// NO muestra progress bar (ya completó 5/5)
class RegisterVehicleScreen extends StatefulWidget {
  final String userId;
  final String role;

  const RegisterVehicleScreen({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  State<RegisterVehicleScreen> createState() => _RegisterVehicleScreenState();
}

class _RegisterVehicleScreenState extends State<RegisterVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _colorController = TextEditingController();
  final _plateController = TextEditingController();
  final _capacityController = TextEditingController();

  final _permissionService = PermissionHandlerService();
  final _imagePicker = ImagePicker();

  File? _vehiclePhoto;
  File? _licensePhoto;
  bool _hasAirConditioning = false;

  // Marcas comunes (ejemplo)
  final List<String> _brands = [
    'Chevrolet',
    'Toyota',
    'Nissan',
    'Hyundai',
    'Kia',
    'Mazda',
    'Ford',
    'Honda',
    'Volkswagen',
    'Suzuki',
    'Otra',
  ];

  // Colores comunes
  final List<String> _colors = [
    'Blanco',
    'Negro',
    'Plateado',
    'Gris',
    'Rojo',
    'Azul',
    'Verde',
    'Amarillo',
    'Otro',
  ];

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _colorController.dispose();
    _plateController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  /// Seleccionar foto del vehículo
  Future<void> _pickVehiclePhoto() async {
    final hasPermission = await _permissionService.requestCameraWithDialog(context);

    if (!hasPermission) return;

    final source = await _showImageSourceDialog();
    if (source == null) return;

    final image = await _imagePicker.pickImage(source: source);

    if (image != null) {
      setState(() {
        _vehiclePhoto = File(image.path);
      });
    }
  }

  /// Seleccionar foto de licencia
  Future<void> _pickLicensePhoto() async {
    final hasPermission = await _permissionService.requestCameraWithDialog(context);

    if (!hasPermission) return;

    final source = await _showImageSourceDialog();
    if (source == null) return;

    final image = await _imagePicker.pickImage(source: source);

    if (image != null) {
      setState(() {
        _licensePhoto = File(image.path);
      });
    }
  }

  /// Mostrar diálogo de origen de imagen
  Future<ImageSource?> _showImageSourceDialog() async {
    return await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar imagen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Cámara'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Registrar vehículo
  void _handleRegisterVehicle() {
    if (_formKey.currentState?.validate() ?? false) {
      if (_vehiclePhoto == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes subir una foto del vehículo'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }

      if (_licensePhoto == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes subir una foto de tu licencia'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }

      context.read<RegistrationBloc>().add(
            RegisterVehicleEvent(
              brand: _brandController.text.trim(),
              model: _modelController.text.trim(),
              year: int.parse(_yearController.text),
              color: _colorController.text.trim(),
              plate: _plateController.text.trim().toUpperCase(),
              capacity: int.parse(_capacityController.text),
              hasAirConditioning: _hasAirConditioning,
              vehiclePhoto: _vehiclePhoto!,
              licensePhoto: _licensePhoto!,
            ),
          );
    }
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
          'Registro de vehículo',
          style: AppTextStyles.h3.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: BlocConsumer<RegistrationBloc, RegistrationState>(
        listener: (context, state) {
          if (state is RegistrationSuccess) {
            // Ir a pantalla de estado
            context.go('/register/status', extra: {
              'userId': state.userId,
              'role': state.role,
              'hasVehicle': state.hasVehicle,
              'status': 'success',
            });
          } else if (state is RegistrationFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error),
                backgroundColor: AppColors.error,
              ),
            );
          } else if (state is RegistrationNetworkError) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sin conexión a internet'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state is RegistrationLoading;

          return LoadingOverlay(
            isLoading: isLoading,
            message: 'Registrando vehículo...',
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.paddingL),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título
                    Text(
                      'Registra tu vehículo',
                      style: AppTextStyles.h1,
                    ),
                    const SizedBox(height: AppDimensions.spacingS),

                    // Subtítulo
                    Text(
                      'Tu vehículo será verificado en máximo 24 horas',
                      style: AppTextStyles.body1.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingXL),

                    // Foto del vehículo
                    _buildPhotoSection(
                      title: 'Foto del vehículo',
                      subtitle: 'Sube una foto clara de tu auto',
                      photo: _vehiclePhoto,
                      onTap: _pickVehiclePhoto,
                    ),
                    const SizedBox(height: AppDimensions.spacingL),

                    // Foto de licencia
                    _buildPhotoSection(
                      title: 'Licencia de conducir',
                      subtitle: 'Sube una foto de tu licencia vigente',
                      photo: _licensePhoto,
                      onTap: _pickLicensePhoto,
                    ),
                    const SizedBox(height: AppDimensions.spacingL),

                    // Marca (selector)
                    _buildDropdownField(
                      label: 'Marca',
                      controller: _brandController,
                      items: _brands,
                      icon: Icons.directions_car,
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Modelo
                    CustomTextField(
                      label: 'Modelo',
                      hint: 'Ej: Spark, Corolla, Versa',
                      controller: _modelController,
                      textCapitalization: TextCapitalization.words,
                      prefixIcon: Icons.car_rental,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa el modelo';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Año
                    CustomTextField(
                      label: 'Año',
                      hint: '2015-2024',
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      prefixIcon: Icons.calendar_today,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa el año';
                        }
                        final year = int.tryParse(value);
                        if (year == null || year < 2000 || year > 2025) {
                          return 'Año inválido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Color (selector)
                    _buildDropdownField(
                      label: 'Color',
                      controller: _colorController,
                      items: _colors,
                      icon: Icons.palette,
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Placa
                    CustomTextField(
                      label: 'Placa',
                      hint: 'ABC-1234',
                      controller: _plateController,
                      textCapitalization: TextCapitalization.characters,
                      prefixIcon: Icons.tag,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa la placa';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Capacidad
                    CustomTextField(
                      label: 'Capacidad de pasajeros',
                      hint: '4',
                      controller: _capacityController,
                      keyboardType: TextInputType.number,
                      prefixIcon: Icons.people,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(1),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa la capacidad';
                        }
                        final capacity = int.tryParse(value);
                        if (capacity == null || capacity < 1 || capacity > 8) {
                          return 'Capacidad inválida (1-8)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Aire acondicionado
                    CheckboxListTile(
                      value: _hasAirConditioning,
                      onChanged: (value) {
                        setState(() {
                          _hasAirConditioning = value ?? false;
                        });
                      },
                      title: Text(
                        'Tiene aire acondicionado',
                        style: AppTextStyles.body1,
                      ),
                      activeColor: AppColors.primary,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: AppDimensions.spacingXL),

                    // Botón registrar
                    CustomButton.primary(
                      text: 'Completar registro',
                      onPressed: isLoading ? null : _handleRegisterVehicle,
                      isLoading: isLoading,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Sección de foto
  Widget _buildPhotoSection({
    required String title,
    required String subtitle,
    required File? photo,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.label),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: photo != null
                ? ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.borderRadius),
                    child: Image.file(
                      photo,
                      fit: BoxFit.cover,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo,
                        size: 48,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Toca para subir foto',
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// Campo dropdown
  Widget _buildDropdownField({
    required String label,
    required TextEditingController controller,
    required List<String> items,
    required IconData icon,
  }) {
    return CustomTextField(
      label: label,
      hint: 'Seleccionar',
      controller: controller,
      readOnly: true,
      prefixIcon: icon,
      suffixIcon: const Icon(Icons.arrow_drop_down),
      onTap: () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => Container(
            padding: const EdgeInsets.all(AppDimensions.paddingL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Selecciona $label', style: AppTextStyles.h3),
                const SizedBox(height: AppDimensions.spacingM),
                ...items.map((item) => ListTile(
                      title: Text(item),
                      onTap: () => Navigator.pop(context, item),
                    )),
              ],
            ),
          ),
        );

        if (selected != null) {
          setState(() {
            controller.text = selected;
          });
        }
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Selecciona $label';
        }
        return null;
      },
    );
  }
}
