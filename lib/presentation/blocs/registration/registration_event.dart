import 'dart:io';
import 'package:equatable/equatable.dart';

/// Eventos del flujo de registro
/// Representa cada paso del proceso de registro
///
/// FLUJO CON VERIFICACIÓN POR LINK:
/// Step 1: Crear usuario + enviar email
/// Step 2: Verificar email (polling o manual)
/// Step 3-5: Completar perfil
abstract class RegistrationEvent extends Equatable {
  const RegistrationEvent();

  @override
  List<Object?> get props => [];
}

/// Iniciar proceso de registro
/// Resetea el estado a Step 1
class StartRegistrationEvent extends RegistrationEvent {
  const StartRegistrationEvent();
}

/// Step 1: Registro de credenciales básicas
/// Email @uide.edu.ec, contraseña, confirmación
class RegisterStep1Event extends RegistrationEvent {
  final String email;
  final String password;
  final String passwordConfirmation;

  const RegisterStep1Event({
    required this.email,
    required this.password,
    required this.passwordConfirmation,
  });

  @override
  List<Object?> get props => [email, password, passwordConfirmation];
}

/// Step 2: Verificar si el email ya fue verificado
/// Usado para polling automático y botón manual
class CheckEmailVerifiedEvent extends RegistrationEvent {
  const CheckEmailVerifiedEvent();
}

/// Step 2: Reenviar email de verificación
class ResendVerificationEmailEvent extends RegistrationEvent {
  const ResendVerificationEmailEvent();
}

/// Step 3: Información adicional del usuario
/// Nombre, apellido, teléfono, carrera, semestre
class RegisterStep3Event extends RegistrationEvent {
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String career;
  final int semester;

  const RegisterStep3Event({
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.career,
    required this.semester,
  });

  @override
  List<Object?> get props => [
        firstName,
        lastName,
        phoneNumber,
        career,
        semester,
      ];
}

/// Step 4: Selección de rol
/// Valores: 'pasajero', 'conductor', 'ambos'
class RegisterStep4Event extends RegistrationEvent {
  final String role;

  const RegisterStep4Event({required this.role});

  @override
  List<Object?> get props => [role];
}

/// Step 5: Confirmar advertencia de pantalla completa
/// Usuario acepta términos y condiciones
class RegisterStep5ConfirmEvent extends RegistrationEvent {
  const RegisterStep5ConfirmEvent();
}

/// Step 6 (Condicional): Registrar vehículo
/// Solo para rol 'conductor' o 'ambos'
/// Incluye verificación KYC de documentos
/// Datos extraídos mediante OCR de matrícula y licencia
class RegisterVehicleEvent extends RegistrationEvent {
  final String userId;
  final File vehiclePhoto;
  final File registrationPhoto; // Foto de matrícula vehicular
  final File licensePhoto;
  final Map<String, String> vehicleData; // Datos extraídos de matrícula
  final Map<String, dynamic>? licenseData; // Datos extraídos de licencia
  final String vehicleOwnership; // 'mio', 'familiar', 'amigo'
  final String driverRelation; // 'yo', 'familiar', 'amigo'

  const RegisterVehicleEvent({
    required this.userId,
    required this.vehiclePhoto,
    required this.registrationPhoto,
    required this.licensePhoto,
    required this.vehicleData,
    this.licenseData,
    required this.vehicleOwnership,
    required this.driverRelation,
  });

  // Getters para acceder a los datos del vehículo
  String get brand => vehicleData['marca'] ?? '';
  String get model => vehicleData['modelo'] ?? '';
  String get year => vehicleData['año'] ?? '';
  String get color => vehicleData['color'] ?? '';
  String get plate => vehicleData['placa'] ?? '';
  String? get vinChasis => vehicleData['vin_chasis'];
  String? get claseVehiculo => vehicleData['clase_vehiculo'];
  String? get pasajeros => vehicleData['pasajeros'];

  // Getters para acceder a los datos de licencia
  String? get licenseNumber => licenseData?['numero_licencia'] as String?;
  String? get licenseHolderName => licenseData != null
      ? '${licenseData!['nombres'] ?? ''} ${licenseData!['apellidos'] ?? ''}'.trim()
      : null;
  String? get licenseCategory => licenseData?['categoria'] as String?;
  String? get licenseExpiration => licenseData?['fecha_vencimiento'] as String?;

  @override
  List<Object?> get props => [
        userId,
        vehiclePhoto,
        registrationPhoto,
        licensePhoto,
        vehicleData,
        licenseData,
        vehicleOwnership,
        driverRelation,
      ];
}

/// Completar registro sin vehículo
/// Para rol 'pasajero'
class CompleteRegistrationEvent extends RegistrationEvent {
  const CompleteRegistrationEvent();
}

/// Cancelar registro (eliminar usuario si existe)
class CancelRegistrationEvent extends RegistrationEvent {
  const CancelRegistrationEvent();
}

/// Volver al paso anterior
class GoBackEvent extends RegistrationEvent {
  const GoBackEvent();
}

/// Reanudar registro incompleto
/// Para usuarios que existen en Auth pero no completaron el registro
class ResumeRegistrationEvent extends RegistrationEvent {
  final String userId;
  final String email;

  const ResumeRegistrationEvent({
    required this.userId,
    required this.email,
  });

  @override
  List<Object?> get props => [userId, email];
}
