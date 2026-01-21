import 'package:equatable/equatable.dart';

/// Eventos de autenticación
/// Representa acciones que el usuario puede realizar
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Verificar estado de autenticación al iniciar la app
/// Se dispara en main.dart para verificar si hay sesión activa
class CheckAuthStatusEvent extends AuthEvent {
  const CheckAuthStatusEvent();
}

/// Login con email y contraseña
class LoginEvent extends AuthEvent {
  final String email;
  final String password;

  const LoginEvent({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];
}

/// Logout del usuario actual
class LogoutEvent extends AuthEvent {
  const LogoutEvent();
}

/// Actualizar datos del usuario en sesión
/// Se dispara cuando el usuario actualiza su perfil
class UpdateUserEvent extends AuthEvent {
  const UpdateUserEvent();
}
