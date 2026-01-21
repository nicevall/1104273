import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/firebase_auth_service.dart';
import '../../../data/services/firebase_storage_service.dart';
import 'registration_event.dart';
import 'registration_state.dart';

/// BLoC del flujo de registro
/// Maneja 5 pasos obligatorios + 1 opcional (vehículo)
///
/// FLUJO CON VERIFICACIÓN POR LINK (Firebase nativo):
/// - Step 1: Crear usuario en Auth + enviar email verificación
/// - Step 2: Esperar verificación por link (polling)
/// - Steps 3-5: Datos se guardan LOCALMENTE en el bloc
/// - Al completar: TODO se envía al backend en UNA sola llamada
class RegistrationBloc extends Bloc<RegistrationEvent, RegistrationState> {
  final FirebaseAuthService _authService;
  final FirebaseStorageService _storageService;

  // Estado temporal del registro (se guarda localmente durante los pasos)
  String? _userId;
  String? _email;
  String? _firstName;
  String? _lastName;
  String? _phoneNumber;
  String? _career;
  int? _semester;
  String? _role;

  RegistrationBloc({
    required FirebaseAuthService authService,
    required FirebaseStorageService storageService,
  })  : _authService = authService,
        _storageService = storageService,
        super(const RegistrationInitial()) {
    on<StartRegistrationEvent>(_onStartRegistration);
    on<RegisterStep1Event>(_onRegisterStep1);
    on<CheckEmailVerifiedEvent>(_onCheckEmailVerified);
    on<ResendVerificationEmailEvent>(_onResendVerificationEmail);
    on<RegisterStep3Event>(_onRegisterStep3);
    on<RegisterStep4Event>(_onRegisterStep4);
    on<RegisterStep5ConfirmEvent>(_onRegisterStep5Confirm);
    on<RegisterVehicleEvent>(_onRegisterVehicle);
    on<CompleteRegistrationEvent>(_onCompleteRegistration);
    on<CancelRegistrationEvent>(_onCancelRegistration);
    on<GoBackEvent>(_onGoBack);
  }

  /// Iniciar proceso de registro
  void _onStartRegistration(
    StartRegistrationEvent event,
    Emitter<RegistrationState> emit,
  ) {
    _resetTempData();
    emit(const RegistrationStep1());
  }

  /// Step 1: Crear usuario en Firebase Auth + enviar email de verificación
  Future<void> _onRegisterStep1(
    RegisterStep1Event event,
    Emitter<RegistrationState> emit,
  ) async {
    emit(const RegistrationLoading(step: 1));

    try {
      // Guardar datos localmente
      _email = event.email;

      // Crear usuario en Firebase Auth y enviar email de verificación
      final userId = await _authService.initiateRegistration(
        email: event.email,
        password: event.password,
      );

      // Guardar userId
      _userId = userId;

      // Avanzar a Step 2 (esperar verificación por link)
      emit(RegistrationStep2(
        userId: userId,
        email: event.email,
      ));
    } on SocketException {
      emit(const RegistrationNetworkError(step: 1));
    } catch (e) {
      emit(RegistrationFailure(
        error: e.toString(),
        step: 1,
      ));
    }
  }

  /// Step 2: Verificar si el email ya fue verificado
  /// Usado por polling automático y botón manual
  Future<void> _onCheckEmailVerified(
    CheckEmailVerifiedEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    final currentState = state;

    // Solo procesar si estamos en Step 2 o estados relacionados
    if (currentState is! RegistrationStep2 &&
        currentState is! VerificationEmailResent) return;

    try {
      final isVerified = await _authService.checkEmailVerified();

      if (isVerified) {
        // Email verificado - avanzar a Step 3
        emit(RegistrationStep3(userId: _userId!));
      }
      // Si no está verificado, no emitimos nada (el polling continuará)
    } catch (e) {
      // Ignorar errores de polling silenciosamente
    }
  }

  /// Step 2: Reenviar email de verificación
  Future<void> _onResendVerificationEmail(
    ResendVerificationEmailEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    final currentState = state;
    if (currentState is! RegistrationStep2 &&
        currentState is! VerificationEmailResent) return;

    try {
      await _authService.resendVerificationEmail();

      emit(VerificationEmailResent(
        userId: _userId!,
        email: _email!,
      ));

      // Volver a Step 2 después de mostrar confirmación
      emit(RegistrationStep2(
        userId: _userId!,
        email: _email!,
      ));
    } catch (e) {
      emit(RegistrationFailure(
        error: 'Error al reenviar email: ${e.toString()}',
        step: 2,
      ));
    }
  }

  /// Step 3: Información adicional del usuario
  /// Solo guarda datos LOCALMENTE - NO envía al backend
  Future<void> _onRegisterStep3(
    RegisterStep3Event event,
    Emitter<RegistrationState> emit,
  ) async {
    final currentState = state;
    if (currentState is! RegistrationStep3) return;

    // Guardar datos LOCALMENTE (no se envían al backend todavía)
    _firstName = event.firstName;
    _lastName = event.lastName;
    _phoneNumber = event.phoneNumber;
    _career = event.career;
    _semester = event.semester;

    // Avanzar a Step 4
    emit(RegistrationStep4(userId: currentState.userId));
  }

