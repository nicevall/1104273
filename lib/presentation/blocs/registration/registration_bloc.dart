import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/firebase_auth_service.dart';
import '../../../data/services/firebase_storage_service.dart';
import '../../../data/services/firestore_service.dart';
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
  final FirestoreService _firestoreService;

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
    required FirestoreService firestoreService,
  })  : _authService = authService,
        _storageService = storageService,
        _firestoreService = firestoreService,
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
    on<ResumeRegistrationEvent>(_onResumeRegistration);
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
      // RECUPERACIÓN: Si el correo ya existe, intentar loguear y continuar
      if (e.toString().contains('El correo ya está en uso')) {
        try {
          final user = await _authService.login(
            email: event.email,
            password: event.password,
          );

          _userId = user.uid;
          _email = event.email;

          // Verificar si ya validó el email para saltar al paso correcto
          if (user.emailVerified) {
             emit(RegistrationStep3(userId: user.uid));
          } else {
             emit(RegistrationStep2(userId: user.uid, email: event.email));
          }
          return;
        } catch (loginError) {
          // Si falla el login (ej. contraseña incorrecta), mostrar mensaje orientativo
          emit(const RegistrationFailure(
            error: 'Este correo ya está registrado. Si es tu cuenta, inicia sesión para continuar con el registro.',
            step: 1,
          ));
          return;
        }
      }

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
  /// Verifica número duplicado y guarda datos LOCALMENTE
  Future<void> _onRegisterStep3(
    RegisterStep3Event event,
    Emitter<RegistrationState> emit,
  ) async {
    final currentState = state;

    // Obtener userId del estado actual
    String? userId;
    if (currentState is RegistrationStep3) {
      userId = currentState.userId;
    } else if (_userId != null) {
      // Si venimos de ResumeRegistrationEvent, usar _userId guardado
      userId = _userId;
    }

    if (userId == null) return;

    emit(const RegistrationLoading(step: 3));

    try {
      // Verificar si el número de celular ya está registrado
      final isPhoneTaken = await _firestoreService.isPhoneNumberTaken(
        event.phoneNumber,
        excludeUserId: userId,
      );

      if (isPhoneTaken) {
        emit(const RegistrationFailure(
          error: 'Este número de celular ya está registrado',
          step: 3,
        ));
        // Volver al estado Step 3 para que pueda corregir
        emit(RegistrationStep3(userId: userId));
        return;
      }

      // Guardar datos LOCALMENTE (no se envían al backend todavía)
      _firstName = event.firstName;
      _lastName = event.lastName;
      _phoneNumber = event.phoneNumber;
      _career = event.career;
      _semester = event.semester;

      // Avanzar a Step 4
      emit(RegistrationStep4(userId: userId));
    } on SocketException {
      emit(const RegistrationNetworkError(step: 3));
      emit(RegistrationStep3(userId: userId));
    } catch (e) {
      emit(RegistrationFailure(
        error: 'Error al verificar datos: $e',
        step: 3,
      ));
      emit(RegistrationStep3(userId: userId));
    }
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

  /// Step 5: Confirmar advertencia y REGISTRAR USUARIO
  /// NUEVO FLUJO: Siempre se registra al usuario aquí, sin importar el rol
  /// El registro de vehículo ahora es un paso separado post-login
  Future<void> _onRegisterStep5Confirm(
    RegisterStep5ConfirmEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    final currentState = state;
    if (currentState is! RegistrationStep5) return;

    // SIEMPRE registrar al usuario aquí (sin vehículo)
    // El registro de vehículo se hace después del login si es necesario
    add(const CompleteRegistrationEvent());
  }

  /// Step 6 (Condicional): Registrar vehículo y completar
  /// AQUÍ se envía TODO al backend
  /// Datos extraídos mediante OCR de matrícula y licencia
  Future<void> _onRegisterVehicle(
    RegisterVehicleEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    emit(const RegistrationLoading(step: 6));

    try {
      final userId = event.userId;

      // 0. Refrescar token antes de operaciones largas
      // Esto evita errores de "unauthenticated" si el proceso de registro fue largo
      await _authService.refreshToken();

      // 1. Subir foto del vehículo
      final vehiclePhotoUrl = await _storageService.uploadVehiclePhoto(
        userId: userId,
        imageFile: event.vehiclePhoto,
      );

      // 2. Subir foto de licencia
      final licensePhotoUrl = await _storageService.uploadLicensePhoto(
        userId: userId,
        imageFile: event.licensePhoto,
      );

      // 3. Subir foto de matrícula
      final registrationPhotoUrl = await _storageService.uploadRegistrationPhoto(
        userId: userId,
        imageFile: event.registrationPhoto,
      );

      // 4. Completar registro con TODOS los datos extraídos por OCR
      await _authService.completeRegistration(
        firstName: _firstName!,
        lastName: _lastName!,
        phoneNumber: _phoneNumber!,
        career: _career!,
        semester: _semester!,
        role: _role!,
        vehicle: {
          // Datos del vehículo extraídos de matrícula
          'brand': event.brand,
          'model': event.model,
          'year': event.year,
          'color': event.color,
          'plate': event.plate,
          'vinChasis': event.vinChasis,
          'claseVehiculo': event.claseVehiculo,
          'pasajeros': event.pasajeros,
          // URLs de fotos (para verificación manual)
          'photoUrl': vehiclePhotoUrl,
          'licensePhotoUrl': licensePhotoUrl,
          'registrationPhotoUrl': registrationPhotoUrl,
          // Datos de licencia extraídos
          'licenseNumber': event.licenseNumber,
          'licenseHolderName': event.licenseHolderName,
          'licenseCategory': event.licenseCategory,
          'licenseExpiration': event.licenseExpiration,
          // Relación propietario/conductor
          'vehicleOwnership': event.vehicleOwnership,
          'driverRelation': event.driverRelation,
          // Metadata
          'verifiedAt': DateTime.now().toIso8601String(),
          'verified': false, // Pendiente de verificación manual
        },
      );

      // Registro completado
      emit(RegistrationSuccess(
        userId: userId,
        role: _role ?? 'conductor',
        hasVehicle: true,
      ));

      _resetTempData();
    } on SocketException {
      emit(const RegistrationNetworkError(step: 6));
    } catch (e) {
      emit(RegistrationFailure(
        error: 'Error al registrar: ${e.toString()}',
        step: 6,
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
  /// RESTRICCIONES:
  /// - Step 2 NO puede volver a Step 1 (email/contraseña ya en Auth)
  /// - Step 3 NO puede volver a Step 2 (email ya verificado)
  void _onGoBack(
    GoBackEvent event,
    Emitter<RegistrationState> emit,
  ) {
    final currentState = state;

    // Desde Step 5 → volver a Step 4
    if (currentState is RegistrationStep5) {
      _role = null; // Limpiar el rol seleccionado
      emit(RegistrationStep4(userId: currentState.userId));
      return;
    }

    // Desde RegistrationVehicle → volver a Step 5
    if (currentState is RegistrationVehicle) {
      emit(RegistrationStep5(
        userId: currentState.userId,
        role: currentState.role,
      ));
      return;
    }

    // Desde Step 4 → volver a Step 3
    if (currentState is RegistrationStep4) {
      emit(RegistrationStep3(userId: currentState.userId));
      return;
    }

    // Step 3 NO puede volver a Step 2 (email ya verificado, no tiene sentido)
    // Step 2 NO puede volver a Step 1 (email/contraseña ya registrados en Auth)
    // En estos casos, no emitimos nada - el usuario debe continuar o cancelar
  }

  /// Reanudar registro incompleto
  /// Para usuarios que existen en Auth pero no completaron el registro
  void _onResumeRegistration(
    ResumeRegistrationEvent event,
    Emitter<RegistrationState> emit,
  ) {
    // Inicializar datos del usuario existente
    _userId = event.userId;
    _email = event.email;

    // Emitir Step 3 para continuar el registro
    emit(RegistrationStep3(userId: event.userId));
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
