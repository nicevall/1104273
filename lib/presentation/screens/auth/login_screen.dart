import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/loading_indicator.dart';

/// Pantalla de inicio de sesión
/// Permite login con email @uide.edu.ec y contraseña
class LoginScreen extends StatefulWidget {
  final String? prefillEmail; // Email pre-llenado (desde registro fallido)

  const LoginScreen({
    super.key,
    this.prefillEmail,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailPrefixController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  // Sufijo fijo del dominio
  static const String _emailSuffix = '@uide.edu.ec';

  // Estado de validación
  String? _emailError;
  String? _passwordError;
  bool _emailTouched = false;
  bool _passwordTouched = false;

  /// Obtener email completo
  String get _fullEmail => '${_emailPrefixController.text.trim()}$_emailSuffix';

  /// Verificar si el formulario es válido para habilitar botón
  bool get _isFormValid =>
      _emailPrefixController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Escuchar cambios para actualizar el estado del botón
    _emailPrefixController.addListener(_onFieldChanged);
    _passwordController.addListener(_onFieldChanged);

    // Escuchar cuando pierde foco para validar
    _emailFocusNode.addListener(_onEmailFocusChange);
    _passwordFocusNode.addListener(_onPasswordFocusChange);

    // Pre-llenar email si viene desde registro fallido
    if (widget.prefillEmail != null && widget.prefillEmail!.isNotEmpty) {
      // Extraer solo la parte antes del @
      final email = widget.prefillEmail!;
      if (email.contains('@')) {
        _emailPrefixController.text = email.split('@').first;
      } else {
        _emailPrefixController.text = email;
      }
      // Enfocar directamente en el campo de contraseña
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _passwordFocusNode.requestFocus();
      });
    }
  }

  void _onFieldChanged() {
    setState(() {
      // Solo limpiar errores si hay contenido
      if (_emailPrefixController.text.isNotEmpty && _emailError != null) {
        _emailError = _validateEmailPrefix(_emailPrefixController.text);
      }
      if (_passwordController.text.isNotEmpty && _passwordError != null) {
        _passwordError = _validatePassword(_passwordController.text);
      }
    });
  }

  void _onEmailFocusChange() {
    // Validar al perder foco
    if (!_emailFocusNode.hasFocus && _emailTouched) {
      _emailError = _validateEmailPrefix(_emailPrefixController.text);
    }
    if (_emailFocusNode.hasFocus) {
      _emailTouched = true;
    }
    // Actualizar UI para cambiar borde
    setState(() {});
  }

  void _onPasswordFocusChange() {
    // Validar al perder foco
    if (!_passwordFocusNode.hasFocus && _passwordTouched) {
      _passwordError = _validatePassword(_passwordController.text);
    }
    if (_passwordFocusNode.hasFocus) {
      _passwordTouched = true;
    }
    // Actualizar UI para cambiar borde
    setState(() {});
  }

  @override
  void dispose() {
    _emailPrefixController.removeListener(_onFieldChanged);
    _passwordController.removeListener(_onFieldChanged);
    _emailFocusNode.removeListener(_onEmailFocusChange);
    _passwordFocusNode.removeListener(_onPasswordFocusChange);
    _emailPrefixController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  /// Validar solo la parte del prefijo (antes del @)
  String? _validateEmailPrefix(String? value) {
    if (value == null || value.isEmpty) {
      return 'Ingresa tu usuario para continuar';
    }
    if (value.contains('@')) {
      return 'Solo ingresa tu usuario, sin @';
    }
    if (value.contains(' ')) {
      return 'No se permiten espacios';
    }
    return null;
  }

  /// Validar contraseña
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Ingresa tu contraseña para continuar';
    }
    if (value.length < 6) {
      return 'La contraseña debe tener al menos 6 caracteres';
    }
    return null;
  }

  /// Validar y hacer login
  void _handleLogin() {
    // Validar ambos campos
    final emailError = _validateEmailPrefix(_emailPrefixController.text);
    final passwordError = _validatePassword(_passwordController.text);

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _emailTouched = true;
      _passwordTouched = true;
    });

    if (emailError == null && passwordError == null) {
      context.read<AuthBloc>().add(
            LoginEvent(
              email: _fullEmail,
              password: _passwordController.text,
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
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is Authenticated) {
            final user = state.user;

            // Si es conductor puro y no tiene vehículo, ir al registro de vehículo
            if (user.role == 'conductor' && !user.hasVehicle) {
              context.go('/vehicle/register', extra: {
                'userId': user.userId,
                'role': user.role,
              });
              return;
            }

            // Login exitoso → ir a home con datos del usuario
            context.go('/home', extra: {
              'userId': user.userId,
              'userRole': user.role,
              'hasVehicle': user.hasVehicle,
            });
          } else if (state is AuthenticatedNotVerified) {
            // No verificado → ir a verificación OTP
            context.go('/register/step2', extra: {
              'userId': state.userId,
              'email': state.email,
            });
          } else if (state is IncompleteRegistration) {
            // Registro incompleto → continuar desde donde se quedó
            if (state.emailVerified) {
              context.go('/register/step3', extra: {
                'userId': state.userId,
              });
            } else {
              context.go('/register/step2', extra: {
                'userId': state.userId,
                'email': state.email,
              });
            }
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthLoading;

          return LoadingOverlay(
            isLoading: isLoading,
            message: 'Iniciando sesión...',
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.paddingL),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título
                    Text(
                      'Bienvenido de vuelta',
                      style: AppTextStyles.h1,
                    ),
                    const SizedBox(height: AppDimensions.spacingS),

                    // Subtítulo
                    Text(
                      'Inicia sesión con tu cuenta de UIDE',
                      style: AppTextStyles.body1.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingXL),

                    // Campo de email con sufijo fijo
                    _buildEmailField(),
                    const SizedBox(height: AppDimensions.spacingM),

                    // Campo de contraseña
                    _buildPasswordField(),
                    const SizedBox(height: AppDimensions.spacingS),

                    // Olvidé mi contraseña
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => context.push('/forgot-password'),
                        child: Text(
                          '¿Olvidaste tu contraseña?',
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingL),

                    // Botón de iniciar sesión
                    CustomButton.primary(
                      text: 'Iniciar Sesión',
                      onPressed: (isLoading || !_isFormValid) ? null : _handleLogin,
                      isLoading: isLoading,
                    ),
                    const SizedBox(height: AppDimensions.spacingL),

                    // Separador
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.paddingM,
                          ),
                          child: Text(
                            'o',
                            style: AppTextStyles.body2.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spacingL),

                    // Botón de registrarse
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '¿No tienes cuenta? ',
                            style: AppTextStyles.body2.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.push('/register/step1'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Regístrate',
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

  /// Campo de email con sufijo fijo y validación visual
  Widget _buildEmailField() {
    final hasError = _emailError != null;
    final hasFocus = _emailFocusNode.hasFocus;

    // Determinar color del borde
    Color borderColor;
    double borderWidth;
    if (hasFocus) {
      borderColor = hasError ? AppColors.error : AppColors.primary;
      borderWidth = 2;
    } else {
      borderColor = hasError ? AppColors.error : AppColors.border;
      borderWidth = 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Correo institucional',
          style: AppTextStyles.body2.copyWith(
            fontWeight: FontWeight.w500,
            color: hasError ? AppColors.error : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingS),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(AppDimensions.radiusM),
            color: hasError ? AppColors.error.withValues(alpha: 0.05) : Colors.white,
          ),
          child: Row(
            children: [
              // Icono
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(
                  Icons.email_outlined,
                  color: hasError ? AppColors.error : AppColors.textSecondary,
                  size: 20,
                ),
              ),
              // Campo de texto (solo prefijo)
              Expanded(
                child: TextField(
                  controller: _emailPrefixController,
                  focusNode: _emailFocusNode,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  style: AppTextStyles.body1,
                  cursorColor: AppColors.primary,
                  onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                  inputFormatters: [
                    // Solo permitir caracteres válidos para la parte local del email
                    // Letras, números, puntos, guiones y guiones bajos
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-Z0-9._\-]'),
                    ),
                  ],
                  decoration: InputDecoration(
                    hintText: 'johndoe',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              // Sufijo fijo @uide.edu.ec
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: hasError
                      ? AppColors.error.withValues(alpha: 0.1)
                      : const Color(0xFFF0F0F0),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(AppDimensions.radiusM - 2),
                    bottomRight: Radius.circular(AppDimensions.radiusM - 2),
                  ),
                ),
                child: Text(
                  _emailSuffix,
                  style: AppTextStyles.body1.copyWith(
                    color: hasError ? AppColors.error : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Mensaje de error
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: AppColors.error),
                const SizedBox(width: 4),
                Text(
                  _emailError!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Campo de contraseña con validación visual
  Widget _buildPasswordField() {
    final hasError = _passwordError != null;
    final hasFocus = _passwordFocusNode.hasFocus;

    // Determinar color del borde
    Color borderColor;
    double borderWidth;
    if (hasFocus) {
      borderColor = hasError ? AppColors.error : AppColors.primary;
      borderWidth = 2;
    } else {
      borderColor = hasError ? AppColors.error : AppColors.border;
      borderWidth = 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Contraseña',
          style: AppTextStyles.body2.copyWith(
            fontWeight: FontWeight.w500,
            color: hasError ? AppColors.error : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingS),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(AppDimensions.radiusM),
            color: hasError ? AppColors.error.withValues(alpha: 0.05) : Colors.white,
          ),
          child: Row(
            children: [
              // Icono
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(
                  Icons.lock_outline,
                  color: hasError ? AppColors.error : AppColors.textSecondary,
                  size: 20,
                ),
              ),
              // Campo de texto
              Expanded(
                child: TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: _obscureText,
                  textInputAction: TextInputAction.done,
                  style: AppTextStyles.body1,
                  cursorColor: AppColors.primary,
                  onSubmitted: (_) => _handleLogin(),
                  decoration: InputDecoration(
                    hintText: 'Ingresa tu contraseña',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              // Toggle visibilidad
              IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility_off : Icons.visibility,
                  color: hasError ? AppColors.error : AppColors.textSecondary,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              ),
            ],
          ),
        ),
        // Mensaje de error
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: AppColors.error),
                const SizedBox(width: 4),
                Text(
                  _passwordError!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ],
            ),
          ),
      ],
    );
  }

  bool _obscureText = true;
}
