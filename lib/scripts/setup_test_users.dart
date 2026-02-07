// Script para crear documentos de usuarios de prueba en Firestore
// Ejecutar con: flutter run -t lib/scripts/setup_test_users.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  print('🚀 Creando documentos de usuarios de prueba...\n');

  final firestore = FirebaseFirestore.instance;
  final now = Timestamp.now();

  // Usuario Pasajero
  final pasajeroData = {
    'userId': '9bDMf5IDSXgEO3XQmPNqJ5UI5pW2',
    'email': 'p@uide.edu.ec',
    'firstName': 'Test',
    'lastName': 'Pasajero',
    'phoneNumber': '+593999999991',
    'career': 'Ingeniería en Software',
    'semester': 5,
    'role': 'pasajero',
    'isVerified': true,
    'hasVehicle': false,
    'rating': 5.0,
    'totalTrips': 0,
    'profilePhotoUrl': null,
    'createdAt': now,
    'updatedAt': now,
  };

  // Usuario Conductor
  final conductorData = {
    'userId': 'eZ7W5jmoUeh6egKMVtMjX1c40gz2',
    'email': 'c@uide.edu.ec',
    'firstName': 'Test',
    'lastName': 'Conductor',
    'phoneNumber': '+593999999992',
    'career': 'Ingeniería en Software',
    'semester': 7,
    'role': 'conductor',
    'isVerified': true,
    'hasVehicle': false,
    'rating': 5.0,
    'totalTrips': 0,
    'profilePhotoUrl': null,
    'createdAt': now,
    'updatedAt': now,
  };

  try {
    // Crear documento del pasajero
    await firestore
        .collection('users')
        .doc('9bDMf5IDSXgEO3XQmPNqJ5UI5pW2')
        .set(pasajeroData);
    print('✅ Pasajero creado: p@uide.edu.ec');

    // Crear documento del conductor
    await firestore
        .collection('users')
        .doc('eZ7W5jmoUeh6egKMVtMjX1c40gz2')
        .set(conductorData);
    print('✅ Conductor creado: c@uide.edu.ec');

    print('\n🎉 ¡Usuarios de prueba creados exitosamente!');
    print('\n📧 Credenciales:');
    print('   Pasajero: p | 123456');
    print('   Conductor: c | 123456');
  } catch (e) {
    print('❌ Error: $e');
  }

  // Salir
  print('\n👋 Script finalizado.');
}
