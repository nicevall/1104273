import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../blocs/registration/registration_bloc.dart';
import '../../blocs/registration/registration_event.dart';
import '../../blocs/registration/registration_state.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/progress_bar.dart';

/// Step 2: Verificación de email por link
/// Usuario hace clic en el link enviado a su correo
/// Polling automático cada 3 segundos para detectar verificación
class RegisterStep2Screen extends StatefulWidget {
  final String userId;
  final String email;

  const RegisterStep2Screen({
    super.key,
    required this.userId,
    required this.email,
  });

  @override
  State<RegisterStep2Screen> createState() => _RegisterStep2ScreenState();
}

class _RegisterStep2ScreenState extends State<RegisterStep2Screen> {
  Timer? _pollingTimer;
  bool _isChecking = false;
  bool _canResend = true;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// Iniciar polling cada 3 segundos
  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_isChecking) {
        context.read<RegistrationBloc>().add(const CheckEmailVerifiedEvent());
      }
    });
  }

  /// Verificar manualmente
  void _handleCheckVerification() {
    if (_isChecking) return;

    setState(() {
      _isChecking = true;
    });

    context.read<RegistrationBloc>().add(const CheckEmailVerifiedEvent());

    // Resetear estado después de un momento
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    });
  }

  /// Reenviar email de verificación
  void _handleResendEmail() {
    if (!_canResend) return;

    context.read<RegistrationBloc>().add(const ResendVerificationEmailEvent());

    // Iniciar cooldown de 60 segundos
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

  /// Cancelar registro
  void _handleCancelRegistration() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar registro?'),
        content: const Text(
          '¿Estás seguro que deseas cancelar el registro? Tu cuenta será eliminada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<RegistrationBloc>().add(const CancelRegistrationEvent());
              context.go('/welcome');
            },
            child: const Text(
              'Sí, cancelar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
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
          onPressed: _handleCancelRegistration,
        ),
        title: Text(
          'Verificación',
          style: AppTextStyles.h3.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: BlocConsumer<RegistrationBloc, RegistrationState>(
        listener: (context, state) {
          if (state is RegistrationStep3) {
            // Email verificado - navegar a Step 3
            _pollingTimer?.cancel();
            context.push('/register/step3', extra: {'userId': state.userId});
          } else if (state is VerificationEmailResent) {
            // Mostrar confirmación de reenvío
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Email de verificación reenviado. Revisa tu correo.'),
                backgroundColor: AppColors.success,
              ),
            );
          } else if (state is RegistrationFailure) {
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
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.paddingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Barra de progreso
                const ProgressBar(currentStep: 2),
                const SizedBox(height: AppDimensions.spacingXL),

                // Icono de email
                Container(
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
                    Icons.mark_email_unread_outlined,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingL),

                // Título
                Text(
                  'Verifica tu correo',
                  style: AppTextStyles.h1,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimensions.spacingS),

                // Subtítulo con email
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: AppTextStyles.body1.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    children: [
                      const TextSpan(
                        text: 'Enviamos un link de verificación a\n',
                      ),
                      TextSpan(
                        text: widget.email,
                        style: AppTextStyles.body1.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
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
                        text: 'Abre tu bandeja de entrada',
                      ),
                      const SizedBox(height: 16),
                      _buildInstructionItem(
                        icon: Icons.link,
                        text: 'Haz clic en el link de verificación',
                      ),
                      const SizedBox(height: 16),
                      _buildInstructionItem(
                        icon: Icons.check_circle_outline,
                        text: 'Vuelve aquí y presiona el botón',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingL),

                // Indicador de polling
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.paddingM,
                    vertical: AppDimensions.paddingS,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.info,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Verificando automáticamente...',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.info,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingXL),

                // Botón verificar manualmente
                CustomButton.primary(
                  text: 'Ya verifiqué mi correo',
                  onPressed: _isChecking ? null : _handleCheckVerification,
                  isLoading: _isChecking,
                ),
                const SizedBox(height: AppDimensions.spacingM),

                // Botón reenviar
                TextButton.icon(
                  onPressed: _canResend ? _handleResendEmail : null,
                  icon: Icon(
                    Icons.refresh,
                    size: 18,
                    color: _canResend ? AppColors.primary : AppColors.disabled,
                  ),
                  label: Text(
                    _canResend
                        ? 'Reenviar email de verificación'
                        : 'Reenviar en ${_resendCooldown}s',
                    style: AppTextStyles.body2.copyWith(
                      color: _canResend ? AppColors.primary : AppColors.disabled,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: AppDimensions.spacingL),

                // Nota de ayuda
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
                          'Revisa también tu carpeta de spam si no encuentras el correo.',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
