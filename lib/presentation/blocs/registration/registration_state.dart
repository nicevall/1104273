import 'package:equatable/equatable.dart';

/// Estados del flujo de registro
/// Representa en qué paso se encuentra el usuario
///
/// FLUJO CON VERIFICACIÓN POR LINK:
/// Step 1: Crear usuario + enviar email → userId
/// Step 2: Esperar verificación por link (polling)
/// Step 3-5: Completar perfil
abstract class RegistrationState extends Equatable {
  const RegistrationState();

  @override
  List<Object?> get props => [];

  /// Obtener número de paso actual (1-5)
  int get currentStep => 0;
}

/// Estado inicial del registro
class RegistrationInitial extends RegistrationState {
  const RegistrationInitial();

  @override
  int get currentStep => 0;
}

/// Step 1: Registro de email y contraseña
class RegistrationStep1 extends RegistrationState {
  const RegistrationStep1();

  @override
  int get currentStep => 1;
}

/// Step 2: Verificación de email por link
/// El usuario debe hacer clic en el link enviado a su correo
class RegistrationStep2 extends RegistrationState {
  final String userId;
  final String email;

  const RegistrationStep2({
    required this.userId,
    required this.email,
  });

  @override
  List<Object?> get props => [userId, email];

  @override
  int get currentStep => 2;
}

/// Step 3: Información adicional (nombre, teléfono, carrera)
/// Datos se guardan localmente hasta completar el registro
class RegistrationStep3 extends RegistrationState {
  final String userId;

  const RegistrationStep3({required this.userId});

  @override
  List<Object?> get props => [userId];

  @override
  int get currentStep => 3;
}

/// Step 4: Selección de rol (pasajero, conductor, ambos)
/// Datos se guardan localmente hasta completar el registro
class RegistrationStep4 extends RegistrationState {
  final String userId;

  const RegistrationStep4({required this.userId});

  @override
  List<Object?> get props => [userId];

  @override
  int get currentStep => 4;
}

/// Step 5: Advertencia de pantalla completa
/// Muestra términos y condiciones según el rol
class RegistrationStep5 extends RegistrationState {
  final String userId;
  final String role;

  const RegistrationStep5({
    required this.userId,
    required this.role,
  });

  @override
  List<Object?> get props => [userId, role];

  @override
  int get currentStep => 5;
}

/// Step 6 (Condicional): Registro de vehículo
/// Solo para 'conductor' o 'ambos'
class RegistrationVehicle extends RegistrationState {
  final String userId;
  final String role;

  const RegistrationVehicle({
    required this.userId,
    required this.role,
  });

  @override
  List<Object?> get props => [userId, role];

  @override
  int get currentStep => 5;
}

/// Estado de carga durante operaciones async
class RegistrationLoading extends RegistrationState {
  final int step;

  const RegistrationLoading({required this.step});

  @override
  List<Object?> get props => [step];

  @override
  int get currentStep => step;
}

/// Registro completado exitosamente
/// Redirige a home o pantalla de bienvenida
class RegistrationSuccess extends RegistrationState {
  final String userId;
  final String role;
  final bool hasVehicle;

  const RegistrationSuccess({
    required this.userId,
    required this.role,
    required this.hasVehicle,
  });

  @override
  List<Object?> get props => [userId, role, hasVehicle];
}

/// Error durante el registro
class RegistrationFailure extends RegistrationState {
  final String error;
  final int step;

  const RegistrationFailure({
    required this.error,
    required this.step,
  });

  @override
  List<Object?> get props => [error, step];

  @override
  int get currentStep => step;
}

/// Error de red (sin conexión)
class RegistrationNetworkError extends RegistrationState {
  final int step;

  const RegistrationNetworkError({required this.step});

  @override
  List<Object?> get props => [step];

  @override
  int get currentStep => step;
}

/// Email de verificación reenviado exitosamente
class VerificationEmailResent extends RegistrationState {
  final String userId;
  final String email;

  const VerificationEmailResent({
    required this.userId,
    required this.email,
  });

  @override
  List<Object?> get props => [userId, email];

  @override
  int get currentStep => 2;
}

/// Email verificado exitosamente (detectado por polling)
class EmailVerified extends RegistrationState {
  final String userId;

  const EmailVerified({required this.userId});

  @override
  List<Object?> get props => [userId];

  @override
  int get currentStep => 2;
}
