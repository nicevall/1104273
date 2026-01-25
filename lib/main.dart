// lib/main.dart
// Punto de entrada de la aplicación UniRide

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'config/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/services/firebase_auth_service.dart';
import 'data/services/firebase_storage_service.dart';
import 'data/services/firestore_service.dart';
import 'presentation/blocs/auth/auth_bloc.dart';
import 'presentation/blocs/registration/registration_bloc.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Inicializar App Check con Debug provider para desarrollo
  // Para producción, cambiar a AndroidProvider.playIntegrity
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
  );

  // Configurar idioma de Firebase Auth para emails
  await FirebaseAuth.instance.setLanguageCode('es');

  // Configurar orientación vertical únicamente
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Configurar barra de estado
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Inicializar servicios
    final authService = FirebaseAuthService();
    final firestoreService = FirestoreService();
    final storageService = FirebaseStorageService();

    return MultiBlocProvider(
      providers: [
        // AuthBloc - Maneja autenticación global
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc(
            authService: authService,
            firestoreService: firestoreService,
          ),
        ),

        // RegistrationBloc - Maneja flujo de registro
        BlocProvider<RegistrationBloc>(
          create: (context) => RegistrationBloc(
            authService: authService,
            storageService: storageService,
            firestoreService: firestoreService,
          ),
        ),
      ],
      child: MaterialApp.router(
        title: 'UniRide',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: appRouter,
      ),
    );
  }
}
