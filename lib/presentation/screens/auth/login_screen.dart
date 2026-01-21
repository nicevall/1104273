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

  @override
  void dispose() {
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
            // Login exitoso → ir a home
            context.go('/home');
          } else if (state is AuthenticatedNotVerified) {
            // No verificado → ir a verificación OTP
            context.go('/register/step2', extra: {
              'userId': state.userId,
              'email': state.email,
            });
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
                      validator: Validators.validateEmail,
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
                        onPressed: () {
                          // TODO: Implementar recuperación de contraseña
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Función de recuperación próximamente',
                              ),
                            ),
                          );
                        },
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
