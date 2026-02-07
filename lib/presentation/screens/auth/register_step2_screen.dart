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
  bool _canResend = true;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
    // Iniciar cooldown automáticamente al cargar la pantalla
    // ya que el email ya fue enviado en Step 1
    _startCooldown();
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
      context.read<RegistrationBloc>().add(const CheckEmailVerifiedEvent());
    });
  }

  /// Iniciar cooldown de reenvío
  void _startCooldown() {
    setState(() {
      _canResend = false;
      _resendCooldown = 30; // 30 segundos iniciales (el email tarda en llegar)
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

  /// Reenviar email de verificación
  void _handleResendEmail() {
    if (!_canResend) return;

    context.read<RegistrationBloc>().add(const ResendVerificationEmailEvent());

    // Iniciar cooldown de 60 segundos
    _startCooldown();
  }

  /// Mostrar diálogo de que no puede volver
  void _showCannotGoBackDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No puedes volver'),
        content: const Text(
          'Tu correo y contraseña ya fueron registrados. Debes verificar tu correo para continuar.\n\n'
          'Si deseas cancelar el registro, usa el botón "Cancelar registro" más abajo.',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: Text(
                'Entendido',
                style: AppTextStyles.button.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cancelar registro
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
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    setState(() {
                      _isCancelling = true;
                    });
                    // Cancelar timers
                    _pollingTimer?.cancel();
                    _cooldownTimer?.cancel();
                    // Enviar evento y esperar un momento para que se procese
                    context.read<RegistrationBloc>().add(const CancelRegistrationEvent());
                    // Esperar a que se elimine el usuario
                    await Future.delayed(const Duration(milliseconds: 500));
                    if (mounted) {
                      context.go('/welcome');
                    }
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
          automaticallyImplyLeading: false, // Sin flecha de retroceso
          title: Text(
            'Verificación',
            style: AppTextStyles.h3.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          centerTitle: true,
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
          if (_isCancelling) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text('Cancelando registro...'),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.paddingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
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
                const SizedBox(height: AppDimensions.spacingS),

                // Nota sobre spam (más visible con icono y color)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Revisa también tu carpeta de spam',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingL),

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
                        text: 'Vuelve aquí, te detectamos automáticamente',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingM),

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
                const SizedBox(height: AppDimensions.spacingL),

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

                // Botón cancelar registro - Rojo sólido con letras blancas
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _handleCancelRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Cancelar registro',
                      style: AppTextStyles.button.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppDimensions.spacingL),
              ],
            ),
          );
        },
        ),
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
