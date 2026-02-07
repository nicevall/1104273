import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../blocs/registration/registration_bloc.dart';
import '../../blocs/registration/registration_event.dart';
import '../../blocs/registration/registration_state.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_text_field.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/password_strength_indicator.dart';
import '../../widgets/common/progress_bar.dart';

/// Step 1: Registro de email y contraseña
/// Valida @uide.edu.ec y fortaleza de contraseña
class RegisterStep1Screen extends StatefulWidget {
  const RegisterStep1Screen({super.key});

  @override
  State<RegisterStep1Screen> createState() => _RegisterStep1ScreenState();
}

class _RegisterStep1ScreenState extends State<RegisterStep1Screen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _passwordsMatch = false;
  bool _confirmPasswordTouched = false;

  // Estado para validación instantánea del email
  bool _emailTouched = false;
  String? _emailError;

  // Estado para validación de contraseña
  bool _passwordTouched = false;

  // Verificar si el email está vacío y ha sido tocado
  bool get _emailHasError {
    if (!_emailTouched) return false;
    // Si está vacío, es error
    if (_emailController.text.trim().isEmpty) return true;
    // Si tiene error de dominio, es error
    return _emailError != null;
  }

  bool get _passwordHasError {
    if (!_passwordTouched) return false;
    // Si está vacío, es error
    if (_passwordController.text.isEmpty) return true;
    return Validators.validatePassword(_passwordController.text) != null;
  }

  bool get _confirmPasswordHasError {
    if (!_confirmPasswordTouched) return false;
    // Si está vacío, es error
    if (_confirmPasswordController.text.isEmpty) return true;
    return !_passwordsMatch;
  }

  // FocusNodes para detectar cuando pierde el foco
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Escuchar cambios en el email para validación instantánea
    _emailController.addListener(_checkEmailDomain);
    // Escuchar cambios en ambas contraseñas
    _passwordController.addListener(_checkPasswordsMatch);
    _confirmPasswordController.addListener(_checkPasswordsMatch);

    // Detectar cuando pierde el foco para marcar como "touched"
    _emailFocusNode.addListener(_onEmailFocusChange);
    _passwordFocusNode.addListener(_onPasswordFocusChange);
    _confirmPasswordFocusNode.addListener(_onConfirmPasswordFocusChange);
  }

  void _onEmailFocusChange() {
    // Cuando pierde el foco, marcar como touched
    if (!_emailFocusNode.hasFocus && _emailController.text.isNotEmpty) {
      setState(() {
        _emailTouched = true;
        // Validar el email completo
        _emailError = Validators.validateEmail(_emailController.text.trim());
      });
    }
    // También marcar si perdió el foco con campo vacío (para mostrar error de campo requerido)
    if (!_emailFocusNode.hasFocus && _emailController.text.isEmpty) {
      setState(() {
        _emailTouched = true;
        _emailError = 'El correo es requerido';
      });
    }
  }

  void _onPasswordFocusChange() {
    // Cuando pierde el foco, marcar como touched
    if (!_passwordFocusNode.hasFocus) {
      setState(() {
        _passwordTouched = true;
      });
    }
  }

  void _onConfirmPasswordFocusChange() {
    // Cuando pierde el foco, marcar como touched
    if (!_confirmPasswordFocusNode.hasFocus) {
      setState(() {
        _confirmPasswordTouched = true;
        if (_confirmPasswordController.text.isNotEmpty) {
          _passwordsMatch = _passwordController.text == _confirmPasswordController.text;
        }
      });
    }
  }

  /// Validar dominio del email en tiempo real
  /// Solo muestra feedback DESPUÉS de que el usuario escriba algo del dominio
  /// Y solo muestra error si lo que escribió NO es parte de "uide.edu.ec"
  void _checkEmailDomain() {
    final email = _emailController.text.trim();

    setState(() {
      // Solo mostrar feedback cuando haya escrito algo después del @
      if (email.contains('@')) {
        final atIndex = email.indexOf('@');
        final afterAt = email.substring(atIndex + 1);

        // Solo mostrar feedback si hay al menos 1 caracter después del @
        if (afterAt.isNotEmpty) {
          _emailTouched = true;

          // Verificar si lo que escribió es parte del dominio correcto
          const validDomain = 'uide.edu.ec';

          // Si el email termina con @uide.edu.ec está bien
          if (email.endsWith('@uide.edu.ec')) {
            _emailError = Validators.validateEmail(email);
          }
          // Si lo que escribió después del @ es un prefijo de "uide.edu.ec", no mostrar error todavía
          else if (validDomain.startsWith(afterAt)) {
            _emailError = null; // Está escribiendo el dominio correcto
          }
          // Si escribió algo que no es parte del dominio, mostrar error
          else {
            _emailError = 'Solo se permiten correos @uide.edu.ec';
          }
        } else {
          // Solo tiene @ pero nada después, no mostrar feedback aún
          _emailTouched = false;
          _emailError = null;
        }
      } else {
        // No tiene @, no mostrar feedback
        _emailTouched = false;
        _emailError = null;
      }
    });
  }

  void _checkPasswordsMatch() {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    setState(() {
      // Marcar contraseña como tocada si tiene contenido
      if (password.isNotEmpty) {
        _passwordTouched = true;
      }

      if (confirmPassword.isNotEmpty) {
        _confirmPasswordTouched = true;
        _passwordsMatch = password == confirmPassword && password.isNotEmpty;
      } else {
        _confirmPasswordTouched = false;
        _passwordsMatch = false;
      }
    });
  }

  /// Verificar si todos los requisitos del formulario están cumplidos
  bool get _isFormValid {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // 1. Email válido (dominio @uide.edu.ec y formato correcto)
    final isEmailValid = Validators.validateEmail(email) == null;

    // 2. Contraseña cumple todos los requisitos
    final isPasswordValid = Validators.validatePassword(password) == null;

    // 3. Las contraseñas coinciden
    final doPasswordsMatch = password.isNotEmpty &&
        confirmPassword.isNotEmpty &&
        password == confirmPassword;

    return isEmailValid && isPasswordValid && doPasswordsMatch;
  }

  @override
  void dispose() {
    _emailController.removeListener(_checkEmailDomain);
    _passwordController.removeListener(_checkPasswordsMatch);
    _confirmPasswordController.removeListener(_checkPasswordsMatch);
    _emailFocusNode.removeListener(_onEmailFocusChange);
    _passwordFocusNode.removeListener(_onPasswordFocusChange);
    _confirmPasswordFocusNode.removeListener(_onConfirmPasswordFocusChange);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  /// Validar y continuar a Step 2
  void _handleContinue() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<RegistrationBloc>().add(
            RegisterStep1Event(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              passwordConfirmation: _confirmPasswordController.text,
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
          'Registro',
          style: AppTextStyles.h3.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: BlocConsumer<RegistrationBloc, RegistrationState>(
        listener: (context, state) {
          if (state is RegistrationStep2) {
            // Navegar a Step 2
            // El email de verificación se envía automáticamente
            context.push('/register/step2', extra: {
              'userId': state.userId,
              'email': state.email,
            });
          } else if (state is RegistrationStep3) {
            // El email ya está verificado (caso de recuperación de registro)
            // Navegar directamente a Step 3
            context.push('/register/step3', extra: {
              'userId': state.userId,
            });
          } else if (state is RegistrationFailure) {
            // Si el correo ya está registrado Y la contraseña es incorrecta,
            // el bloc ya intentó loguear y falló → redirigir al login
            if (state.error.contains('ya está registrado') ||
                state.error.contains('Si es tu cuenta, inicia sesión')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Este correo ya está registrado. Ingresa tu contraseña para iniciar sesión.'),
                  backgroundColor: AppColors.info,
                  duration: Duration(seconds: 3),
                ),
              );
              // Navegar al login con el email pre-llenado
              context.go('/login', extra: {
                'prefillEmail': _emailController.text.trim(),
              });
            } else {
              // Mostrar error normal
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.error),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          } else if (state is RegistrationNetworkError) {
            // Error de red
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sin conexión a internet'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state is RegistrationLoading && state.step == 1;

          return LoadingOverlay(
            isLoading: isLoading,
            message: 'Creando tu cuenta...',
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.paddingL),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barra de progreso
                    const ProgressBar(currentStep: 1),
                    const SizedBox(height: AppDimensions.spacingXL),

                    // Título
                    Text(
                      'Crea tu cuenta',
                      style: AppTextStyles.h1,
                    ),
                    const SizedBox(height: AppDimensions.spacingS),

                    // Subtítulo
                    Text(
                      'Usa tu correo institucional de UIDE',
                      style: AppTextStyles.body1.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingXL),

                    // Campo de email
                    Focus(
                      focusNode: _emailFocusNode,
                      child: CustomTextField(
                        label: 'Correo electrónico',
                        hint: 'tu.email@uide.edu.ec',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.email_outlined,
                        hasExternalError: _emailHasError,
                        suffixIcon: _emailTouched
                            ? (_emailError == null && _emailController.text.trim().isNotEmpty
                                ? const Icon(Icons.check_circle,
                                    color: AppColors.success)
                                : const Icon(Icons.cancel,
                                    color: AppColors.error))
                            : null,
                        validator: Validators.validateEmail,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingS),

                    // Feedback instantáneo del email
                    if (_emailTouched && _emailHasError)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AppDimensions.paddingL,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cancel,
                              size: 16,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: AppDimensions.spacingS),
                            Expanded(
                              child: Text(
                                _emailError ?? 'El correo es requerido',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_emailTouched && !_emailHasError && _emailController.text.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AppDimensions.paddingL,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: AppDimensions.spacingS),
                            Text(
                              'Correo institucional válido',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Campo de contraseña
                    Focus(
                      focusNode: _passwordFocusNode,
                      child: CustomTextField(
                        label: 'Contraseña',
                        hint: 'Mínimo 8 caracteres',
                        controller: _passwordController,
                        obscureText: true,
                        prefixIcon: Icons.lock_outline,
                        hasExternalError: _passwordHasError,
                        validator: Validators.validatePassword,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingS),

                    // Indicador de fortaleza de contraseña
                    ValueListenableBuilder(
                      valueListenable: _passwordController,
                      builder: (context, value, child) {
                        return PasswordStrengthIndicator(
                          password: _passwordController.text,
                          showRequirements: true,
                        );
                      },
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Confirmar contraseña
                    Focus(
                      focusNode: _confirmPasswordFocusNode,
                      child: CustomTextField(
                        label: 'Confirmar contraseña',
                        hint: 'Repite tu contraseña',
                        controller: _confirmPasswordController,
                        obscureText: true,
                        prefixIcon: Icons.lock_outline,
                        hasExternalError: _confirmPasswordHasError,
                        suffixIcon: _confirmPasswordTouched
                            ? (_passwordsMatch && _confirmPasswordController.text.isNotEmpty
                                ? const Icon(Icons.check_circle,
                                    color: AppColors.success)
                                : const Icon(Icons.cancel,
                                    color: AppColors.error))
                            : null,
                        validator: (value) =>
                            Validators.validatePasswordConfirmation(
                          value,
                          _passwordController.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingS),

                    // Feedback de contraseñas
                    if (_confirmPasswordTouched)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AppDimensions.paddingL,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _passwordsMatch ? Icons.check_circle : Icons.cancel,
                              size: 16,
                              color: _passwordsMatch
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                            const SizedBox(width: AppDimensions.spacingS),
                            Text(
                              _passwordsMatch
                                  ? 'Las contraseñas coinciden'
                                  : 'Las contraseñas no coinciden',
                              style: AppTextStyles.caption.copyWith(
                                color: _passwordsMatch
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppDimensions.spacingXL),

                    // Botón continuar (solo habilitado si todos los requisitos están cumplidos)
                    CustomButton.primary(
                      text: 'Continuar',
                      onPressed: isLoading || !_isFormValid ? null : _handleContinue,
                      isLoading: isLoading,
                    ),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Ya tienes cuenta
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '¿Ya tienes cuenta? ',
                            style: AppTextStyles.body2.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Inicia sesión',
                              style: AppTextStyles.body2.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
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
