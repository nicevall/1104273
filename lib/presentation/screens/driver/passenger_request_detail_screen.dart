// lib/presentation/screens/driver/passenger_request_detail_screen.dart
// Pantalla de detalle de solicitud de pasajero
// Muestra mapa con ruta + desvío, info completa, botones aceptar/rechazar

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/route_info.dart';
import '../../../data/services/trips_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/google_directions_service.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../blocs/trip/trip_event.dart';
import '../../blocs/trip/trip_state.dart';

class PassengerRequestDetailScreen extends StatefulWidget {
  final String tripId;
  final String passengerId;

  const PassengerRequestDetailScreen({
    super.key,
    required this.tripId,
    required this.passengerId,
  });

  @override
  State<PassengerRequestDetailScreen> createState() =>
      _PassengerRequestDetailScreenState();
}

class _PassengerRequestDetailScreenState
    extends State<PassengerRequestDetailScreen> {
  final _tripsService = TripsService();
  final _firestoreService = FirestoreService();
  final _directionsService = GoogleDirectionsService();

  GoogleMapController? _mapController;

  TripModel? _trip;
  TripPassenger? _passenger;
  UserModel? _passengerUser;
  DeviationInfo? _deviationInfo;

  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Cargar viaje
      final trip = await _tripsService.getTrip(widget.tripId);
      if (trip == null) {
        setState(() {
          _error = 'Viaje no encontrado';
          _isLoading = false;
        });
        return;
      }

      // Encontrar pasajero
      final passenger = trip.passengers.firstWhere(
        (p) => p.userId == widget.passengerId,
        orElse: () => throw Exception('Pasajero no encontrado'),
      );

      // Cargar info del usuario
      final user = await _firestoreService.getUser(widget.passengerId);

      // Calcular desvío si hay pickup point
      DeviationInfo? deviation;
      if (passenger.pickupPoint != null) {
        // Obtener pasajeros ya aceptados
        final acceptedPickups = trip.passengers
            .where((p) => p.status == 'accepted' && p.pickupPoint != null)
            .map((p) => p.pickupPoint!)
            .toList();

        deviation = await _directionsService.calculateTotalDeviation(
          origin: trip.origin,
          destination: trip.destination,
          acceptedPickups: acceptedPickups,
          newPickup: passenger.pickupPoint!,
        );
      }

      if (mounted) {
        setState(() {
          _trip = trip;
          _passenger = passenger;
          _passengerUser = user;
          _deviationInfo = deviation;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _acceptPassenger() async {
    if (_trip == null || _passenger == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text(
          '¿Aceptar a ${_passengerUser?.firstName ?? "este pasajero"} en tu viaje?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      await _tripsService.acceptPassenger(widget.tripId, widget.passengerId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_passengerUser?.firstName ?? "Pasajero"} agregado al viaje',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _rejectPassenger() async {
    if (_trip == null || _passenger == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Text(
          '¿Rechazar la solicitud de ${_passengerUser?.firstName ?? "este pasajero"}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      await _tripsService.rejectPassenger(widget.tripId, widget.passengerId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud rechazada'),
            backgroundColor: AppColors.textSecondary,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_error != null || _trip == null || _passenger == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Text(_error ?? 'Error desconocido'),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Mapa de fondo
          _buildMap(),

          // Back button + Badge de desvío
          _buildTopOverlay(),

          // Bottom sheet con info
          _buildBottomSheet(),

          // Loading overlay
          if (_isProcessing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_trip == null || _passenger == null) return const SizedBox.shrink();

    // Crear markers
    final markers = <Marker>{
      // Origen (turquesa)
      Marker(
        markerId: const MarkerId('origin'),
        position: LatLng(_trip!.origin.latitude, _trip!.origin.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: InfoWindow(title: 'Origen', snippet: _trip!.origin.name),
      ),
      // Destino (verde)
      Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(
          _trip!.destination.latitude,
          _trip!.destination.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Destino',
          snippet: _trip!.destination.name,
        ),
      ),
    };

    // Pickup del pasajero (naranja)
    if (_passenger!.pickupPoint != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(
            _passenger!.pickupPoint!.latitude,
            _passenger!.pickupPoint!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: 'Recogida',
            snippet: _passenger!.pickupPoint!.name,
          ),
        ),
      );
    }

    // Crear polylines
    final polylines = <Polyline>{};

    // Ruta original (gris punteado)
    if (_deviationInfo?.originalRoute != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('original'),
          points: _deviationInfo!.originalRoute.polylinePoints,
          color: Colors.grey.withOpacity(0.5),
          width: 4,
          patterns: [
            PatternItem.dash(20),
            PatternItem.gap(10),
          ],
        ),
      );
    }

    // Ruta con pickup (turquesa sólido)
    if (_deviationInfo?.routeWithPickup != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('withPickup'),
          points: _deviationInfo!.routeWithPickup.polylinePoints,
          color: AppColors.primary,
          width: 5,
        ),
      );
    }

    // Calcular bounds para mostrar todos los puntos
    final bounds = _calculateBounds(markers);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(_trip!.origin.latitude, _trip!.origin.longitude),
        zoom: 13,
      ),
      markers: markers,
      polylines: polylines,
      onMapCreated: (controller) {
        _mapController = controller;
        // Ajustar cámara a los bounds
        Future.delayed(const Duration(milliseconds: 300), () {
          controller.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 80),
          );
        });
      },
      myLocationEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }

  LatLngBounds _calculateBounds(Set<Marker> markers) {
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final marker in markers) {
      minLat = minLat < marker.position.latitude
          ? minLat
          : marker.position.latitude;
      maxLat = maxLat > marker.position.latitude
          ? maxLat
          : marker.position.latitude;
      minLng = minLng < marker.position.longitude
          ? minLng
          : marker.position.longitude;
      maxLng = maxLng > marker.position.longitude
          ? maxLng
          : marker.position.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Botón atrás
          Container(
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
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
          ),

          // Badge de desvío
          if (_deviationInfo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.warning.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_road,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'DESVÍO +${_deviationInfo!.deviationMinutes} MIN',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 20,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Info del pasajero
              _buildPassengerInfo(),

              const SizedBox(height: 20),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 20),

              // Punto de recogida
              _buildPickupInfo(),

              const SizedBox(height: 20),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 20),

              // Preferencias del pasajero
              _buildPreferencesInfo(),

              const SizedBox(height: 20),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 20),

              // Método de pago
              _buildPaymentInfo(),

              const SizedBox(height: 32),

              // Botones de acción
              _buildActionButtons(),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPassengerInfo() {
    return Row(
      children: [
        // Avatar
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.tertiary,
            border: Border.all(color: AppColors.divider, width: 2),
          ),
          child: ClipOval(
            child: _passengerUser?.profilePhotoUrl != null
                ? Image.network(
                    _passengerUser!.profilePhotoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildAvatarPlaceholder(),
                  )
                : _buildAvatarPlaceholder(),
          ),
        ),
        const SizedBox(width: 16),

        // Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getFullName(),
                style: AppTextStyles.h3,
              ),
              const SizedBox(height: 4),
              if (_passengerUser?.rating != null)
                Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      _passengerUser!.rating!.toStringAsFixed(1),
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              if (_passengerUser?.career != null) ...[
                const SizedBox(height: 4),
                Text(
                  _passengerUser!.career,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarPlaceholder() {
    final initials = _getInitials();
    return Container(
      color: AppColors.primary.withOpacity(0.1),
      child: Center(
        child: Text(
          initials,
          style: AppTextStyles.h3.copyWith(
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  String _getFullName() {
    if (_passengerUser == null) return 'Pasajero';
    return '${_passengerUser!.firstName} ${_passengerUser!.lastName}';
  }

  String _getInitials() {
    if (_passengerUser == null) return '?';
    final first = _passengerUser!.firstName.isNotEmpty
        ? _passengerUser!.firstName[0].toUpperCase()
        : '';
    final last = _passengerUser!.lastName.isNotEmpty
        ? _passengerUser!.lastName[0].toUpperCase()
        : '';
    return '$first$last';
  }

  Widget _buildPickupInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.place,
                color: AppColors.warning,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Punto de recogida',
              style: AppTextStyles.body1.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _passenger!.pickupPoint?.name ?? 'No especificado',
                style: AppTextStyles.body2,
              ),
              if (_passenger!.referenceNote != null &&
                  _passenger!.referenceNote!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _passenger!.referenceNote!,
                          style: AppTextStyles.caption.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreferencesInfo() {
    final prefs = _passenger!.preferences;
    final hasObjetoGrande = prefs.contains('objeto_grande');
    final hasMascota = prefs.contains('mascota');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.info,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '¿Qué lleva?',
              style: AppTextStyles.body1.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Lista de preferencias
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (prefs.contains('mochila'))
                _buildPreferenceChip(
                  icon: Icons.backpack_outlined,
                  label: 'Mochila',
                  color: AppColors.textSecondary,
                ),
              if (hasObjetoGrande)
                _buildPreferenceChip(
                  icon: Icons.inventory_2,
                  label: 'Objeto grande',
                  color: AppColors.info,
                ),
              if (hasMascota && _passenger!.petType != null)
                _buildPetChip(),
            ],
          ),
        ),

        // Descripción del objeto grande
        if (hasObjetoGrande && _passenger!.objectDescription != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _passenger!.objectDescription!,
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Info de mascota
        if (hasMascota && _passenger!.petType == 'otro' && _passenger!.petDescription != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('🐾', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mascota: ${_passenger!.petDescription}',
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPreferenceChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPetChip() {
    String emoji;
    String label;

    switch (_passenger!.petType) {
      case 'perro':
        emoji = '🐕';
        label = _passenger!.petSize != null
            ? 'Perro (${_passenger!.petSize})'
            : 'Perro';
        break;
      case 'gato':
        emoji = '🐱';
        label = 'Gato';
        break;
      case 'otro':
        emoji = '🐾';
        label = 'Otra mascota';
        break;
      default:
        emoji = '🐾';
        label = 'Mascota';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w500,
              color: Colors.amber.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo() {
    final isEfectivo = _passenger!.paymentMethod == 'Efectivo';

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isEfectivo ? Icons.payments_outlined : Icons.phone_android,
            color: AppColors.success,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Método de pago',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              _passenger!.paymentMethod,
              style: AppTextStyles.body2.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const Spacer(),
        Text(
          '\$${_passenger!.price.toStringAsFixed(2)}',
          style: AppTextStyles.h3.copyWith(
            color: AppColors.success,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Rechazar
        Expanded(
          child: OutlinedButton(
            onPressed: _isProcessing ? null : _rejectPassenger,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Rechazar',
              style: AppTextStyles.button.copyWith(color: AppColors.error),
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Aceptar
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _acceptPassenger,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Agregar al viaje',
                  style: AppTextStyles.button,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
