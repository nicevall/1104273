// lib/presentation/screens/home/home_screen.dart
// Pantalla Home principal - Estilo Uber
// Muestra búsqueda, historial reciente y destinos frecuentes

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../widgets/home/role_switcher.dart';
import '../../widgets/home/search_bar_widget.dart';
import '../../widgets/home/recent_place_card.dart';
import '../../widgets/home/location_permission_banner.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String userRole; // 'pasajero', 'conductor', 'ambos'
  final bool hasVehicle; // true si tiene vehículo registrado

  const HomeScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.hasVehicle = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Rol activo actual (para usuarios con rol "ambos")
  late String _activeRole;

  // Lista de lugares recientes (se cargará desde Firebase cuando haya historial)
  // Por ahora está vacía - solo se mostrará cuando el usuario tenga historial real
  final List<RecentPlace> _recentPlaces = [];

  // Key para refrescar el banner de ubicación
  final GlobalKey<State> _locationBannerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Si es "ambos", inicia como pasajero por defecto
    _activeRole = widget.userRole == 'ambos' ? 'pasajero' : widget.userRole;
  }

  void _onRoleChanged(String newRole) {
    // Si intenta cambiar a conductor y no tiene vehículo, mostrar aviso
    if (newRole == 'conductor' && !widget.hasVehicle) {
      _showVehicleRequiredDialog();
      return;
    }
    setState(() {
      _activeRole = newRole;
    });
  }

  void _showVehicleRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.directions_car, color: AppColors.primary),
            const SizedBox(width: 12),
            const Text('Vehículo requerido'),
          ],
        ),
        content: const Text(
          'Para usar el modo conductor necesitas registrar tu vehículo primero.\n\n'
          '¿Deseas registrar tu vehículo ahora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Más tarde'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/vehicle/register', extra: {
                'userId': widget.userId,
                'role': widget.userRole,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Registrar vehículo'),
          ),
        ],
      ),
    );
  }

  void _onSearchTap() {
    // Navegar a la pantalla de planificación de viaje
    context.push('/trip/plan', extra: {
      'userId': widget.userId,
      'userRole': _activeRole,
    });
  }

  void _onScheduleLater() {
    // TODO: Implementar programación de viaje
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Programar viaje - Próximamente'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _onRecentPlaceTap(RecentPlace place) {
    // Navegar directamente al mapa con este destino
    context.push('/trip/plan', extra: {
      'userId': widget.userId,
      'userRole': _activeRole,
      'destination': {
        'name': place.name,
        'address': place.address,
        'latitude': place.latitude,
        'longitude': place.longitude,
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _activeRole == 'pasajero'
            ? _buildPassengerHome()
            : _buildDriverHome(),
      ),
    );
  }

  Widget _buildPassengerHome() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de ubicación desactivada (estilo Uber)
          LocationPermissionBanner(
            key: _locationBannerKey,
            onPermissionGranted: () {
              // Refrescar la pantalla cuando se otorga el permiso
              setState(() {});
            },
          ),

          // Header con logo y avatar
          _buildHeader(),

          const SizedBox(height: 16),

          // Toggle de rol (solo si es "ambos")
          if (widget.userRole == 'ambos')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: RoleSwitcher(
                activeRole: _activeRole,
                onRoleChanged: _onRoleChanged,
              ),
            ),

          const SizedBox(height: 24),

          // Barra de búsqueda estilo Uber
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SearchBarWidget(
              onTap: _onSearchTap,
              onScheduleLater: _onScheduleLater,
            ),
          ),

          const SizedBox(height: 24),

          // Lugares recientes (solo si hay historial real)
          if (_recentPlaces.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentPlaces.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return RecentPlaceCard(
                    place: _recentPlaces[index],
                    onTap: () => _onRecentPlaceTap(_recentPlaces[index]),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Mensaje cuando no hay historial
          if (_recentPlaces.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.tertiary.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.explore_outlined,
                      color: AppColors.textSecondary,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sin viajes recientes',
                            style: AppTextStyles.body1.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tus destinos frecuentes aparecerán aquí',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDriverHome() {
    // Pantalla de conductor - Próximamente
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Toggle de rol (solo si es "ambos")
            if (widget.userRole == 'ambos')
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: RoleSwitcher(
                  activeRole: _activeRole,
                  onRoleChanged: _onRoleChanged,
                ),
              ),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.tertiary.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_car,
                size: 64,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Modo Conductor',
              style: AppTextStyles.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Esta funcionalidad estará disponible próximamente.',
              style: AppTextStyles.body2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Podrás crear viajes y recibir solicitudes de pasajeros.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo UniRide
          Text(
            'UniRide',
            style: AppTextStyles.h1.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),

          // Avatar del usuario - Navega al perfil
          GestureDetector(
            onTap: () {
              context.push('/profile', extra: {
                'userId': widget.userId,
              });
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.tertiary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.divider,
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.person,
                color: AppColors.textSecondary,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modelo para lugares recientes
class RecentPlace {
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final IconData icon;

  RecentPlace({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.icon = Icons.access_time,
  });
}
