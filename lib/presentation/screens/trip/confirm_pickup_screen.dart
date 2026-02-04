// lib/presentation/screens/trip/confirm_pickup_screen.dart
// Pantalla "Confirmar punto de recogida" - Estilo Uber
// El usuario mueve el mapa y el pin está fijo en el centro

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/services/google_places_service.dart';

class ConfirmPickupScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final Map<String, dynamic> origin;
  final Map<String, dynamic> destination;
  final String preference;
  final String preferenceDescription;
  final String paymentMethod;

  const ConfirmPickupScreen({
    super.key,
    required this.userId,
    required this.userRole,
    required this.origin,
    required this.destination,
    required this.preference,
    required this.preferenceDescription,
    required this.paymentMethod,
  });

  @override
  State<ConfirmPickupScreen> createState() => _ConfirmPickupScreenState();
}

class _ConfirmPickupScreenState extends State<ConfirmPickupScreen> {
  GoogleMapController? _mapController;
  final GooglePlacesService _placesService = GooglePlacesService();
  final TextEditingController _referenceController = TextEditingController();

  late LatLng _pickupLocation;
  late LatLng _userLocation; // Ubicación actual del usuario
  String _pickupAddress = '';
  bool _isLoadingAddress = false;
  Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _pickupLocation = LatLng(
      widget.origin['latitude'] as double,
      widget.origin['longitude'] as double,
    );
    _userLocation = _pickupLocation; // Guardar ubicación inicial del usuario
    _pickupAddress = widget.origin['name'] ?? 'Ubicación seleccionada';
    _createDottedCurve();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _placesService.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onCameraMove(CameraPosition position) {
    _pickupLocation = position.target;
    if (!_isLoadingAddress) {
      setState(() {
        _isLoadingAddress = true;
      });
    }
    // Actualizar los círculos mientras se mueve
    _createDottedCurve();
  }

  void _onCameraIdle() {
    _getAddressFromLatLng(_pickupLocation);
  }

  /// Crear círculos a lo largo de una curva (estilo Uber)
  void _createDottedCurve() {
    final points = _generateCurvedPoints(_pickupLocation, _userLocation);
    final circles = <Circle>{};

    // Calcular el radio de los puntos basado en el zoom/distancia
    // A mayor distancia, puntos más grandes para que se vean
    final distance = _calculateDistance(_pickupLocation, _userLocation);
    final dotRadius = _calculateDotRadius(distance);

    for (int i = 0; i < points.length; i++) {
      // Gradiente de opacidad: más oscuro cerca del pickup, más claro cerca del usuario
      final opacity = 0.4 + (0.6 * (i / points.length));
      circles.add(
        Circle(
          circleId: CircleId('dot_$i'),
          center: points[i],
          radius: dotRadius,
          fillColor: Colors.black.withOpacity(opacity),
          strokeColor: Colors.black.withOpacity(opacity),
          strokeWidth: 0,
        ),
      );
    }

    setState(() {
      _circles = circles;
    });
  }

  /// Calcular el radio de los puntos según la distancia
  double _calculateDotRadius(double distance) {
    // Convertir distancia en grados a metros aproximadamente
    // 1 grado ≈ 111,000 metros en el ecuador
    final distanceMeters = distance * 111000;

    // Radio muy pequeño (la mitad del anterior)
    if (distanceMeters < 30) return 0.4;
    if (distanceMeters < 80) return 0.5;
    if (distanceMeters < 150) return 0.6;
    return 0.75;
  }

  /// Generar puntos para una curva Bezier que sale hacia un lado
  /// Los puntos van desde el pickup (start) hasta la ubicación del usuario (end)
  List<LatLng> _generateCurvedPoints(LatLng start, LatLng end) {
    final points = <LatLng>[];

    // Si los puntos son iguales o muy cercanos, no dibujar
    final distance = _calculateDistance(start, end);
    if (distance < 0.00005) return points;

    // Calcular dirección de start a end
    final dx = end.longitude - start.longitude;
    final dy = end.latitude - start.latitude;
    final length = math.sqrt(dx * dx + dy * dy);

    // Vector perpendicular normalizado
    final perpX = -dy / length;
    final perpY = dx / length;

    // Curvatura proporcional a la distancia (más suave)
    final curveAmount = distance * 0.3;

    // Punto de control desplazado perpendicularmente
    final midLat = (start.latitude + end.latitude) / 2;
    final midLng = (start.longitude + end.longitude) / 2;

    final controlLat = midLat + perpX * curveAmount;
    final controlLng = midLng + perpY * curveAmount;

    // Calcular número de puntos basado en la distancia
    // Más distancia = más puntos, pero mantener espaciado consistente
    final distanceMeters = distance * 111000;
    final numDots = _calculateNumDots(distanceMeters);

    // Generar puntos, empezando un poco después del inicio para no tapar el pin
    // y terminando un poco antes del final para no tapar el punto azul
    for (int i = 1; i < numDots; i++) {
      final t = i / numDots;
      final lat = _quadraticBezier(start.latitude, controlLat, end.latitude, t);
      final lng = _quadraticBezier(start.longitude, controlLng, end.longitude, t);
      points.add(LatLng(lat, lng));
    }

    return points;
  }

