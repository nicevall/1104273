import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../blocs/registration/registration_bloc.dart';
import '../../blocs/registration/registration_event.dart';
import '../../blocs/registration/registration_state.dart';
import '../../widgets/common/progress_bar.dart';

/// Step 5: Confirmación de rol y términos
/// Diseño minimalista con fondo blanco
class RegisterStep5Screen extends StatefulWidget {
  final String userId;
  final String role;

  const RegisterStep5Screen({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  State<RegisterStep5Screen> createState() => _RegisterStep5ScreenState();
}

class _RegisterStep5ScreenState extends State<RegisterStep5Screen> {
  bool _acceptedTerms = false;

  /// Contenido según el rol
  Map<String, dynamic> get _content {
    switch (widget.role) {
      case 'pasajero':
        return {
          'icon': Icons.person,
          'title': 'Solo Pasajero',
          'subtitle': 'Podrás solicitar viajes compartidos',
          'warning': 'Esta elección es permanente. No podrás ofrecer viajes como conductor.',
        };
      case 'conductor':
        return {
          'icon': Icons.drive_eta,
          'title': 'Solo Conductor',
          'subtitle': 'Podrás ofrecer viajes y ganar dinero',
          'warning': 'Esta elección es permanente. No podrás solicitar viajes como pasajero.',
        };
      case 'ambos':
        return {
          'icon': Icons.swap_horiz,
          'title': 'Pasajero y Conductor',
          'subtitle': 'Alterna entre ambos roles según tu necesidad',
          'warning': 'Esta elección es permanente. Deberás registrar tu vehículo para ofrecer viajes.',
        };
      default:
        return {
          'icon': Icons.info_outline,
          'title': 'Rol no reconocido',
          'subtitle': '',
          'warning': 'Error: Rol no válido',
        };
    }
  }

  /// Aceptar y continuar
  void _handleAccept() {
    context.read<RegistrationBloc>().add(const RegisterStep5ConfirmEvent());
  }

  /// Volver al paso anterior
  void _handleGoBack() {
    context.read<RegistrationBloc>().add(const GoBackEvent());
  }

  /// Abrir pantalla de términos y condiciones
  void _openTermsAndConditions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TermsAndConditionsScreen(role: widget.role),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleGoBack();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: _handleGoBack,
            icon: const Icon(
              Icons.arrow_back,
              color: AppColors.textPrimary,
            ),
          ),
          title: Text(
            'Registro',
            style: AppTextStyles.h3.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
        body: BlocListener<RegistrationBloc, RegistrationState>(
          listener: (context, state) {
            if (state is RegistrationStep4) {
              context.go('/register/step4', extra: {
                'userId': state.userId,
              });
            } else if (state is RegistrationSuccess) {
              context.go('/home', extra: {
                'userId': state.userId,
                'userRole': state.role,
                'hasVehicle': state.hasVehicle,
              });
            } else if (state is RegistrationFailure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: ${state.error}'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          },
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.paddingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Barra de progreso
                  const ProgressBar(currentStep: 5),
                  const SizedBox(height: AppDimensions.spacingXL),

                  // Icono del rol
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        content['icon'] as IconData,
                        size: 50,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingL),

                  // Título
                  Center(
                    child: Text(
                      content['title'] as String,
                      style: AppTextStyles.h1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingS),

                  // Subtítulo
                  Center(
                    child: Text(
                      content['subtitle'] as String,
                      style: AppTextStyles.body1.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingL),

                  // Advertencia
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppDimensions.paddingM),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                      border: Border.all(
                        color: AppColors.warning,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.warning,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            content['warning'] as String,
                            style: AppTextStyles.body2.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Checkbox de términos con link
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _acceptedTerms = !_acceptedTerms;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(AppDimensions.paddingM),
                      decoration: BoxDecoration(
                        color: _acceptedTerms
                            ? AppColors.primary.withOpacity(0.05)
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                        border: Border.all(
                          color: _acceptedTerms
                              ? AppColors.primary
                              : AppColors.border,
                          width: _acceptedTerms ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _acceptedTerms
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: _acceptedTerms
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: AppTextStyles.body2.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                                children: [
                                  const TextSpan(text: 'He leído y acepto los '),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: _openTermsAndConditions,
                                      child: Text(
                                        'términos y condiciones',
                                        style: AppTextStyles.body2.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingL),

                  // Botón aceptar
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _acceptedTerms ? _handleAccept : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.disabled,
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                        ),
                      ),
                      child: Text(
                        'Aceptar y continuar',
                        style: AppTextStyles.button.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingM),

                  // Botón cancelar (rojo con relleno)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('¿Cancelar registro?'),
                            content: const Text(
                              '¿Estás seguro que deseas cancelar? Perderás todo el progreso.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('No'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  context.go('/welcome');
                                },
                                child: Text(
                                  'Sí, cancelar',
                                  style: TextStyle(color: AppColors.error),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                        ),
                      ),
                      child: Text(
                        'Cancelar registro',
                        style: AppTextStyles.button.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla de términos y condiciones completos
class TermsAndConditionsScreen extends StatelessWidget {
  final String role;

  const TermsAndConditionsScreen({
    super.key,
    required this.role,
  });

  List<Map<String, dynamic>> get _sections {
    final commonSections = [
      {
        'title': '1. Aceptación de Términos',
        'content': 'Al registrarte en UniRide, aceptas estos términos y condiciones en su totalidad. UniRide es una plataforma de carpooling exclusiva para estudiantes verificados de la Universidad Internacional del Ecuador (UIDE).',
      },
      {
        'title': '2. Elegibilidad',
        'content': 'Para usar UniRide debes:\n• Ser estudiante activo de UIDE con correo @uide.edu.ec\n• Ser mayor de 18 años\n• Proporcionar información veraz y actualizada',
      },
      {
        'title': '3. Privacidad y Datos',
        'content': 'Tus datos personales serán tratados conforme a la Ley Orgánica de Protección de Datos Personales de Ecuador. Solo compartimos información necesaria para facilitar los viajes.',
      },
      {
        'title': '4. Pagos',
        'content': 'Los pagos se realizan directamente entre usuarios en efectivo o transferencia bancaria. UniRide no procesa pagos ni cobra comisiones por los viajes.',
      },
      {
        'title': '5. Responsabilidad',
        'content': 'UniRide facilita la conexión entre usuarios pero NO es responsable por:\n• Accidentes de tránsito\n• Objetos olvidados\n• Comportamiento de otros usuarios\n• Retrasos o cancelaciones',
      },
      {
        'title': '6. Conducta',
        'content': 'Queda prohibido:\n• Discriminación de cualquier tipo\n• Acoso o comportamiento inapropiado\n• Consumo de alcohol o sustancias\n• Exceder la capacidad del vehículo',
      },
      {
        'title': '7. Suspensión',
        'content': 'UniRide puede suspender cuentas por:\n• Violación de términos\n• Calificaciones consistentemente bajas\n• Reportes de otros usuarios\n• Información falsa',
      },
      {
        'title': '8. Emergencias',
        'content': 'En caso de emergencia, contacta al ECU 911. UniRide no proporciona servicios de emergencia.',
      },
    ];

    // Agregar secciones específicas según el rol
    if (role == 'conductor' || role == 'ambos') {
      commonSections.insert(3, {
        'title': '3. Requisitos para Conductores',
        'content': 'Como conductor debes:\n• Tener licencia tipo B vigente emitida por la ANT\n• Matrícula vehicular al día\n• Revisión técnica vehicular vigente\n• SOAT vigente\n• Vehículo en buen estado mecánico y de aseo',
      });
    }

    if (role == 'pasajero' || role == 'ambos') {
      commonSections.insert(3, {
        'title': '3. Responsabilidades del Pasajero',
        'content': 'Como pasajero debes:\n• Llegar puntual al punto de encuentro\n• Respetar las normas del conductor\n• Usar cinturón de seguridad\n• Realizar el pago acordado\n• Calificar al conductor después del viaje',
      });
    }

    return commonSections;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.textPrimary,
          ),
        ),
        title: Text(
          'Términos y Condiciones',
          style: AppTextStyles.h3.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDimensions.paddingL),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppDimensions.radiusM),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 48,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppDimensions.spacingM),
                  Text(
                    'UniRide Ecuador',
                    style: AppTextStyles.h2.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingS),
                  Text(
                    'Última actualización: Febrero 2026',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.spacingXL),

            // Secciones
            ..._sections.map((section) => _buildSection(
                  section['title'] as String,
                  section['content'] as String,
                )),

            const SizedBox(height: AppDimensions.spacingXL),

            // Footer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDimensions.paddingM),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppDimensions.radiusM),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppDimensions.spacingS),
                  Text(
                    'Si tienes preguntas sobre estos términos, contacta a soporte@uniride.ec',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.h3.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingS),
          Text(
            content,
            style: AppTextStyles.body1.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
