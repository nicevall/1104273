import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_text_field.dart';
import '../../widgets/common/loading_indicator.dart';

/// Pantalla de inicio de sesión
/// Permite login con email @uide.edu.ec y contraseña
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Estado para validación instantánea del email
  bool _emailTouched = false;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    // Escuchar cambios en el email para validación instantánea
    _emailController.addListener(_checkEmailDomain);
  }

  /// Validar dominio del email en tiempo real
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
          if (!email.endsWith('@uide.edu.ec')) {
            _emailError = 'Solo se permiten correos @uide.edu.ec';
          } else {
            // Validar formato completo
            _emailError = Validators.validateEmail(email);
          }
        } else {
          _emailTouched = false;
          _emailError = null;
        }
      } else {
        _emailTouched = false;
        _emailError = null;
      }
    });
  }

  @override
  void dispose() {
    _emailController.removeListener(_checkEmailDomain);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Validar y hacer login
  void _handleLogin() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(
            LoginEvent(
              email: _emailController.text.trim(),
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
              // Email ya verificado → ir a Step 3
              context.go('/register/step3', extra: {
                'userId': state.userId,
              });
            } else {
              // Email no verificado → ir a Step 2
              context.go('/register/step2', extra: {
                'userId': state.userId,
                'email': state.email,
              });
            }
          } else if (state is AuthError) {
            // Mostrar error
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

                    // Campo de email
                    CustomTextField(
                      label: 'Correo electrónico',
                      hint: 'tu.email@uide.edu.ec',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: Icons.email_outlined,
                      suffixIcon: _emailTouched
                          ? (_emailError == null
                              ? const Icon(Icons.check_circle,
                                  color: AppColors.success)
                              : const Icon(Icons.cancel,
                                  color: AppColors.error))
                          : null,
                      validator: Validators.validateEmail,
                    ),
                    const SizedBox(height: AppDimensions.spacingS),

                    // Feedback instantáneo del email
                    if (_emailTouched && _emailError != null)
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
                                _emailError!,
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_emailTouched && _emailError == null)
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
                    CustomTextField(
                      label: 'Contraseña',
                      hint: 'Ingresa tu contraseña',
                      controller: _passwordController,
                      obscureText: true,
                      prefixIcon: Icons.lock_outline,
                      validator: Validators.validatePassword,
                    ),
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
                      onPressed: isLoading ? null : _handleLogin,
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
}
