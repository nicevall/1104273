// ignore_for_file: avoid_print
/// Script para verificar si los usuarios de prueba existen
/// Ejecutar desde la app con: CheckTestUsers.check()

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CheckTestUsers {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Verificar si los usuarios de prueba existen en Firestore
  /// NOTA: Requiere estar autenticado para funcionar
  static Future<Map<String, bool>> check() async {
    final results = <String, bool>{};

    try {
      // Verificar pasajero
      final pasajeroQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: 'p@uide.edu.ec')
          .limit(1)
          .get();

      results['pasajero'] = pasajeroQuery.docs.isNotEmpty;

      // Verificar conductor
      final conductorQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: 'c@uide.edu.ec')
          .limit(1)
          .get();

      results['conductor'] = conductorQuery.docs.isNotEmpty;
    } catch (e) {
      // Si hay error de permisos, retornar unknown
      print('Error checking Firestore: $e');
      results['pasajero'] = false;
      results['conductor'] = false;
      results['error'] = true;
    }

    return results;
  }

  /// Verificar si el login funciona para los usuarios de prueba
  /// Retorna mapa con el resultado del login para cada usuario
  /// Este método NO requiere estar autenticado previamente
  static Future<Map<String, String>> checkLogin() async {
    final results = <String, String>{};
    const password = '123456';

    // Test pasajero login
    try {
      await _auth.signInWithEmailAndPassword(
        email: 'p@uide.edu.ec',
        password: password,
      );
      results['pasajero'] = 'OK';
      await _auth.signOut();
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('user-not-found')) {
        results['pasajero'] = 'No existe en Auth';
      } else if (errorStr.contains('wrong-password') || errorStr.contains('invalid-credential')) {
        results['pasajero'] = 'Contraseña incorrecta';
      } else if (errorStr.contains('network')) {
        results['pasajero'] = 'Error de red';
      } else {
        results['pasajero'] = 'Error: ${errorStr.length > 50 ? errorStr.substring(0, 50) : errorStr}';
      }
    }

    // Test conductor login
    try {
      await _auth.signInWithEmailAndPassword(
        email: 'c@uide.edu.ec',
        password: password,
      );
      results['conductor'] = 'OK';
      await _auth.signOut();
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('user-not-found')) {
        results['conductor'] = 'No existe en Auth';
      } else if (errorStr.contains('wrong-password') || errorStr.contains('invalid-credential')) {
        results['conductor'] = 'Contraseña incorrecta';
      } else if (errorStr.contains('network')) {
        results['conductor'] = 'Error de red';
      } else {
        results['conductor'] = 'Error: ${errorStr.length > 50 ? errorStr.substring(0, 50) : errorStr}';
      }
    }

    return results;
  }

  /// Verificación SOLO por login (no requiere permisos Firestore)
  /// Usar este método cuando no se está autenticado
  static Future<Map<String, String>> quickCheck() async {
    return await checkLogin();
  }

  /// Verificación completa: Firestore + Auth
  /// NOTA: La verificación de Firestore puede fallar si no hay usuario autenticado
  static Future<Map<String, dynamic>> fullCheck() async {
    // Solo hacer check de login, que no requiere permisos
    final loginResults = await checkLogin();

    return {
      'login': loginResults,
    };
  }
}
