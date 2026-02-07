// lib/presentation/widgets/common/map_preloader.dart
// Widget invisible que precarga Google Maps en segundo plano
// Se usa en MainNavigationScreen para que el mapa esté listo cuando se necesite

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Widget que precarga Google Maps de forma invisible
///
/// Renderiza un mapa de 1x1 pixel oculto para inicializar el SDK
/// de Google Maps en segundo plano. Esto reduce significativamente
/// el tiempo de carga cuando el usuario navega a pantallas con mapa.
class MapPreloader extends StatefulWidget {
  /// Ubicación inicial para el mapa (por defecto Quito, Ecuador)
  final LatLng initialPosition;

  const MapPreloader({
    super.key,
    this.initialPosition = const LatLng(-0.1807, -78.4678), // Quito
  });

  @override
  State<MapPreloader> createState() => _MapPreloaderState();
}

class _MapPreloaderState extends State<MapPreloader> {
  bool _isMapReady = false;
  GoogleMapController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) async {
    _controller = controller;

    // Esperar un momento para que se carguen los tiles del mapa
    await Future.delayed(const Duration(milliseconds: 500));

    // Marcar como listo y ocultar
    if (mounted) {
      setState(() {
        _isMapReady = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si el mapa ya está listo, no renderizar nada
    if (_isMapReady) {
      return const SizedBox.shrink();
    }

    // Renderizar un mapa pequeño pero funcional para precargar el SDK completo
    return SizedBox(
      width: 1,
      height: 1,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialPosition,
              zoom: 14,
            ),
            // Deshabilitar todas las interacciones
            zoomControlsEnabled: false,
            zoomGesturesEnabled: false,
            scrollGesturesEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            myLocationButtonEnabled: false,
            myLocationEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            // NO usar liteModeEnabled para precargar el SDK completo
            liteModeEnabled: false,
            onMapCreated: _onMapCreated,
          ),
        ),
      ),
    );
  }
}
