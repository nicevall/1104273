// Script para crear documento del conductor en Firestore
// Ejecutar con: flutter run -t lib/scripts/setup_conductor.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  print('🚀 Creando documento del conductor...\n');

  final firestore = FirebaseFirestore.instance;
  final now = Timestamp.now();

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
    await firestore
        .collection('users')
        .doc('eZ7W5jmoUeh6egKMVtMjX1c40gz2')
        .set(conductorData);
    print('✅ Conductor creado: c@uide.edu.ec');
  } catch (e) {
    print('❌ Error: $e');
  }

  print('\n👋 Script finalizado.');
}
