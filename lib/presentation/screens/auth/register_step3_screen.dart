import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../blocs/registration/registration_bloc.dart';
import '../../blocs/registration/registration_event.dart';
import '../../blocs/registration/registration_state.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_text_field.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/progress_bar.dart';

/// Step 3: Información adicional del usuario
/// Nombre, apellido, teléfono, carrera y semestre
class RegisterStep3Screen extends StatefulWidget {
  final String userId;

  const RegisterStep3Screen({
    super.key,
    required this.userId,
  });

  @override
  State<RegisterStep3Screen> createState() => _RegisterStep3ScreenState();
}

class _RegisterStep3ScreenState extends State<RegisterStep3Screen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _careerController = TextEditingController();
  final _semesterController = TextEditingController();

  // Lista de carreras de UIDE (ejemplo)
  final List<String> _careers = [
    'Ingeniería en Sistemas',
    'Ingeniería Industrial',
    'Ingeniería Civil',
    'Administración de Empresas',
    'Marketing',
    'Contabilidad y Auditoría',
    'Derecho',
    'Psicología',
    'Arquitectura',
    'Diseño Gráfico',
    'Medicina',
    'Enfermería',
    'Comunicación',
    'Turismo',
    'Otra',
  ];

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _careerController.dispose();
    _semesterController.dispose();
    super.dispose();
  }

  /// Validar y continuar a Step 4
  void _handleContinue() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<RegistrationBloc>().add(
            RegisterStep3Event(
              firstName: _firstNameController.text.trim(),
              lastName: _lastNameController.text.trim(),
              phoneNumber: _phoneController.text.trim(),
              career: _careerController.text.trim(),
              semester: int.parse(_semesterController.text),
            ),
          );
    }
  }

  /// Mostrar selector de carrera
  Future<void> _showCareerPicker() async {
    final career = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(AppDimensions.paddingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Selecciona tu carrera',
              style: AppTextStyles.h3,
            ),
            const SizedBox(height: AppDimensions.spacingM),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _careers.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(_careers[index]),
                    onTap: () => Navigator.pop(context, _careers[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (career != null) {
      setState(() {
        _careerController.text = career;
      });
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
          'Registro',
          style: AppTextStyles.h3.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: BlocConsumer<RegistrationBloc, RegistrationState>(
        listener: (context, state) {
          if (state is RegistrationStep4) {
            // Navegar a Step 4
            context.push('/register/step4', extra: {'userId': state.userId});
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
          final isLoading = state is RegistrationLoading && state.step == 3;

          return LoadingOverlay(
            isLoading: isLoading,
            message: 'Guardando información...',
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.paddingL),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barra de progreso
                    const ProgressBar(currentStep: 3),
                    const SizedBox(height: AppDimensions.spacingXL),

                    // Título
                    Text(
                      'Cuéntanos sobre ti',
                      style: AppTextStyles.h1,
                    ),
                    const SizedBox(height: AppDimensions.spacingS),

                    // Subtítulo
                    Text(
                      'Completa tu perfil de estudiante',
                      style: AppTextStyles.body1.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingXL),

                    // Nombre
                    CustomTextField(
                      label: 'Nombre',
                      hint: 'Tu primer nombre',
                      controller: _firstNameController,
                      textCapitalization: TextCapitalization.words,
                      prefixIcon: Icons.person_outline,
                      validator: Validators.validateName,
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Apellido
                    CustomTextField(
                      label: 'Apellido',
                      hint: 'Tu apellido',
                      controller: _lastNameController,
                      textCapitalization: TextCapitalization.words,
                      prefixIcon: Icons.person_outline,
                      validator: Validators.validateName,
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Teléfono
                    CustomTextField(
                      label: 'Teléfono',
                      hint: '+593999999999',
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      prefixIcon: Icons.phone_outlined,
                      validator: Validators.validatePhone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Carrera (selector)
                    CustomTextField(
                      label: 'Carrera',
                      hint: 'Selecciona tu carrera',
                      controller: _careerController,
                      readOnly: true,
                      prefixIcon: Icons.school_outlined,
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                      onTap: _showCareerPicker,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Selecciona tu carrera';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Semestre
                    CustomTextField(
                      label: 'Semestre',
                      hint: 'Número de semestre (1-10)',
                      controller: _semesterController,
                      keyboardType: TextInputType.number,
                      prefixIcon: Icons.class_outlined,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa tu semestre';
                        }
                        final semester = int.tryParse(value);
                        if (semester == null || semester < 1 || semester > 10) {
                          return 'Ingresa un semestre válido (1-10)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppDimensions.spacingXL),

                    // Botón continuar
                    CustomButton.primary(
                      text: 'Continuar',
                      onPressed: isLoading ? null : _handleContinue,
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
}
