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

  // Carrera y semestre seleccionados
  String? _selectedCareer;
  int? _selectedSemester;

  @override
  void initState() {
    super.initState();
    // Si el bloc está en estado inicial, reanudar el registro
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<RegistrationBloc>().state;
      if (state is RegistrationInitial) {
        context.read<RegistrationBloc>().add(
              ResumeRegistrationEvent(
                userId: widget.userId,
                email: '', // Email no es necesario en Step 3
              ),
            );
      }
    });

    // Escuchar cambios en los campos para actualizar el estado del botón
    _firstNameController.addListener(_onFieldChanged);
    _lastNameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    setState(() {});
  }

  /// Verificar si todos los requisitos del formulario están cumplidos
  bool get _isFormValid {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();

    // Nombre válido (mínimo 3 caracteres)
    final isFirstNameValid = firstName.length >= 3;

    // Apellido válido (mínimo 3 caracteres)
    final isLastNameValid = lastName.length >= 3;

    // Celular válido (9 dígitos)
    final isPhoneValid = phone.length == 9;

    // Carrera y semestre seleccionados
    final isCareerSelected = _selectedCareer != null;
    final isSemesterSelected = _selectedSemester != null;

    return isFirstNameValid &&
        isLastNameValid &&
        isPhoneValid &&
        isCareerSelected &&
        isSemesterSelected;
  }

  // Carreras de UIDE con sus semestres máximos
  static const Map<String, int> _careerSemesters = {
    'Administración de Empresas': 8,
    'Derecho': 8,
    'Ingeniería en Sistemas de la Información': 8,
    'Marketing': 8,
    'Negocios Internacionales': 8,
    'Psicología': 8,
    'Arquitectura': 9,
  };

  // Obtener el número máximo de semestres para la carrera seleccionada
  int get _maxSemesters => _careerSemesters[_selectedCareer] ?? 8;

  @override
  void dispose() {
    _firstNameController.removeListener(_onFieldChanged);
    _lastNameController.removeListener(_onFieldChanged);
    _phoneController.removeListener(_onFieldChanged);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Validar y continuar a Step 4
  void _handleContinue() {
    if (_formKey.currentState?.validate() ?? false) {
      if (_selectedCareer == null || _selectedSemester == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecciona tu carrera y semestre'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      // Agregar prefijo +593 al número de celular
      final phoneNumber = '+593${_phoneController.text.trim()}';

      context.read<RegistrationBloc>().add(
            RegisterStep3Event(
              firstName: _firstNameController.text.trim(),
              lastName: _lastNameController.text.trim(),
              phoneNumber: phoneNumber,
              career: _selectedCareer!,
              semester: _selectedSemester!,
            ),
          );
    }
  }

  /// Cuando cambia la carrera, resetear el semestre si excede el máximo
  void _onCareerChanged(String? career) {
    setState(() {
      _selectedCareer = career;
      // Si el semestre actual excede el máximo de la nueva carrera, resetear
      if (_selectedSemester != null && _selectedSemester! > _maxSemesters) {
        _selectedSemester = null;
      }
    });
  }

  /// Mostrar diálogo de que no puede volver
  void _showCannotGoBackDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No puedes volver'),
        content: const Text(
          'Tu correo ya fue verificado. Debes completar el registro para continuar.\n\n'
          'Si deseas cancelar, puedes hacerlo desde el último paso del registro.',
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showCannotGoBackDialog();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          // Sin botón de retroceso - el usuario debe completar el registro
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

                    // Celular
                    _buildPhoneField(),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Carrera (dropdown)
                    _buildDropdownField(
                      label: 'Carrera',
                      hint: 'Selecciona tu carrera',
                      value: _selectedCareer,
                      icon: Icons.school_outlined,
                      items: _careerSemesters.keys.toList(),
                      onChanged: _onCareerChanged,
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Semestre (dropdown dinámico)
                    _buildDropdownField(
                      label: 'Semestre',
                      hint: _selectedCareer == null
                          ? 'Primero selecciona tu carrera'
                          : 'Selecciona tu semestre',
                      value: _selectedSemester?.toString(),
                      icon: Icons.class_outlined,
                      items: _selectedCareer == null
                          ? []
                          : List.generate(_maxSemesters, (i) => '${i + 1}'),
                      onChanged: _selectedCareer == null
                          ? null
                          : (value) {
                              setState(() {
                                _selectedSemester = int.tryParse(value ?? '');
                              });
                            },
                      enabled: _selectedCareer != null,
                    ),
                    const SizedBox(height: AppDimensions.spacingXL),

                    // Botón continuar
                    // Botón continuar (solo habilitado si todos los requisitos están cumplidos)
                    CustomButton.primary(
                      text: 'Continuar',
                      onPressed: isLoading || !_isFormValid ? null : _handleContinue,
                      isLoading: isLoading,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        ),
      ),
    );
  }

  /// Construir campo selector moderno con bottom sheet
  Widget _buildDropdownField({
    required String label,
    required String hint,
    required String? value,
    required IconData icon,
    required List<String> items,
    required void Function(String?)? onChanged,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.inputLabel,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: enabled && items.isNotEmpty
              ? () => _showSelectionBottomSheet(
                    title: label,
                    items: items,
                    selectedValue: value,
                    onSelected: onChanged,
                  )
              : null,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: enabled ? Colors.white : AppColors.background,
              borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
              border: Border.all(
                color: AppColors.border,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: enabled ? AppColors.textSecondary : AppColors.disabled,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value ?? hint,
                    style: AppTextStyles.body1.copyWith(
                      color: value != null
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: enabled ? AppColors.textSecondary : AppColors.disabled,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Mostrar bottom sheet para selección
  void _showSelectionBottomSheet({
    required String title,
    required List<String> items,
    required String? selectedValue,
    required void Function(String?)? onSelected,
  }) {
    // Calcular altura dinámica basada en el número de items
    // Header (handle + título + divider) ≈ 80px, cada item ≈ 56px, padding inferior ≈ 40px
    final headerHeight = 80.0;
    final itemHeight = 56.0;
    final bottomPadding = 40.0;
    final calculatedHeight = headerHeight + (items.length * itemHeight) + bottomPadding;
    final maxAllowedHeight = MediaQuery.of(context).size.height * 0.75;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        // Usar altura calculada si cabe, sino usar máximo permitido
        constraints: BoxConstraints(
          maxHeight: calculatedHeight < maxAllowedHeight ? calculatedHeight : maxAllowedHeight,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Título
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Selecciona $title',
                style: AppTextStyles.h3,
              ),
            ),
            const Divider(height: 1),
            // Lista de opciones (sin scroll si caben todas)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                physics: calculatedHeight < maxAllowedHeight
                    ? const NeverScrollableScrollPhysics()
                    : null,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = item == selectedValue;
                  return ListTile(
                    onTap: () {
                      onSelected?.call(item);
                      Navigator.pop(context);
                    },
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? AppColors.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    title: Text(
                      item,
                      style: AppTextStyles.body1.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                          )
                        : null,
                  );
                },
              ),
            ),
            // Padding inferior para safe area
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  /// Construir campo de celular con prefijo +593
  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Celular',
          style: AppTextStyles.inputLabel,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Prefijo fijo +593
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppDimensions.borderRadius),
                  bottomLeft: Radius.circular(AppDimensions.borderRadius),
                ),
                border: Border.all(
                  color: AppColors.border,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '+593',
                    style: AppTextStyles.body1.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Campo de número (9 dígitos)
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.number,
                maxLength: 9,
                style: AppTextStyles.body1,
                decoration: InputDecoration(
                  hintText: '999999999',
                  hintStyle: AppTextStyles.body1.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  counterText: '', // Ocultar contador de caracteres
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(AppDimensions.borderRadius),
                      bottomRight: Radius.circular(AppDimensions.borderRadius),
                    ),
                    borderSide: const BorderSide(
                      color: AppColors.border,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(AppDimensions.borderRadius),
                      bottomRight: Radius.circular(AppDimensions.borderRadius),
                    ),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(AppDimensions.borderRadius),
                      bottomRight: Radius.circular(AppDimensions.borderRadius),
                    ),
                    borderSide: const BorderSide(
                      color: AppColors.error,
                      width: 1,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(AppDimensions.borderRadius),
                      bottomRight: Radius.circular(AppDimensions.borderRadius),
                    ),
                    borderSide: const BorderSide(
                      color: AppColors.error,
                      width: 2,
                    ),
                  ),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingresa tu número';
                  }
                  if (value.length != 9) {
                    return 'El número debe tener 9 dígitos';
                  }
                  if (!value.startsWith('9')) {
                    return 'El número debe empezar con 9';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Ingresa tu número sin el 0 del principio',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
