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
class RegisterVehicleEvent extends RegistrationEvent {
  final String brand;
  final String model;
  final int year;
  final String color;
  final String plate;
  final int capacity;
  final bool hasAirConditioning;
  final File vehiclePhoto;
  final File licensePhoto;

  const RegisterVehicleEvent({
    required this.brand,
    required this.model,
    required this.year,
    required this.color,
    required this.plate,
    required this.capacity,
    required this.hasAirConditioning,
    required this.vehiclePhoto,
    required this.licensePhoto,
  });

  @override
  List<Object?> get props => [
        brand,
        model,
        year,
        color,
        plate,
        capacity,
        hasAirConditioning,
        vehiclePhoto,
        licensePhoto,
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
