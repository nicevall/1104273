import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

/// Pantalla de registro de vehículo (Legacy)
/// Redirige al nuevo flujo de registro con KYC
class RegisterVehicleScreen extends StatefulWidget {
  final String userId;
  final String role;

  const RegisterVehicleScreen({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  State<RegisterVehicleScreen> createState() => _RegisterVehicleScreenState();
}

class _RegisterVehicleScreenState extends State<RegisterVehicleScreen> {
  @override
  void initState() {
    super.initState();
    // Redirigir al nuevo flujo de registro de vehículo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/register/vehicle/questions', extra: {
        'userId': widget.userId,
        'role': widget.role,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mostrar loading mientras redirige
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      ),
    );
  }
}
