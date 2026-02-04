// lib/presentation/screens/trip/map_route_screen.dart
// Pantalla de Mapa con Ruta - Material Design 3
// Muestra origen/destino con pines modernos estilo pick_location_screen

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:widget_to_marker/widget_to_marker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class MapRouteScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final Map<String, dynamic> origin;
  final Map<String, dynamic> destination;

  const MapRouteScreen({
    super.key,
    required this.userId,
    required this.userRole,
    required this.origin,
    required this.destination,
  });

  @override
  State<MapRouteScreen> createState() => _MapRouteScreenState();
}

class _MapRouteScreenState extends State<MapRouteScreen> {
  GoogleMapController? _mapController;

  // Colores
  static const Color _destinationColor = Color(0xFF6CCC91); // Verde menta
  static const Color _originColor = AppColors.primary; // Turquesa

  // Preferencias del viaje
  String _selectedPreference = 'mochila';
  String _preferenceDescription = '';
  String _paymentMethod = 'Efectivo';

  // Polyline y Markers
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};

  bool _markersCreated = false;

  @override
  void initState() {
    super.initState();
    _createPolyline();
    // Markers se crean después del primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _createCustomMarkers();
    });
  }

  /// Crear markers personalizados usando widget_to_marker
  Future<void> _createCustomMarkers() async {
    if (_markersCreated) return;
    _markersCreated = true;

    try {
      // Crear marker de origen (turquesa)
      final originIcon = await _buildMarkerWidget(_originColor).toBitmapDescriptor(
        logicalSize: const Size(48, 58),
        imageSize: const Size(96, 116),
      );

      // Crear marker de destino (verde menta)
      final destinationIcon = await _buildMarkerWidget(_destinationColor).toBitmapDescriptor(
        logicalSize: const Size(48, 58),
        imageSize: const Size(96, 116),
      );

      if (mounted) {
        setState(() {
          _markers = {
            Marker(
              markerId: const MarkerId('origin'),
              position: _originLatLng,
              icon: originIcon,
              anchor: const Offset(0.5, 1.0),
            ),
            Marker(
              markerId: const MarkerId('destination'),
              position: _destinationLatLng,
              icon: destinationIcon,
              anchor: const Offset(0.5, 1.0),
            ),
          };
        });
      }
    } catch (e) {
      // Fallback a markers nativos si falla
      debugPrint('Error creating custom markers: $e');
      if (mounted) {
        setState(() {
          _markers = {
            Marker(
              markerId: const MarkerId('origin'),
              position: _originLatLng,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
            ),
            Marker(
              markerId: const MarkerId('destination'),
              position: _destinationLatLng,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            ),
          };
        });
      }
    }
  }

  /// Widget del marker (igual que pick_location_screen)
  Widget _buildMarkerWidget(Color color) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 48,
        height: 58,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // Sombra circular
            Positioned(
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Icono del pin
            Icon(
              Icons.location_on,
              size: 48,
              color: color,
            ),
          ],
        ),
      ),
    );
  }

  void _createPolyline() {
    _polylines = {
      Polyline(
        polylineId: const PolylineId('route_base'),
        points: [_originLatLng, _destinationLatLng],
        color: _destinationColor.withOpacity(0.3),
        width: 5,
      ),
      Polyline(
        polylineId: const PolylineId('route'),
        points: [_originLatLng, _destinationLatLng],
        color: _destinationColor,
        width: 5,
        patterns: [
          PatternItem.dash(16),
          PatternItem.gap(10),
        ],
      ),
    };
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  LatLng get _originLatLng => LatLng(
        widget.origin['latitude'] as double,
        widget.origin['longitude'] as double,
      );

  LatLng get _destinationLatLng => LatLng(
        widget.destination['latitude'] as double,
        widget.destination['longitude'] as double,
      );

  bool _isPlusCode(String? text) {
    if (text == null || text.isEmpty) return false;
    return RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}', caseSensitive: false)
        .hasMatch(text);
  }

  String _cleanAddress(String address) {
    final parts = address.split(',').map((s) => s.trim()).toList();
    final cleanParts = parts.where((part) => !_isPlusCode(part)).toList();
    return cleanParts.isNotEmpty ? cleanParts.join(', ') : address;
  }

  String get _originName {
    final address = widget.origin['address'] as String?;
    final name = widget.origin['name'] as String?;
    if (name != null && name.isNotEmpty && !_isPlusCode(name)) return name;
    if (address != null && address.isNotEmpty) {
      final cleaned = _cleanAddress(address);
      if (cleaned.isNotEmpty && !_isPlusCode(cleaned.split(',').first.trim())) {
        return cleaned;
      }
    }
    return name ?? 'Origen';
  }

  String get _destinationName {
    final address = widget.destination['address'] as String?;
    final name = widget.destination['name'] as String?;
    if (name != null && name.isNotEmpty && !_isPlusCode(name)) return name;
    if (address != null && address.isNotEmpty) {
      final cleaned = _cleanAddress(address);
      if (cleaned.isNotEmpty) return cleaned;
    }
    return name ?? 'Destino';
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // Esperar un poco para que el mapa se renderice completamente
    Future.delayed(const Duration(milliseconds: 500), () {
      _fitBounds();
    });
  }

  void _fitBounds() {
    if (_mapController == null) return;

    final bounds = LatLngBounds(
      southwest: LatLng(
        _originLatLng.latitude < _destinationLatLng.latitude
            ? _originLatLng.latitude
            : _destinationLatLng.latitude,
        _originLatLng.longitude < _destinationLatLng.longitude
            ? _originLatLng.longitude
            : _destinationLatLng.longitude,
      ),
      northeast: LatLng(
        _originLatLng.latitude > _destinationLatLng.latitude
            ? _originLatLng.latitude
            : _destinationLatLng.latitude,
        _originLatLng.longitude > _destinationLatLng.longitude
            ? _originLatLng.longitude
            : _destinationLatLng.longitude,
      ),
    );

    // Padding más grande para asegurar que los markers se vean bien
    // Considerando el card superior y el bottom sheet
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  void _onPreferencesTap() {
    context.push('/trip/preferences', extra: {
      'userId': widget.userId,
      'currentPreference': _selectedPreference,
      'currentDescription': _preferenceDescription,
    }).then((result) {
      if (result != null && result is Map<String, dynamic>) {
        setState(() {
          _selectedPreference = result['preference'] ?? 'mochila';
          _preferenceDescription = result['description'] ?? '';
        });
      }
    });
  }

  void _onPaymentMethodTap() {
    _showPaymentMethodSheet();
  }

  void _onConfirmAndSearch() {
    if (_selectedPreference.contains('objeto_grande') &&
        _preferenceDescription.isEmpty) {
      _onPreferencesTap();
      return;
    }

    context.push('/trip/confirm-pickup', extra: {
      'userId': widget.userId,
      'userRole': widget.userRole,
      'origin': widget.origin,
      'destination': widget.destination,
      'preference': _selectedPreference,
      'preferenceDescription': _preferenceDescription,
      'paymentMethod': _paymentMethod,
    });
  }

  void _showPaymentMethodSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Método de pago', style: AppTextStyles.h3),
            const SizedBox(height: 20),
            _buildPaymentOption(
                'Efectivo', Icons.payments_outlined, _paymentMethod == 'Efectivo',
                subtitle: 'Paga en efectivo al conductor'),
            _buildPaymentOption(
                'Ahorita', Icons.account_balance_outlined, _paymentMethod == 'Ahorita',
                subtitle: 'Pago inmediato por transferencia'),
            _buildPaymentOption(
                'DeUna', Icons.bolt_outlined, _paymentMethod == 'DeUna',
                subtitle: 'Transferencia al finalizar el viaje'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOption(String method, IconData icon, bool isSelected,
      {String? subtitle}) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.tertiary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon,
            color: isSelected ? AppColors.primary : AppColors.textSecondary),
      ),
      title: Text(method,
          style: AppTextStyles.body1.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          )),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary))
          : null,
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.primary)
          : null,
      onTap: () {
        setState(() => _paymentMethod = method);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Mapa con markers personalizados
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _originLatLng,
              zoom: 14,
            ),
            onMapCreated: _onMapCreated,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 180,
              bottom: MediaQuery.of(context).size.height * 0.35,
            ),
          ),

          // Card con info de ruta
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 16,
            right: 16,
            child: _buildRouteInfoCard(),
          ),

          // Botón atrás
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: _buildBackButton(),
          ),

          // Bottom Sheet
          _buildBottomSheet(),
        ],
      ),
    );
  }

  Widget _buildRouteInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Destino
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _destinationColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.flag_rounded, color: _destinationColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Destino',
                      style: AppTextStyles.caption.copyWith(
                        color: _destinationColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _destinationName,
                      style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Línea conectora
          Container(
            margin: const EdgeInsets.only(left: 17),
            child: Row(
              children: [
                CustomPaint(
                  size: const Size(2, 24),
                  painter: _StaticDottedLinePainter(color: _destinationColor),
                ),
              ],
            ),
          ),

          // Salida
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _originColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.my_location_rounded, color: _originColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Salida',
                      style: AppTextStyles.caption.copyWith(
                        color: _originColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _originName,
                      style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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
        icon: const Icon(Icons.arrow_back_rounded),
        color: AppColors.textPrimary,
        onPressed: () => context.pop(),
      ),
    );
  }

  Widget _buildBottomSheet() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
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
            _buildPreferenceTile(),
            const Divider(height: 1),
            _buildPaymentTile(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _onConfirmAndSearch,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Confirmar y buscar viaje', style: AppTextStyles.button),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferenceTile() {
    IconData prefIcon;
    String prefText;

    if (_selectedPreference.contains(',')) {
      prefIcon = Icons.checklist_rounded;
      final parts = _selectedPreference.split(',');
      prefText = '${parts.length} opciones seleccionadas';
    } else {
      switch (_selectedPreference) {
        case 'objeto_grande':
          prefIcon = Icons.inventory_2_outlined;
          prefText = _preferenceDescription.isNotEmpty
              ? _preferenceDescription
              : 'Objeto grande';
          break;
        case 'mascota':
          prefIcon = Icons.pets_outlined;
          prefText = 'Mascota';
          break;
        default:
          prefIcon = Icons.backpack_outlined;
          prefText = 'Mochila';
      }
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.tertiary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(prefIcon, color: AppColors.textSecondary),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Qué vas a llevar?',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          Text(prefText,
              style: AppTextStyles.body1,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      onTap: _onPreferencesTap,
    );
  }

  Widget _buildPaymentTile() {
    IconData paymentIcon;
    switch (_paymentMethod) {
      case 'Ahorita':
        paymentIcon = Icons.account_balance_outlined;
        break;
      case 'DeUna':
        paymentIcon = Icons.bolt_outlined;
        break;
      default:
        paymentIcon = Icons.payments_outlined;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.tertiary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(paymentIcon, color: AppColors.textSecondary),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Método de pago',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          Text(_paymentMethod, style: AppTextStyles.body1),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      onTap: _onPaymentMethodTap,
    );
  }
}

/// Línea punteada estática
class _StaticDottedLinePainter extends CustomPainter {
  final Color color;

  _StaticDottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dotSpacing = 6.0;
    const dotRadius = 2.0;

    for (double y = 0; y < size.height; y += dotSpacing) {
      canvas.drawCircle(Offset(size.width / 2, y), dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StaticDottedLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
