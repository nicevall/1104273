// lib/presentation/screens/home/main_navigation_screen.dart
// Pantalla principal con Bottom Navigation
// Maneja la navegación entre las 3 tabs principales (Inicio, Actividad, Mensajes)
// El perfil se accede desde el avatar en la esquina superior derecha

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/services/location_cache_service.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/common/map_preloader.dart';
import 'home_screen.dart';
import 'activity_screen.dart';
import 'messages_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final String userId;
  final String userRole; // 'pasajero', 'conductor', 'ambos'
  final bool hasVehicle; // true si tiene vehículo registrado
  final String? activeRole; // Rol activo inicial (para mantener contexto al navegar)

  const MainNavigationScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.hasVehicle = false,
    this.activeRole,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  late List<Widget> _screens;

  // Variables para datos del usuario autenticado
  late String _userId;
  late String _userRole;
  late bool _hasVehicle;

  @override
  void initState() {
    super.initState();
    _userId = widget.userId;
    _userRole = widget.userRole;
    _hasVehicle = widget.hasVehicle;
    _buildScreens();
  }

  void _buildScreens() {
    _screens = [
      HomeScreen(
        userId: _userId,
        userRole: _userRole,
        hasVehicle: _hasVehicle,
        activeRole: widget.activeRole,
      ),
      ActivityScreen(userId: _userId),
      const MessagesScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        // Si el usuario cierra sesión o no está autenticado, ir a welcome
        if (state is Unauthenticated) {
          context.go('/welcome');
        }
        // Si el estado cambia a Authenticated, actualizar datos
        if (state is Authenticated) {
          setState(() {
            _userId = state.user.userId;
            _userRole = state.user.role;
            _hasVehicle = state.user.hasVehicle;
            _buildScreens();
          });
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Precargador de Google Maps (invisible)
            // Se inicializa en segundo plano para que el mapa
            // esté listo cuando el usuario lo necesite
            // Usa la ubicación cacheada del usuario si está disponible
            Builder(
              builder: (context) {
                final cache = LocationCacheService();
                if (cache.hasFreshLocation) {
                  final loc = cache.cachedLocation!;
                  return MapPreloader(
                    initialPosition: LatLng(loc.latitude, loc.longitude),
                  );
                }
                // Si no hay ubicación cacheada, usar ubicación por defecto (Quito)
                return const MapPreloader();
              },
            ),

            // Contenido principal con las pantallas
            IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(
                    index: 0,
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: 'Inicio',
                  ),
                  _buildNavItem(
                    index: 1,
                    icon: Icons.history_outlined,
                    activeIcon: Icons.history,
                    label: 'Actividad',
                  ),
                  _buildNavItem(
                    index: 2,
                    icon: Icons.chat_bubble_outline,
                    activeIcon: Icons.chat_bubble,
                    label: 'Mensajes',
                    badge: 0, // TODO: Conectar con mensajes no leídos
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    int badge = 0,
  }) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 26,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
                if (badge > 0)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        badge > 9 ? '9+' : badge.toString(),
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
