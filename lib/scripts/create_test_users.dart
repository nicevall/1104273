// ignore_for_file: avoid_print
/// Script para crear usuarios de prueba
/// Ejecutar desde la app con: CreateTestUsers.createAll()
///
/// Usuario 1: Solo pasajero (pasajero.test@uide.edu.ec)
/// Usuario 2: Solo conductor (conductor.test@uide.edu.ec) con vehículo fake
///
/// IMPORTANTE: Estos usuarios tienen bypass de verificación de email
/// porque son emails de prueba sin acceso real.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Constante del password para evitar typos
const String _testPassword = '123456';

/// Lista de emails de prueba que tienen bypass de verificación
/// Usar en AuthBloc y FirebaseAuthService para saltar verificación
class TestUsers {
  // Emails cortos para testing rápido
  static const String pasajeroEmail = 'p@uide.edu.ec';
  static const String conductorEmail = 'c@uide.edu.ec';

  static const List<String> testEmails = [
    pasajeroEmail,
    conductorEmail,
  ];

  /// Verificar si un email es de prueba (tiene bypass)
  static bool isTestEmail(String email) {
    return testEmails.contains(email.toLowerCase());
  }

  /// Password por defecto para usuarios de prueba
  static const String defaultPassword = '123456';
}

class CreateTestUsers {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Crear ambos usuarios de prueba
  static Future<void> createAll() async {
    print('=== Creando usuarios de prueba ===');
    print('Password para todos: ${TestUsers.defaultPassword}');
    print('');

    try {
      await createPassengerUser();
      print('');
      await createDriverUser();
      print('');
      print('=== Usuarios creados exitosamente ===');
      print('');
      print('📱 CREDENCIALES:');
      print('   Pasajero: pasajero.test@uide.edu.ec');
      print('   Conductor: conductor.test@uide.edu.ec');
      print('   Password: ${TestUsers.defaultPassword}');
    } catch (e) {
      print('Error creando usuarios: $e');
    }
  }

