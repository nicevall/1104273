import 'package:equatable/equatable.dart';
import '../../../data/models/user_model.dart';

/// Estados de autenticación
/// Representa el estado actual de la sesión del usuario
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Estado inicial cuando se inicia la app
/// Se muestra splash screen durante este estado
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Verificando estado de autenticación
/// Se muestra loading indicator
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// Usuario autenticado correctamente
/// Contiene datos completos del usuario desde Firestore
class Authenticated extends AuthState {
  final UserModel user;

  const Authenticated({required this.user});

  @override
  List<Object?> get props => [user];

  /// Verificar si el usuario es conductor
  bool get isDriver => user.isDriver;

  /// Verificar si el usuario es pasajero
  bool get isPassenger => user.isPassenger;

  /// Verificar si el usuario está verificado
  bool get isVerified => user.isVerified;
}

/// Usuario no autenticado
/// Redirigir a pantalla de login
class Unauthenticated extends AuthState {
  const Unauthenticated();
}

/// Error de autenticación
/// Mostrar mensaje de error en UI
class AuthError extends AuthState {
  final String error;

  const AuthError({required this.error});

  @override
  List<Object?> get props => [error];
}

/// Usuario autenticado pero no verificado
/// Redirigir a pantalla de verificación OTP
class AuthenticatedNotVerified extends AuthState {
  final String userId;
  final String email;

  const AuthenticatedNotVerified({
    required this.userId,
    required this.email,
  });

  @override
  List<Object?> get props => [userId, email];
}
