// lib/presentation/screens/profile/profile_screen.dart
// Pantalla de Perfil del usuario
// Muestra información real del usuario desde AuthBloc

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';

class ProfileScreen extends StatelessWidget {
  final String userId;

  const ProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        // Si el usuario cierra sesión, redirigir a welcome
        if (state is Unauthenticated) {
          context.go('/welcome');
        }
      },
      builder: (context, state) {
        // Obtener datos del usuario autenticado
        String userName = 'Usuario';
        String userEmail = 'correo@uide.edu.ec';
        double userRating = 5.0;
        int totalTrips = 0;
        String? profilePhotoUrl;

        if (state is Authenticated) {
          final user = state.user;
          userName = user.fullName;
          userEmail = user.email;
          userRating = user.rating;
          totalTrips = user.totalTrips;
          profilePhotoUrl = user.profilePhotoUrl;
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            title: Text(
              'Perfil',
              style: AppTextStyles.h2,
            ),
            centerTitle: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                color: AppColors.textPrimary,
                onPressed: () {
                  // TODO: Navegar a configuración
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Avatar y nombre
                _buildProfileHeader(
                  userName: userName,
                  userEmail: userEmail,
                  userRating: userRating,
                  totalTrips: totalTrips,
                  profilePhotoUrl: profilePhotoUrl,
                ),

                const SizedBox(height: 32),

                // Opciones del perfil
                _buildProfileOptions(context),

                const SizedBox(height: 32),

                // Botón cerrar sesión
                _buildLogoutButton(context),

                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileHeader({
    required String userName,
    required String userEmail,
    required double userRating,
    required int totalTrips,
    String? profilePhotoUrl,
  }) {
    return Column(
      children: [
        // Avatar
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.tertiary,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primary,
              width: 3,
            ),
            image: profilePhotoUrl != null
                ? DecorationImage(
                    image: NetworkImage(profilePhotoUrl),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: profilePhotoUrl == null
              ? const Icon(
                  Icons.person,
                  size: 50,
                  color: AppColors.textSecondary,
                )
              : null,
        ),
        const SizedBox(height: 16),

        // Nombre
        Text(
          userName,
          style: AppTextStyles.h2,
        ),
        const SizedBox(height: 4),

        // Email
        Text(
          userEmail,
          style: AppTextStyles.body2.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),

        // Rating
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.star,
              size: 20,
              color: AppColors.warning,
            ),
            const SizedBox(width: 4),
            Text(
              userRating.toStringAsFixed(1),
              style: AppTextStyles.body1.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '($totalTrips viajes)',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileOptions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildOptionTile(
            icon: Icons.person_outline,
            title: 'Editar perfil',
            onTap: () {
              // TODO: Navegar a editar perfil
            },
          ),
          _buildOptionTile(
            icon: Icons.history,
            title: 'Historial de viajes',
            onTap: () {
              // TODO: Navegar a historial
            },
          ),
          _buildOptionTile(
            icon: Icons.payment_outlined,
            title: 'Métodos de pago',
            onTap: () {
              // TODO: Navegar a métodos de pago
            },
          ),
          _buildOptionTile(
            icon: Icons.notifications_outlined,
            title: 'Notificaciones',
            onTap: () {
              // TODO: Navegar a notificaciones
            },
          ),
          _buildOptionTile(
            icon: Icons.security_outlined,
            title: 'Seguridad',
            onTap: () {
              // TODO: Navegar a seguridad
            },
          ),
          _buildOptionTile(
            icon: Icons.help_outline,
            title: 'Ayuda',
            onTap: () {
              // TODO: Navegar a ayuda
            },
          ),
          _buildOptionTile(
            icon: Icons.info_outline,
            title: 'Acerca de UniRide',
            onTap: () {
              // TODO: Navegar a acerca de
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.tertiary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: AppColors.textSecondary,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: AppTextStyles.body1,
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppColors.textTertiary,
      ),
      onTap: onTap,
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            _showLogoutDialog(context);
          },
          icon: const Icon(Icons.logout, color: Colors.white),
          label: Text(
            'Cerrar sesión',
            style: AppTextStyles.button.copyWith(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '¿Cerrar sesión?',
          style: AppTextStyles.h3,
        ),
        content: Text(
          '¿Estás seguro de que deseas cerrar sesión?',
          style: AppTextStyles.body2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              // Botón Cancelar - outline gris
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Cancelar',
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Botón Cerrar sesión - rojo sólido
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    // Cerrar sesión usando AuthBloc
                    context.read<AuthBloc>().add(const LogoutEvent());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Cerrar sesión',
                    style: AppTextStyles.button.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