  /// Usuario 1: Solo pasajero
  static Future<void> createPassengerUser() async {
    const email = 'pasajero.test@uide.edu.ec';

    try {
      // Verificar si ya existe en Firestore
      final existingQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        print('✅ Pasajero ya existe en Firestore: $email');
        // Intentar login para verificar que funciona
        try {
          await _auth.signInWithEmailAndPassword(
            email: email,
            password: _testPassword,
          );
          print('✅ Login de prueba exitoso');
          await _auth.signOut();
        } catch (e) {
          print('⚠️ Usuario existe en Firestore pero login falló: $e');
        }
        return;
      }

      // Intentar crear en Firebase Auth
      String? userId;

      try {
        final userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: _testPassword,
        );
        userId = userCredential.user!.uid;
        print('🔑 Pasajero Auth creado: $userId');
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          print('⚠️ Email ya existe en Auth, intentando login...');
          // Intentar login
          try {
            final cred = await _auth.signInWithEmailAndPassword(
              email: email,
              password: _testPassword,
            );
            userId = cred.user!.uid;
            print('🔑 Login exitoso, userId: $userId');
          } catch (loginErr) {
            print('❌ No se pudo hacer login: $loginErr');
            print('💡 El usuario existe en Auth con otra contraseña.');
            print('   Debes eliminarlo manualmente desde Firebase Console.');
            return;
          }
        } else {
          print('❌ Error Auth: ${e.code} - ${e.message}');
          rethrow;
        }
      }

      if (userId == null) {
        print('❌ No se pudo obtener userId');
        return;
      }

      // Crear documento en Firestore
      await _firestore.collection('users').doc(userId).set({
        'userId': userId,
        'email': email,
        'firstName': 'Carlos',
        'lastName': 'Pasajero',
        'phoneNumber': '+593987654321',
        'career': 'Ingeniería en Software',
        'semester': 5,
        'role': 'pasajero',
        'isVerified': true, // BYPASS: Marcado como verificado
        'hasVehicle': false,
        'rating': 4.8,
        'totalTrips': 0,
        'profilePhotoUrl': 'https://picsum.photos/seed/passenger1/200/200',
        'isTestUser': true, // Marcar como usuario de prueba
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Pasajero creado completamente: $email');

      // Hacer logout para no interferir con la sesión actual
      await _auth.signOut();
    } catch (e) {
      print('❌ Error general: $e');
    }
  }

  /// Usuario 2: Solo conductor con vehículo
  static Future<void> createDriverUser() async {
    const email = 'conductor.test@uide.edu.ec';

    try {
      // Verificar si ya existe en Firestore
      final existingQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        print('✅ Conductor ya existe en Firestore: $email');
        // Intentar login para verificar que funciona
        try {
          await _auth.signInWithEmailAndPassword(
            email: email,
            password: _testPassword,
          );
          print('✅ Login de prueba exitoso');
          await _auth.signOut();
        } catch (e) {
          print('⚠️ Usuario existe en Firestore pero login falló: $e');
        }
        return;
      }

      // Intentar crear en Firebase Auth
      String? userId;

      try {
        final userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: _testPassword,
        );
        userId = userCredential.user!.uid;
        print('🔑 Conductor Auth creado: $userId');
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          print('⚠️ Email ya existe en Auth, intentando login...');
          try {
            final cred = await _auth.signInWithEmailAndPassword(
              email: email,
              password: _testPassword,
            );
            userId = cred.user!.uid;
            print('🔑 Login exitoso, userId: $userId');
          } catch (loginErr) {
            print('❌ No se pudo hacer login: $loginErr');
            print('💡 El usuario existe en Auth con otra contraseña.');
            print('   Debes eliminarlo manualmente desde Firebase Console.');
            return;
          }
        } else {
          print('❌ Error Auth: ${e.code} - ${e.message}');
          rethrow;
        }
      }

      if (userId == null) {
        print('❌ No se pudo obtener userId');
        return;
      }

      // Crear documento de usuario en Firestore
      await _firestore.collection('users').doc(userId).set({
        'userId': userId,
        'email': email,
        'firstName': 'María',
        'lastName': 'Conductora',
        'phoneNumber': '+593912345678',
        'career': 'Administración de Empresas',
        'semester': 7,
        'role': 'conductor',
        'isVerified': true, // BYPASS: Marcado como verificado
        'hasVehicle': true,
        'rating': 4.9,
        'totalTrips': 0,
        'profilePhotoUrl': 'https://picsum.photos/seed/driver1/200/200',
        'isTestUser': true, // Marcar como usuario de prueba
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('📄 Documento de usuario creado');

      // Crear documento de vehículo con fotos de Lorem Picsum
      final vehicleId = _firestore.collection('vehicles').doc().id;
      await _firestore.collection('vehicles').doc(vehicleId).set({
        'vehicleId': vehicleId,
        'ownerId': userId,
        'brand': 'Toyota',
        'model': 'Corolla',
        'year': 2020,
        'color': 'Gris Plata',
        'plate': 'ABC-1234',
        'capacity': 4,
        'hasAirConditioning': true,
        // Fotos de Lorem Picsum (diferentes seeds para variedad)
        'photoUrl': 'https://picsum.photos/seed/toyotacorolla/800/600',
        'matriculaPhotoUrl': 'https://picsum.photos/seed/matricula123/800/600',
        'licensePhotoUrl': 'https://picsum.photos/seed/licencia456/800/600',
        'isVerified': true,
        'isTestVehicle': true, // Marcar como vehículo de prueba
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('🚗 Vehículo creado: Toyota Corolla (ABC-1234)');
      print('✅ Conductor completo: $email');

      // Hacer logout para no interferir con la sesión actual
      await _auth.signOut();
    } catch (e) {
      print('❌ Error general: $e');
    }
  }

  /// Eliminar usuarios de prueba de Firestore (para resetear)
  /// NOTA: Esto solo elimina de Firestore. Para eliminar de Firebase Auth,
  /// debes hacerlo desde la consola de Firebase.
  static Future<void> deleteTestUsers() async {
    print('=== Eliminando usuarios de prueba de Firestore ===');

    try {
      for (final email in TestUsers.testEmails) {
        // Buscar usuario por email
        final userQuery = await _firestore
            .collection('users')
            .where('email', isEqualTo: email)
            .get();

        for (final doc in userQuery.docs) {
          final userId = doc.id;

          // Eliminar vehículos asociados
          final vehiclesQuery = await _firestore
              .collection('vehicles')
              .where('ownerId', isEqualTo: userId)
              .get();

          for (final vehicle in vehiclesQuery.docs) {
            await vehicle.reference.delete();
            print('🗑️ Eliminado vehículo: ${vehicle.id}');
          }

          // Eliminar viajes asociados
          final tripsQuery = await _firestore
              .collection('trips')
              .where('driverId', isEqualTo: userId)
              .get();

          for (final trip in tripsQuery.docs) {
            await trip.reference.delete();
            print('🗑️ Eliminado viaje: ${trip.id}');
          }

          // Eliminar documento de usuario
          await doc.reference.delete();
          print('🗑️ Eliminado usuario de Firestore: $email');
        }
      }
    } catch (e) {
      print('⚠️ Error eliminando de Firestore (puede ser permiso): $e');
      print('   Esto es normal si no hay usuario autenticado.');
    }

    print('=== Documentos Firestore eliminados (si había permisos) ===');
    print('⚠️ NOTA: Los usuarios siguen existiendo en Firebase Auth.');
    print('   Si necesitas eliminarlos completamente, hazlo desde:');
    print('   Firebase Console → Authentication → Users');
  }

  /// Resetear y recrear usuarios de prueba
  /// Primero elimina de Firestore, luego intenta recrear
  static Future<void> resetAndCreate() async {
    print('=== RESET: Eliminando y recreando usuarios ===');
    await deleteTestUsers();
    print('');
    await createAll();
  }
}
