import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Servicio de autenticación con Firebase
/// Maneja login, registro y verificación de usuarios
/// Usa verificación por link nativo de Firebase (gratis)
class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ============================================================================
  // GETTERS
  // ============================================================================

  /// Usuario actual (null si no está autenticado)
  User? get currentUser => _auth.currentUser;

  /// Stream de cambios de autenticación
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Verificar si hay usuario autenticado
  bool get isAuthenticated => _auth.currentUser != null;

  /// Verificar si el email está verificado
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Refrescar token de autenticación
  /// Útil antes de operaciones largas como subir fotos
  Future<void> refreshToken() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.getIdToken(true);
    }
  }

  // ============================================================================
  // FLUJO DE REGISTRO (Verificación por link nativo de Firebase)
  // ============================================================================

  /// PASO 1: Iniciar registro
  ///
  /// Crea usuario en Firebase Auth y envía email de verificación.
  /// El usuario NO está verificado hasta que haga clic en el link.
  ///
  /// Retorna:
  /// - userId: ID del usuario creado
  Future<String> initiateRegistration({
    required String email,
    required String password,
  }) async {
    try {
      // 1. Validar email @uide.edu.ec
      if (!email.endsWith('@uide.edu.ec')) {
        throw Exception('Solo se permiten correos @uide.edu.ec');
      }

      // 2. Crear usuario en Firebase Auth
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('Error al crear usuario');
      }

      // 3. Enviar email de verificación (nativo de Firebase)
      await credential.user!.sendEmailVerification();

      return credential.user!.uid;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (e) {
      if (e is Exception) rethrow; // Allow original exception to bubble up
      throw Exception('Error desconocido: ${e.toString()}'); // Show actual error
    }
  }

  /// PASO 2: Verificar si el email ya fue verificado
  ///
  /// Recarga el usuario y verifica el estado de emailVerified.
  /// Usar para polling cada 3 segundos.
  Future<bool> checkEmailVerified() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Recargar usuario para obtener estado actualizado
      await user.reload();

      // Obtener usuario actualizado
      final updatedUser = _auth.currentUser;
      return updatedUser?.emailVerified ?? false;
    } catch (e) {
      return false;
    }
  }

  /// PASO 2.5: Reenviar email de verificación
  Future<void> resendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado');
      }

      if (user.emailVerified) {
        throw Exception('El correo ya está verificado');
      }

      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error al reenviar email de verificación');
    }
  }

  /// PASO FINAL: Completar registro
  ///
  /// Guarda los datos del perfil en Firestore.
  /// Se llama solo cuando el usuario completó todos los pasos.
  /// El usuario debe estar autenticado y con email verificado.
  ///
  /// Retorna:
  /// - userId: ID del usuario
  Future<String> completeRegistration({
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String career,
    required int semester,
    required String role,
    Map<String, dynamic>? vehicle,
  }) async {
    try {
      // Refrescar el token antes de llamar a la función
      // Esto evita errores de "unauthenticated" si el proceso de registro fue largo
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado. Inicia sesión nuevamente.');
      }

      // Forzar refresh del token
      await user.getIdToken(true);

      final result = await _functions.httpsCallable('completeRegistration').call({
        'firstName': firstName,
        'lastName': lastName,
        'phoneNumber': phoneNumber,
        'career': career,
        'semester': semester,
        'role': role,
        'vehicle': vehicle,
      });

      return result.data['userId'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw _handleFunctionsError(e);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error de red. Verifica tu conexión.');
    }
  }

  /// Verificar estado del registro (si tiene perfil completo)
  Future<Map<String, dynamic>> checkRegistrationStatus() async {
    try {
      final result = await _functions.httpsCallable('checkRegistrationStatus').call({});

      return {
        'exists': result.data['exists'] as bool,
        'isProfileComplete': result.data['isProfileComplete'] as bool,
        'role': result.data['role'],
        'hasVehicle': result.data['hasVehicle'] as bool? ?? false,
      };
    } on FirebaseFunctionsException catch (e) {
      throw _handleFunctionsError(e);
    } catch (e) {
      throw Exception('Error de red. Verifica tu conexión.');
    }
  }

  /// Registrar vehículo (post-login)
  /// Para usuarios que ya completaron registro sin vehículo
  Future<void> registerVehicle({
    required Map<String, dynamic> vehicle,
  }) async {
    try {
      // Refrescar token antes de operación
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado. Inicia sesión nuevamente.');
      }
      await user.getIdToken(true);

      await _functions.httpsCallable('registerVehicle').call({
        'vehicle': vehicle,
      });
    } on FirebaseFunctionsException catch (e) {
      throw _handleFunctionsError(e);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error de red. Verifica tu conexión.');
    }
  }

  // ============================================================================
  // LOGIN
  // ============================================================================

  /// Iniciar sesión con email y contraseña
  Future<User> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('Error al iniciar sesión');
      }

      return credential.user!;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (e) {
      throw Exception('Error al iniciar sesión: ${e.toString()}');
    }
  }

  /// Cerrar sesión
  Future<void> logout() async {
    await _auth.signOut();
  }

  /// Eliminar cuenta actual (para registros incompletos)
  Future<void> deleteCurrentUser() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.delete();
      }
    } catch (e) {
      // Ignorar errores al eliminar
    }
  }

  /// Eliminar cuenta actual con re-autenticación
  /// Firebase requiere autenticación reciente para eliminar cuenta
  Future<void> deleteCurrentUserWithReauth({
    required String email,
    required String password,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Re-autenticar al usuario antes de eliminar
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        await user.reauthenticateWithCredential(credential);

        // Ahora sí eliminar
        await user.delete();
      }
    } catch (e) {
      // Si falla la re-autenticación, intentar eliminar de todas formas
      try {
        final user = _auth.currentUser;
        if (user != null) {
          await user.delete();
        }
      } catch (_) {
        // Ignorar errores secundarios
      }
    }
  }

  // ============================================================================
  // RECUPERACIÓN DE CONTRASEÑA
  // ============================================================================

  /// Enviar email para recuperar contraseña
  Future<void> resetPassword({required String email}) async {
    try {
      // Validar dominio
      if (!email.endsWith('@uide.edu.ec')) {
        throw Exception('Solo se permiten correos @uide.edu.ec');
      }

      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthError(e));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error al enviar email de recuperación');
    }
  }

  // ============================================================================
  // MANEJO DE ERRORES
  // ============================================================================

  /// Manejo de errores de Firebase Functions
  String _handleFunctionsError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'already-exists':
        return e.message ?? 'El correo ya está registrado';
      case 'invalid-argument':
        return e.message ?? 'Datos inválidos';
      case 'not-found':
        return e.message ?? 'No encontrado';
      case 'deadline-exceeded':
        return e.message ?? 'Tiempo expirado';
      case 'failed-precondition':
        return e.message ?? 'El correo no ha sido verificado';
      case 'unauthenticated':
        return 'No autorizado. Inicia sesión nuevamente.';
      case 'permission-denied':
        return 'Permiso denegado';
      case 'unavailable':
        return 'Servicio no disponible. Intenta más tarde.';
      case 'internal':
        return e.message ?? 'Error interno del servidor';
      default:
        return e.message ?? 'Error desconocido';
    }
  }

  /// Manejo de errores de Firebase Auth
  String _handleAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Usuario no encontrado';
      case 'wrong-password':
        return 'Contraseña incorrecta';
      case 'invalid-email':
        return 'Correo inválido';
      case 'user-disabled':
        return 'Usuario deshabilitado';
      case 'email-already-in-use':
        return 'El correo ya está en uso';
      case 'weak-password':
        return 'Contraseña muy débil (mínimo 6 caracteres)';
      case 'operation-not-allowed':
        return 'Operación no permitida';
      case 'network-request-failed':
        return 'Error de red. Verifica tu conexión.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde.';
      case 'invalid-credential':
        return 'Credenciales inválidas';
      default:
        return e.message ?? 'Error de autenticación';
    }
  }
}
