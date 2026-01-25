import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../data/services/firebase_auth_service.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_text_field.dart';

/// Pantalla de recuperación de contraseña
/// Permite enviar un email para resetear la contraseña
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _authService = FirebaseAuthService();

  bool _isLoading = false;
  bool _emailSent = false;

  // Cooldown para evitar múltiples envíos
  bool _canResend = true;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  // Estado para validación instantánea del email
  bool _emailTouched = false;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_checkEmailDomain);
  }

  /// Validar dominio del email en tiempo real
  void _checkEmailDomain() {
    final email = _emailController.text.trim();

    setState(() {
      if (email.contains('@')) {
        final atIndex = email.indexOf('@');
        final afterAt = email.substring(atIndex + 1);

        if (afterAt.isNotEmpty) {
          _emailTouched = true;
          if (!email.endsWith('@uide.edu.ec')) {
            _emailError = 'Solo se permiten correos @uide.edu.ec';
          } else {
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
    _cooldownTimer?.cancel();
    _emailController.removeListener(_checkEmailDomain);
    _emailController.dispose();
    super.dispose();
  }

  /// Enviar email de recuperación
  Future<void> _handleResetPassword() async {
    // Evitar múltiples envíos
    if (_isLoading || !_canResend) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.resetPassword(
        email: _emailController.text.trim(),
      );

      if (mounted) {
        // Iniciar cooldown de 60 segundos
        _startCooldown();

        setState(() {
          _emailSent = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        String errorMessage = e.toString();
        // Limpiar el mensaje de error
        if (errorMessage.startsWith('Exception: ')) {
          errorMessage = errorMessage.substring(11);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Iniciar cooldown para evitar spam de emails
  void _startCooldown() {
    setState(() {
      _canResend = false;
      _resendCooldown = 60;
    });

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() {
          _resendCooldown--;
        });
      } else {
        setState(() {
          _canResend = true;
        });
        timer.cancel();
      }
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingL),
        child: _emailSent ? _buildSuccessContent() : _buildFormContent(),
      ),
    );
  }

  /// Contenido del formulario para ingresar email
  Widget _buildFormContent() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icono
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.lock_reset,
                size: 48,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingL),

          // Título
          Center(
            child: Text(
              'Recuperar contraseña',
              style: AppTextStyles.h1,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingS),

          // Subtítulo
          Center(
            child: Text(
              'Ingresa tu correo institucional y te enviaremos un link para restablecer tu contraseña',
              style: AppTextStyles.body1.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
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
                    ? const Icon(Icons.check_circle, color: AppColors.success)
                    : const Icon(Icons.cancel, color: AppColors.error))
                : null,
            validator: Validators.validateEmail,
          ),
          const SizedBox(height: AppDimensions.spacingS),

          // Feedback instantáneo del email
          if (_emailTouched && _emailError != null)
            Padding(
              padding: const EdgeInsets.only(left: AppDimensions.paddingL),
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
              padding: const EdgeInsets.only(left: AppDimensions.paddingL),
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
          const SizedBox(height: AppDimensions.spacingXL),

          // Botón enviar (con cooldown)
          CustomButton.primary(
            text: _canResend
                ? 'Enviar link de recuperación'
                : 'Espera ${_resendCooldown}s para reenviar',
            onPressed: (_isLoading || !_canResend) ? null : _handleResetPassword,
            isLoading: _isLoading,
          ),
          const SizedBox(height: AppDimensions.spacingL),

          // Volver a login
          Center(
            child: TextButton(
              onPressed: () => context.pop(),
              child: Text(
                'Volver a iniciar sesión',
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Contenido de éxito después de enviar el email
  Widget _buildSuccessContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: AppDimensions.spacingXL),

        // Icono de éxito
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 48,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingL),

        // Título
        Text(
          '¡Email enviado!',
          style: AppTextStyles.h1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDimensions.spacingS),

        // Mensaje
        Text(
          'Hemos enviado un link de recuperación a:',
          style: AppTextStyles.body1.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDimensions.spacingS),

        // Email
        Text(
          _emailController.text.trim(),
          style: AppTextStyles.body1.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDimensions.spacingXL),

        // Instrucciones
        Container(
          padding: const EdgeInsets.all(AppDimensions.paddingL),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _buildInstructionItem(
                icon: Icons.email_outlined,
                text: 'Revisa tu bandeja de entrada',
              ),
              const SizedBox(height: 16),
              _buildInstructionItem(
                icon: Icons.link,
                text: 'Haz clic en el link de recuperación',
              ),
              const SizedBox(height: 16),
              _buildInstructionItem(
                icon: Icons.lock_outline,
                text: 'Ingresa tu nueva contraseña',
              ),
              const SizedBox(height: 16),
              _buildInstructionItem(
                icon: Icons.login,
                text: 'Vuelve a iniciar sesión',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.spacingL),

        // Nota de spam
        Container(
          padding: const EdgeInsets.all(AppDimensions.paddingM),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.warning.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Si no encuentras el correo, revisa tu carpeta de spam.',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.spacingXL),

        // Botón volver a login
        CustomButton.primary(
          text: 'Volver a iniciar sesión',
          onPressed: () => context.go('/login'),
        ),
        const SizedBox(height: AppDimensions.spacingM),

        // Reenviar email (con cooldown)
        TextButton(
          onPressed: _canResend
              ? () {
                  setState(() {
                    _emailSent = false;
                  });
                }
              : null,
          child: Text(
            _canResend
                ? '¿No recibiste el correo? Reenviar'
                : 'Reenviar en ${_resendCooldown}s',
            style: AppTextStyles.body2.copyWith(
              color: _canResend ? AppColors.primary : AppColors.disabled,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  /// Item de instrucción
  Widget _buildInstructionItem({
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.body2.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