  /// Calcular número de puntos según la distancia para mantener espaciado estético
  int _calculateNumDots(double distanceMeters) {
    // Más puntos, bien distribuidos como en Uber
    // Espaciado objetivo: ~4-6 metros entre puntos
    if (distanceMeters < 20) return 6;
    if (distanceMeters < 40) return 10;
    if (distanceMeters < 60) return 12;
    if (distanceMeters < 100) return 16;
    if (distanceMeters < 150) return 20;
    if (distanceMeters < 200) return 24;
    return 30;
  }

  double _quadraticBezier(double p0, double p1, double p2, double t) {
    return (1 - t) * (1 - t) * p0 + 2 * (1 - t) * t * p1 + t * t * p2;
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    final dx = p1.latitude - p2.latitude;
    final dy = p1.longitude - p2.longitude;
    return math.sqrt(dx * dx + dy * dy);
  }

  Future<void> _getAddressFromLatLng(LatLng position) async {
    try {
      final result = await _placesService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (result != null && mounted) {
        setState(() {
          _pickupAddress = result.shortName;
          _isLoadingAddress = false;
        });
      } else if (mounted) {
        setState(() {
          _pickupAddress = 'Ubicación seleccionada';
          _isLoadingAddress = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pickupAddress = 'Ubicación seleccionada';
          _isLoadingAddress = false;
        });
      }
    }
  }

  void _onConfirmPickup() {
    context.push('/trip/search-results', extra: {
      'userId': widget.userId,
      'userRole': widget.userRole,
      'origin': widget.origin,
      'destination': widget.destination,
      'pickupLocation': {
        'latitude': _pickupLocation.latitude,
        'longitude': _pickupLocation.longitude,
        'address': _pickupAddress,
        'reference': _referenceController.text.trim(),
      },
      'preference': widget.preference,
      'preferenceDescription': widget.preferenceDescription,
      'paymentMethod': widget.paymentMethod,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomSheetHeight = MediaQuery.of(context).size.height * 0.38;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Mapa de fondo (recibe gestos)
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _pickupLocation,
                zoom: 23,
              ),
              onMapCreated: _onMapCreated,
              onCameraMove: _onCameraMove,
              onCameraIdle: _onCameraIdle,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              circles: _circles,
              padding: EdgeInsets.only(bottom: bottomSheetHeight),
            ),
          ),

          // 2. Pin central (NO recibe gestos)
          Positioned.fill(
            bottom: bottomSheetHeight,
            child: IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Recoger aquí',
                        style: AppTextStyles.body2.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 20,
                      color: AppColors.primary,
                    ),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Botón atrás (recibe gestos)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.black87,
                  size: 24,
                ),
              ),
            ),
          ),

          // 4. Bottom Sheet (recibe gestos)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).padding.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Título
                  Text(
                    'Confirma el punto de recogida',
                    style: AppTextStyles.h3,
                  ),
                  const SizedBox(height: 12),

                  // Dirección
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
                  else
                    Text(
                      _pickupAddress,
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 16),

                  // Campo de referencia (opcional)
                  TextField(
                    controller: _referenceController,
                    style: AppTextStyles.body2,
                    decoration: InputDecoration(
                      hintText: 'Referencia (opcional)',
                      hintStyle: AppTextStyles.body2.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      prefixIcon: Icon(
                        Icons.edit_location_alt_outlined,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ej: Casa blanca con reja negra, edificio azul',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Botón confirmar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoadingAddress ? null : _onConfirmPickup,
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
                        'Confirmar recogida',
                        style: AppTextStyles.button,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