  /// Step 4: Selección de rol
  /// Solo guarda datos LOCALMENTE - NO envía al backend
  Future<void> _onRegisterStep4(
    RegisterStep4Event event,
    Emitter<RegistrationState> emit,
  ) async {
    final currentState = state;
    if (currentState is! RegistrationStep4) return;

    // Guardar rol LOCALMENTE
    _role = event.role;

    // Avanzar a Step 5 (advertencia)
    emit(RegistrationStep5(
      userId: currentState.userId,
      role: event.role,
    ));
  }

  /// Step 5: Confirmar advertencia
  void _onRegisterStep5Confirm(
    RegisterStep5ConfirmEvent event,
    Emitter<RegistrationState> emit,
  ) {
    final currentState = state;
    if (currentState is! RegistrationStep5) return;

    // Si es conductor o ambos, ir a registro de vehículo
    if (currentState.role == 'conductor' || currentState.role == 'ambos') {
      emit(RegistrationVehicle(
        userId: currentState.userId,
        role: currentState.role,
      ));
    } else {
      // Si es pasajero, completar registro
      add(const CompleteRegistrationEvent());
    }
  }

  /// Step 6 (Condicional): Registrar vehículo y completar
  /// AQUÍ se envía TODO al backend
  Future<void> _onRegisterVehicle(
    RegisterVehicleEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    final currentState = state;
    if (currentState is! RegistrationVehicle) return;

    emit(const RegistrationLoading(step: 5));

    try {
      // 1. Subir foto del vehículo
      final vehiclePhotoUrl = await _storageService.uploadVehiclePhoto(
        userId: currentState.userId,
        imageFile: event.vehiclePhoto,
      );

      // 2. Subir foto de licencia
      final licensePhotoUrl = await _storageService.uploadLicensePhoto(
        userId: currentState.userId,
        imageFile: event.licensePhoto,
      );

      // 3. Completar registro con TODOS los datos
      await _authService.completeRegistration(
        firstName: _firstName!,
        lastName: _lastName!,
        phoneNumber: _phoneNumber!,
        career: _career!,
        semester: _semester!,
        role: _role!,
        vehicle: {
          'brand': event.brand,
          'model': event.model,
          'year': event.year,
          'color': event.color,
          'plate': event.plate,
          'capacity': event.capacity,
          'hasAirConditioning': event.hasAirConditioning,
          'photoUrl': vehiclePhotoUrl,
          'licensePhotoUrl': licensePhotoUrl,
        },
      );

      // Registro completado
      emit(RegistrationSuccess(
        userId: currentState.userId,
        role: currentState.role,
        hasVehicle: true,
      ));

      _resetTempData();
    } on SocketException {
      emit(const RegistrationNetworkError(step: 5));
    } catch (e) {
      emit(RegistrationFailure(
        error: 'Error al registrar: ${e.toString()}',
        step: 5,
      ));
    }
  }

  /// Completar registro sin vehículo (pasajero)
  /// AQUÍ se envía TODO al backend
  Future<void> _onCompleteRegistration(
    CompleteRegistrationEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    final currentState = state;

    String userId;
    String role;

    if (currentState is RegistrationStep5) {
      userId = currentState.userId;
      role = currentState.role;
    } else {
      return;
    }

    emit(const RegistrationLoading(step: 5));

    try {
      // Completar registro con TODOS los datos (sin vehículo)
      await _authService.completeRegistration(
        firstName: _firstName!,
        lastName: _lastName!,
        phoneNumber: _phoneNumber!,
        career: _career!,
        semester: _semester!,
        role: role,
      );

      emit(RegistrationSuccess(
        userId: userId,
        role: role,
        hasVehicle: false,
      ));

      _resetTempData();
    } on SocketException {
      emit(const RegistrationNetworkError(step: 5));
    } catch (e) {
      emit(RegistrationFailure(
        error: 'Error al completar registro: ${e.toString()}',
        step: 5,
      ));
    }
  }

  /// Cancelar registro (eliminar usuario si existe)
  Future<void> _onCancelRegistration(
    CancelRegistrationEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    try {
      // Eliminar usuario si existe (registro incompleto)
      await _authService.deleteCurrentUser();
    } catch (e) {
      // Ignorar errores
    }

    _resetTempData();
    emit(const RegistrationInitial());
  }

  /// Volver al paso anterior
  void _onGoBack(
    GoBackEvent event,
    Emitter<RegistrationState> emit,
  ) {
    // Implementar si es necesario
  }

  /// Limpiar datos temporales
  void _resetTempData() {
    _userId = null;
    _email = null;
    _firstName = null;
    _lastName = null;
    _phoneNumber = null;
    _career = null;
    _semester = null;
    _role = null;
  }
}
