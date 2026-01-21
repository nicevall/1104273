import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/firebase_auth_service.dart';
import '../../../data/services/firestore_service.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// BLoC de autenticación
/// Maneja login, logout y verificación de sesión
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final FirebaseAuthService _authService;
  final FirestoreService _firestoreService;

  // Suscripción al stream de autenticación
  StreamSubscription? _authSubscription;

  AuthBloc({
    required FirebaseAuthService authService,
    required FirestoreService firestoreService,
  })  : _authService = authService,
        _firestoreService = firestoreService,
        super(const AuthInitial()) {
    // Registrar handlers de eventos
    on<CheckAuthStatusEvent>(_onCheckAuthStatus);
    on<LoginEvent>(_onLogin);
    on<LogoutEvent>(_onLogout);
    on<UpdateUserEvent>(_onUpdateUser);

    // Escuchar cambios de autenticación de Firebase
    _authSubscription = _authService.authStateChanges.listen((firebaseUser) {
      if (firebaseUser != null) {
        // Usuario autenticado, cargar datos de Firestore
        add(const UpdateUserEvent());
      } else {
        // Usuario no autenticado
        if (state is! Unauthenticated) {
          emit(const Unauthenticated());
        }
      }
    });
  }

  /// Verificar estado de autenticación al iniciar la app
  Future<void> _onCheckAuthStatus(
    CheckAuthStatusEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final firebaseUser = _authService.currentUser;

      if (firebaseUser == null) {
        // No hay usuario autenticado
        emit(const Unauthenticated());
        return;
      }

      // Obtener datos del usuario desde Firestore
      final user = await _firestoreService.getUser(firebaseUser.uid);

      if (user == null) {
        // Usuario existe en Auth pero no en Firestore (raro, error de sincronización)
        await _authService.logout();
        emit(const Unauthenticated());
        return;
      }

      // Verificar si el usuario completó la verificación OTP
      if (!user.isVerified) {
        emit(AuthenticatedNotVerified(
          userId: user.userId,
          email: user.email,
        ));
        return;
      }

      // Usuario completamente autenticado y verificado
      emit(Authenticated(user: user));
    } catch (e) {
      emit(AuthError(error: 'Error al verificar autenticación: $e'));
    }
  }

  /// Login con email y contraseña
  Future<void> _onLogin(
    LoginEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      // Login en Firebase Auth
      final firebaseUser = await _authService.login(
        email: event.email,
        password: event.password,
      );

      // Obtener datos del usuario desde Firestore
      final user = await _firestoreService.getUser(firebaseUser.uid);

      if (user == null) {
        // Usuario no existe en Firestore (inconsistencia)
        await _authService.logout();
        emit(const AuthError(
          error: 'Usuario no encontrado en la base de datos',
        ));
        return;
      }

      // Verificar si completó la verificación OTP
      if (!user.isVerified) {
        emit(AuthenticatedNotVerified(
          userId: user.userId,
          email: user.email,
        ));
        return;
      }

      // Login exitoso
      emit(Authenticated(user: user));
    } catch (e) {
      // Error de autenticación
      emit(AuthError(error: e.toString()));
    }
  }

  /// Logout del usuario actual
  Future<void> _onLogout(
    LogoutEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _authService.logout();
      emit(const Unauthenticated());
    } catch (e) {
      emit(AuthError(error: 'Error al cerrar sesión: $e'));
    }
  }

  /// Actualizar datos del usuario en sesión
  ///
  /// Se llama cuando:
  /// - El usuario actualiza su perfil
  /// - Se detecta cambio en Firebase Auth
  /// - Se completa el registro
  Future<void> _onUpdateUser(
    UpdateUserEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final firebaseUser = _authService.currentUser;

      if (firebaseUser == null) {
        emit(const Unauthenticated());
        return;
      }

      // Obtener datos actualizados de Firestore
      final user = await _firestoreService.getUser(firebaseUser.uid);

      if (user == null) {
        await _authService.logout();
        emit(const Unauthenticated());
        return;
      }

      // Verificar si está verificado
      if (!user.isVerified) {
        emit(AuthenticatedNotVerified(
          userId: user.userId,
          email: user.email,
        ));
        return;
      }

      emit(Authenticated(user: user));
    } catch (e) {
      // No emitir error aquí, mantener estado actual
      // Solo logear el error
      print('Error al actualizar usuario: $e');
    }
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
