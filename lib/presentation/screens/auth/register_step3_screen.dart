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

  // Estados "touched" para mostrar errores solo después de interacción
  bool _firstNameTouched = false;
  bool _lastNameTouched = false;
  bool _phoneTouched = false;

  // FocusNodes para detectar cuando pierde el foco
  final _firstNameFocusNode = FocusNode();
  final _lastNameFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();

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

    // Detectar cuando pierde el foco para marcar como "touched"
    _firstNameFocusNode.addListener(_onFirstNameFocusChange);
    _lastNameFocusNode.addListener(_onLastNameFocusChange);
    _phoneFocusNode.addListener(_onPhoneFocusChange);
  }

  void _onFieldChanged() {
    setState(() {
      // Marcar como "touched" si tienen contenido
      if (_firstNameController.text.isNotEmpty) {
        _firstNameTouched = true;
      }
      if (_lastNameController.text.isNotEmpty) {
        _lastNameTouched = true;
      }
      if (_phoneController.text.isNotEmpty) {
        _phoneTouched = true;
      }
    });
  }

  // Cuando el nombre pierde el foco, marcar como touched
  void _onFirstNameFocusChange() {
    if (!_firstNameFocusNode.hasFocus) {
      setState(() {
        _firstNameTouched = true;
      });
    }
  }

  // Cuando el apellido pierde el foco, marcar como touched
  void _onLastNameFocusChange() {
    if (!_lastNameFocusNode.hasFocus) {
      setState(() {
        _lastNameTouched = true;
      });
    }
  }

  // Cuando el celular pierde el foco, marcar como touched
  void _onPhoneFocusChange() {
    if (!_phoneFocusNode.hasFocus) {
      setState(() {
        _phoneTouched = true;
      });
    }
  }

  // Verificar si el nombre tiene error
  bool get _firstNameHasError {
    if (!_firstNameTouched) return false;
    final name = _firstNameController.text.trim();
    if (name.isEmpty) return true;
    return name.length < 3;
  }

  // Obtener mensaje de error del nombre
  String? get _firstNameErrorMessage {
    if (!_firstNameTouched) return null;
    final name = _firstNameController.text.trim();
    if (name.isEmpty) return 'El nombre es requerido';
    if (name.length < 3) return 'Mínimo 3 caracteres';
    return null;
  }

  // Verificar si el apellido tiene error
  bool get _lastNameHasError {
    if (!_lastNameTouched) return false;
    final lastName = _lastNameController.text.trim();
    if (lastName.isEmpty) return true;
    return lastName.length < 3;
  }

  // Obtener mensaje de error del apellido
  String? get _lastNameErrorMessage {
    if (!_lastNameTouched) return null;
    final lastName = _lastNameController.text.trim();
    if (lastName.isEmpty) return 'El apellido es requerido';
    if (lastName.length < 3) return 'Mínimo 3 caracteres';
    return null;
  }

  // Verificar si el celular tiene error
  bool get _phoneHasError {
    if (!_phoneTouched) return false;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return true;
    if (phone.length != 9) return true;
    if (!phone.startsWith('9')) return true;
    return false;
  }

  // Obtener mensaje de error del celular
  String? get _phoneErrorMessage {
    if (!_phoneTouched) return null;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return 'El número es requerido';
    if (phone.length != 9) return 'Debe tener 9 dígitos';
    if (!phone.startsWith('9')) return 'Debe empezar con 9';
    return null;
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
    _firstNameFocusNode.removeListener(_onFirstNameFocusChange);
    _lastNameFocusNode.removeListener(_onLastNameFocusChange);
    _phoneFocusNode.removeListener(_onPhoneFocusChange);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _firstNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    _phoneFocusNode.dispose();
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('No puedes volver'),
        content: const Text(
          'Tu correo ya fue verificado. Debes completar el registro para continuar.\n\n'
          'Si deseas cancelar el registro, tu cuenta será eliminada.',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              // Botón Entendido - outline gris
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Entendido',
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Botón Cancelar registro - rojo sólido
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _handleCancelRegistration();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Cancelar',
                    style: AppTextStyles.button.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Cancelar registro - mostrar confirmación
  void _handleCancelRegistration() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Cancelar registro?'),
        content: const Text(
          '¿Estás seguro que deseas cancelar el registro? Tu cuenta será eliminada.',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              // Botón No - outline gris
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'No',
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Botón Sí, cancelar - rojo sólido
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    // Cancelar registro y eliminar cuenta
                    context.read<RegistrationBloc>().add(const CancelRegistrationEvent());
                    context.go('/welcome');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Sí, cancelar',
                    style: AppTextStyles.button.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
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
                    Focus(
                      focusNode: _firstNameFocusNode,
                      child: CustomTextField(
                        label: 'Nombre',
                        hint: 'Tu primer nombre',
                        controller: _firstNameController,
                        textCapitalization: TextCapitalization.words,
                        prefixIcon: Icons.person_outline,
                        hasExternalError: _firstNameHasError,
                        validator: Validators.validateName,
                      ),
                    ),
                    // Feedback del nombre
                    if (_firstNameTouched && _firstNameHasError)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AppDimensions.paddingL,
                          top: 6,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cancel,
                              size: 14,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _firstNameErrorMessage ?? '',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Apellido
                    Focus(
                      focusNode: _lastNameFocusNode,
                      child: CustomTextField(
                        label: 'Apellido',
                        hint: 'Tu apellido',
                        controller: _lastNameController,
                        textCapitalization: TextCapitalization.words,
                        prefixIcon: Icons.person_outline,
                        hasExternalError: _lastNameHasError,
                        validator: Validators.validateName,
                      ),
                    ),
                    // Feedback del apellido
                    if (_lastNameTouched && _lastNameHasError)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AppDimensions.paddingL,
                          top: 6,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cancel,
                              size: 14,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _lastNameErrorMessage ?? '',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
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
    final isSelected = value != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label con indicador de "Toca para seleccionar"
        Row(
          children: [
            Text(
              label,
              style: AppTextStyles.inputLabel,
            ),
            if (enabled && !isSelected) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app,
                      size: 12,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Toca para seleccionar',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
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
              // Fondo ligeramente turquesa cuando está enabled y no seleccionado
              color: !enabled
                  ? AppColors.background
                  : (isSelected
                      ? Colors.white
                      : AppColors.primary.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
              border: Border.all(
                // Borde turquesa cuando está enabled y no seleccionado
                color: !enabled
                    ? AppColors.border
                    : (isSelected ? AppColors.border : AppColors.primary.withOpacity(0.5)),
                width: enabled && !isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: enabled
                      ? (isSelected ? AppColors.textSecondary : AppColors.primary)
                      : AppColors.disabled,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value ?? hint,
                    style: AppTextStyles.body1.copyWith(
                      color: isSelected
                          ? AppColors.textPrimary
                          : (enabled
                              ? AppColors.primary
                              : AppColors.textSecondary),
                      fontWeight: enabled && !isSelected
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: enabled
                      ? (isSelected ? AppColors.textSecondary : AppColors.primary)
                      : AppColors.disabled,
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
    final hasError = _phoneHasError;

    return Focus(
      focusNode: _phoneFocusNode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Celular',
            style: AppTextStyles.inputLabel.copyWith(
              color: hasError ? AppColors.error : AppColors.textPrimary,
            ),
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
                  color: hasError
                      ? AppColors.error.withOpacity(0.05)
                      : AppColors.background,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppDimensions.borderRadius),
                    bottomLeft: Radius.circular(AppDimensions.borderRadius),
                  ),
                  border: Border.all(
                    color: hasError ? AppColors.error : AppColors.border,
                    width: hasError ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.phone_outlined,
                      color: hasError ? AppColors.error : AppColors.textSecondary,
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
                    filled: hasError,
                    fillColor: hasError
                        ? AppColors.error.withOpacity(0.05)
                        : Colors.white,
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
                      borderSide: BorderSide(
                        color: hasError ? AppColors.error : AppColors.border,
                        width: hasError ? 1.5 : 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(AppDimensions.borderRadius),
                        bottomRight: Radius.circular(AppDimensions.borderRadius),
                      ),
                      borderSide: BorderSide(
                        color: hasError ? AppColors.error : AppColors.primary,
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
                        width: 1.5,
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
                    // Solo permite 9 como primer dígito
                    _OnlyNineFirstDigitFormatter(),
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
          // Feedback del celular
          if (_phoneTouched && hasError)
            Padding(
              padding: const EdgeInsets.only(left: AppDimensions.paddingL),
              child: Row(
                children: [
                  const Icon(
                    Icons.cancel,
                    size: 14,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _phoneErrorMessage ?? '',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          if (!hasError || !_phoneTouched)
            Text(
              'El número debe empezar con 9 (ej: 999999999)',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Formatter que SOLO permite 9 como primer dígito
class _OnlyNineFirstDigitFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Si el nuevo valor está vacío, permitirlo
    if (newValue.text.isEmpty) {
      return newValue;
    }
    // Si el primer dígito no es 9, rechazarlo
    if (!newValue.text.startsWith('9')) {
      return oldValue;
    }
    return newValue;
  }
}
