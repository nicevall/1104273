// lib/presentation/screens/trip/pick_location_screen.dart
// Pantalla para elegir ubicación moviendo el mapa (el pin está fijo en el centro)
// Similar a la funcionalidad de Uber "Elegir en el mapa"

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/services/google_places_service.dart';

class PickLocationScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final double originLatitude;
  final double originLongitude;
  final String originAddress;

  const PickLocationScreen({
    super.key,
    required this.userId,
    required this.userRole,
    required this.originLatitude,
    required this.originLongitude,
    required this.originAddress,
  });

  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  late final GooglePlacesService _placesService;

  // Posición seleccionada (centro del mapa)
  late LatLng _selectedPosition;

  // Dirección de la posición seleccionada
  String _selectedAddress = 'Mueve el mapa para seleccionar';
  String _selectedName = 'Cargando...';
  bool _isLoadingAddress = false;
  bool _isMoving = false; // Para animar el pin cuando se mueve el mapa

  // Animación para los puntitos
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _placesService = GooglePlacesService();
    // Iniciar con la posición del origen
    _selectedPosition = LatLng(widget.originLatitude, widget.originLongitude);

    // Configurar animación de pulso para los puntitos
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController?.dispose();
    _placesService.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // Hacer geocoding inicial
    _reverseGeocode(_selectedPosition);
  }

  void _onCameraMoveStarted() {
    setState(() {
      _isMoving = true;
    });
  }

  void _onCameraMove(CameraPosition position) {
    _selectedPosition = position.target;
  }

  void _onCameraIdle() {
    setState(() {
      _isMoving = false;
    });
    // Hacer reverse geocoding cuando el mapa deja de moverse
    _reverseGeocode(_selectedPosition);
  }

  Future<void> _reverseGeocode(LatLng position) async {
    setState(() {
      _isLoadingAddress = true;
    });

    try {
      // Usar Google Geocoding API
      final result = await _placesService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (result != null && mounted) {
        setState(() {
          _selectedName = result.shortName;
          _selectedAddress = result.fullAddress;
          _isLoadingAddress = false;
        });
      } else if (mounted) {
        setState(() {
          _selectedName = 'Ubicación seleccionada';
          _selectedAddress =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
          _isLoadingAddress = false;
        });
      }
    } catch (e) {
      print('Error en reverse geocoding: $e');
      if (mounted) {
        setState(() {
          _selectedName = 'Ubicación seleccionada';
          _selectedAddress =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
          _isLoadingAddress = false;
        });
      }
    }
  }

  void _onConfirmLocation() {
    // Retornar la ubicación seleccionada
    context.pop({
      'name': _selectedName,
      'address': _selectedAddress,
      'latitude': _selectedPosition.latitude,
      'longitude': _selectedPosition.longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Mapa - El usuario mueve el mapa, no el pin
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selectedPosition,
              zoom: 16, // Zoom más alejado para escoger destino
            ),
            onMapCreated: _onMapCreated,
            onCameraMoveStarted: _onCameraMoveStarted,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            // Padding para que el centro visual esté arriba del bottom card
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height * 0.22,
            ),
          ),

          // Pin fijo en el centro con animación
          _buildCenterPin(),

          // Botón atrás (sin botón de capas)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: _buildBackButton(),
          ),

          // Card de dirección seleccionada + botón confirmar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomCard(),
          ),
        ],
      ),
    );
  }

  // Color personalizado del pin (verde menta)
  static const Color _pinColor = Color(0xFF6CCC91);

  Widget _buildCenterPin() {
    return Center(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height * 0.22,
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Puntitos animados (efecto Uber) - debajo del pin
            Positioned(
              top: 36, // Posición fija debajo del pin
              child: _buildPulseDots(),
            ),
            // Pin con animación de elevación cuando se mueve
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(0, _isMoving ? -12 : 0, 0),
              child: const Icon(
                Icons.location_on,
                size: 44,
                color: _pinColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPulseDots() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return SizedBox(
          width: 60,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Círculo central (sombra del pin)
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _pinColor.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
              // Círculos de pulso que se expanden
              if (!_isMoving) ...[
                // Primer círculo de pulso
                Transform.scale(
                  scale: 1 + (_pulseAnimation.value * 1.5),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _pinColor
                          .withValues(alpha: 0.3 * (1 - _pulseAnimation.value)),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                // Segundo círculo de pulso (desfasado)
                Transform.scale(
                  scale: 1 +
                      (((_pulseAnimation.value + 0.5) % 1.0) * 1.5),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _pinColor.withValues(
                          alpha: 0.2 *
                              (1 - ((_pulseAnimation.value + 0.5) % 1.0))),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBackButton() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.arrow_back),
        color: AppColors.textPrimary,
        onPressed: () => context.pop(),
      ),
    );
  }

  Widget _buildBottomCard() {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Info de la ubicación
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _pinColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.flag,
                  color: _pinColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isLoadingAddress)
                      Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Obteniendo dirección...',
                            style: AppTextStyles.body2.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      Text(
                        _selectedName,
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedAddress,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Botón confirmar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoadingAddress ? null : _onConfirmLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.disabled,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Confirmar destino',
                style: AppTextStyles.button,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
