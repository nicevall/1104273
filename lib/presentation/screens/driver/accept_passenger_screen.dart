// lib/presentation/screens/driver/accept_passenger_screen.dart
// Pantalla para que el conductor vea y acepte una solicitud de pasajero
// Muestra mapa con desvío, info del pasajero, botones aceptar/rechazar

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/ride_request_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/route_info.dart';
import '../../../data/services/trips_service.dart';
import '../../../data/services/ride_requests_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/google_directions_service.dart';
import '../../../data/services/tts_service.dart';
import '../../../core/utils/car_marker_generator.dart';

class AcceptPassengerScreen extends StatefulWidget {
  final String tripId;
  final String requestId;

  const AcceptPassengerScreen({
    super.key,
    required this.tripId,
    required this.requestId,
  });

  @override
  State<AcceptPassengerScreen> createState() => _AcceptPassengerScreenState();
}

class _AcceptPassengerScreenState extends State<AcceptPassengerScreen> {
  final _tripsService = TripsService();
  final _requestsService = RideRequestsService();
  final _firestoreService = FirestoreService();
  final _directionsService = GoogleDirectionsService();
  final _ttsService = TtsService();

  GoogleMapController? _mapController;
  BitmapDescriptor? _carIcon;

  TripModel? _trip;
  RideRequestModel? _request;
  UserModel? _passengerUser;
  DeviationInfo? _deviationInfo;

  bool _isLoading = true;
  bool _isProcessing = false;
  bool _isReviewing = false; // Si marcamos la solicitud como reviewing en Firestore
  bool _detailsExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    // Parar TTS al salir
    _ttsService.stop();
    // Si salimos sin aceptar, restaurar a searching
    if (_isReviewing && !_isProcessing) {
      _requestsService.unreviewRequest(widget.requestId);
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Cargar viaje del conductor
      final trip = await _tripsService.getTrip(widget.tripId);
      if (trip == null) {
        setState(() {
          _error = 'Viaje no encontrado';
          _isLoading = false;
        });
        return;
      }

      // Cargar solicitud del pasajero
      final request = await _requestsService.getRequest(widget.requestId);
      if (request == null) {
        setState(() {
          _error = 'Solicitud no encontrada';
          _isLoading = false;
        });
        return;
      }

      // Verificar que la solicitud aún esté disponible
      if (request.status != 'searching') {
        setState(() {
          _error = 'Esta solicitud ya no está disponible';
          _isLoading = false;
        });
        return;
      }

      // Verificar que passengerId no esté vacío (datos huérfanos)
      if (request.passengerId.isEmpty) {
        debugPrint('⚠️ AcceptPassenger: solicitud ${widget.requestId} tiene passengerId vacío');
        setState(() {
          _error = 'Solicitud inválida (datos incompletos)';
          _isLoading = false;
        });
        return;
      }

      // Cargar info del pasajero
      final user = await _firestoreService.getUser(request.passengerId);
      debugPrint('🧑 AcceptPassenger: passengerId=${request.passengerId}, user=${user?.firstName} ${user?.lastName}, career=${user?.career}');

      // Calcular desvío
      DeviationInfo? deviation;
      final acceptedPickups = trip.passengers
          .where((p) => p.status == 'accepted' && p.pickupPoint != null)
          .map((p) => p.pickupPoint!)
          .toList();

      deviation = await _directionsService.calculateTotalDeviation(
        origin: trip.origin,
        destination: trip.destination,
        acceptedPickups: acceptedPickups,
        newPickup: request.pickupPoint,
      );

      // Cargar ícono del carro
      final carIcon = await CarMarkerGenerator.generate(size: 120);

      if (mounted) {
        setState(() {
          _trip = trip;
          _request = request;
          _passengerUser = user;
          _deviationInfo = deviation;
          _carIcon = carIcon;
          _isLoading = false;
        });

        // Marcar solicitud como "reviewing" para pausar timer del pasajero
        _requestsService.reviewRequest(widget.requestId).then((_) {
          _isReviewing = true;
        }).catchError((_) {});

        // Leer detalles con TTS
        _speakRequestDetails(request, user);
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

  /// Leer detalles de la solicitud con TTS
  void _speakRequestDetails(RideRequestModel request, UserModel? user) {
    final buffer = StringBuffer();

    // 1. Carrera del pasajero
    if (user?.career != null && user!.career.isNotEmpty) {
      buffer.write('Estudiante de ${user.career}.');
    }

    // 2. Referencia del punto de recogida
    if (request.referenceNote != null && request.referenceNote!.isNotEmpty) {
      buffer.write(' Referencia: ${request.referenceNote}.');
    }

    // 3. Objeto grande
    if (request.hasLargeObject) {
      if (request.objectDescription != null &&
          request.objectDescription!.isNotEmpty) {
        buffer.write(' Lleva ${request.objectDescription}.');
      } else {
        buffer.write(' Lleva objeto grande.');
      }
    }

    // 4. Mascota con detalles
    if (request.hasPet) {
      switch (request.petType) {
        case 'perro':
          buffer.write(' Lleva perro');
          if (request.petSize != null && request.petSize!.isNotEmpty) {
            buffer.write(' tamaño ${request.petSize}');
          }
          buffer.write('.');
          break;
        case 'gato':
          buffer.write(' Lleva gato.');
          break;
        case 'otro':
          buffer.write(' Lleva de mascota un ${request.petDescription}.');
          break;
      }
    }

    final text = buffer.toString().trim();
    if (text.isNotEmpty) {
      _ttsService.speakRequest(text);
    }
  }

  void _acceptPassenger() async {
    if (_trip == null || _request == null) return;

    // Parar TTS inmediatamente al querer aceptar
    _ttsService.stop();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text(
          '¿Aceptar a ${_passengerUser?.firstName ?? "este pasajero"} en tu viaje?',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Aceptar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      // 1. Aceptar la solicitud (actualiza el documento en ride_requests)
      await _requestsService.acceptRequest(
        requestId: widget.requestId,
        driverId: _trip!.driverId,
        tripId: widget.tripId,
        agreedPrice: 0.0,
      );

      // 2. Agregar el pasajero al viaje (como TripPassenger)
      final passenger = TripPassenger(
        userId: _request!.passengerId,
        status: 'accepted',
        pickupPoint: _request!.pickupPoint,
        price: 0.0,
        paymentMethod: _request!.paymentMethod,
        preferences: _request!.preferences,
        referenceNote: _request!.referenceNote,
        objectDescription: _request!.objectDescription,
        petType: _request!.petType,
        petSize: _request!.petSize,
        petDescription: _request!.petDescription,
        requestedAt: _request!.requestedAt,
      );

      await _tripsService.requestToJoin(widget.tripId, passenger);

      // 3. Actualizar SOLO asientos disponibles (sin sobrescribir passengers)
      await FirebaseFirestore.instance
          .collection('trips')
          .doc(widget.tripId)
          .update({
        'availableSeats': FieldValue.increment(-1),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_passengerUser?.firstName ?? "Pasajero"} agregado al viaje',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        // Devolver el passengerId para que la pantalla padre lo sepa de inmediato
        context.pop(_request!.passengerId);
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

    if (_error != null || _trip == null || _request == null) {
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
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: AppColors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Error desconocido',
                  style: AppTextStyles.body1,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Volver'),
                ),
              ],
            ),
          ),
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
    // Markers: solo conductor (origen/posición actual) y pickup del pasajero
    final markers = <Marker>{
      // Posición del conductor (ícono carro)
      Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(_trip!.origin.latitude, _trip!.origin.longitude),
        icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'Tu ubicación'),
      ),
      // Pickup del pasajero (naranja)
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(
          _request!.pickupPoint.latitude,
          _request!.pickupPoint.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: 'Recogida',
          snippet: _request!.pickupPoint.name,
        ),
      ),
    };

    // Polyline de ruta con pickup (turquesa) — solo esta, sin la gris
    final polylines = <Polyline>{};
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

    // Bounds: conductor + pickup del pasajero
    final driverLat = _trip!.origin.latitude;
    final driverLng = _trip!.origin.longitude;
    final pickupLat = _request!.pickupPoint.latitude;
    final pickupLng = _request!.pickupPoint.longitude;

    final bounds = LatLngBounds(
      southwest: LatLng(
        driverLat < pickupLat ? driverLat : pickupLat,
        driverLng < pickupLng ? driverLng : pickupLng,
      ),
      northeast: LatLng(
        driverLat > pickupLat ? driverLat : pickupLat,
        driverLng > pickupLng ? driverLng : pickupLng,
      ),
    );

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(
          (driverLat + pickupLat) / 2,
          (driverLng + pickupLng) / 2,
        ),
        zoom: 14,
      ),
      markers: markers,
      polylines: polylines,
      // Padding inferior para que el bottom card no tape los markers
      padding: const EdgeInsets.only(bottom: 280, top: 60),
      onMapCreated: (controller) {
        _mapController = controller;
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

  Widget _buildTopOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      child: Container(
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
    );
  }

  Widget _buildBottomSheet() {
    final hasDetails = _hasExtraDetails();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
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
                const SizedBox(height: 14),

                // — Fila pasajero: avatar + nombre + rating + timer
                _buildPassengerRow(),

                const SizedBox(height: 12),

                // — Pickup compacto (una línea)
                _buildPickupRow(),

                // — Chips rápidos de pago + preferencias
                const SizedBox(height: 10),
                _buildQuickChips(),

                // — "Ver detalles" / "Ocultar detalles" (solo si hay detalles)
                if (hasDetails) ...[
                  const SizedBox(height: 10),
                  _buildToggleDetails(),
                ],

                const SizedBox(height: 14),

                // — Botón "Agregar al viaje" siempre visible
                _buildActionButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasExtraDetails() {
    return (_request!.referenceNote != null &&
            _request!.referenceNote!.isNotEmpty) ||
        _request!.hasLargeObject ||
        _request!.hasPet ||
        _request!.preferences.contains('mochila');
  }

  /// Fila compacta: avatar 48x48 + nombre + rating + carrera + timer
  Widget _buildPassengerRow() {
    return Row(
      children: [
        // Avatar
        Container(
          width: 48,
          height: 48,
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
        const SizedBox(width: 12),

        // Nombre + rating + carrera
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _getShortName(),
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_passengerUser?.rating != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.star, size: 14, color: AppColors.warning),
                    const SizedBox(width: 2),
                    Text(
                      _passengerUser!.rating.toStringAsFixed(1),
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
              if (_passengerUser?.career != null &&
                  _passengerUser!.career.isNotEmpty)
                Text(
                  _passengerUser!.career,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),

        // Timer de expiración
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _request!.minutesUntilExpiry <= 5
                ? AppColors.error.withOpacity(0.1)
                : AppColors.textSecondary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer,
                size: 13,
                color: _request!.minutesUntilExpiry <= 5
                    ? AppColors.error
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 3),
              Text(
                '${_request!.minutesUntilExpiry} min',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: _request!.minutesUntilExpiry <= 5
                      ? AppColors.error
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Fila de pickup: ícono naranja + nombre del punto
  Widget _buildPickupRow() {
    return Row(
      children: [
        Icon(Icons.place, color: Colors.orange.shade600, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _request!.pickupPoint.name,
            style: AppTextStyles.body2.copyWith(
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_request!.referenceNote != null &&
            _request!.referenceNote!.isNotEmpty) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: _request!.referenceNote!,
            child: Icon(
              Icons.info_outline,
              size: 16,
              color: AppColors.textSecondary.withOpacity(0.6),
            ),
          ),
        ],
      ],
    );
  }

  /// Chips rápidos: método de pago + indicadores si lleva algo
  Widget _buildQuickChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        // Método de pago
        _buildMiniChip(
          icon: _request!.paymentMethod == 'Efectivo'
              ? Icons.payments_outlined
              : Icons.phone_android,
          label: _request!.paymentMethod,
          bgColor: AppColors.success.withOpacity(0.1),
          iconColor: AppColors.success,
        ),
        // Si tiene mascota
        if (_request!.hasPet)
          _buildMiniChip(
            icon: null,
            emoji: _request!.petIcon,
            label: _getPetLabel(),
            bgColor: Colors.amber.withOpacity(0.12),
            iconColor: Colors.amber.shade800,
          ),
        // Si tiene objeto grande
        if (_request!.hasLargeObject)
          _buildMiniChip(
            icon: Icons.inventory_2,
            label: 'Objeto grande',
            bgColor: AppColors.info.withOpacity(0.1),
            iconColor: AppColors.info,
          ),
      ],
    );
  }

  Widget _buildMiniChip({
    IconData? icon,
    String? emoji,
    required String label,
    required Color bgColor,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null)
            Text(emoji, style: const TextStyle(fontSize: 12))
          else if (icon != null)
            Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 11,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Toggle "Ver detalles" / "Ocultar detalles" con AnimatedCrossFade
  Widget _buildToggleDetails() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tap para expandir/colapsar
        GestureDetector(
          onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _detailsExpanded ? 'Ocultar detalles' : 'Ver detalles',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _detailsExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.expand_more,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Contenido expandible
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildDetailsSection(),
          ),
          crossFadeState: _detailsExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }

  /// Sección de detalles — visible al tocar "Ver detalles"
  Widget _buildDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detalles',
          style: AppTextStyles.body1.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),

        // Referencia del pickup
        if (_request!.referenceNote != null &&
            _request!.referenceNote!.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ref: ${_request!.referenceNote}',
                  style: AppTextStyles.body2.copyWith(
                    fontStyle: FontStyle.italic,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        // Mochila
        if (_request!.preferences.contains('mochila')) ...[
          Row(
            children: [
              const Icon(Icons.backpack_outlined,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Lleva mochila',
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // Objeto grande con descripción
        if (_request!.hasLargeObject) ...[
          Row(
            children: [
              const Icon(Icons.inventory_2,
                  size: 18, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (_request!.objectDescription != null &&
                          _request!.objectDescription!.isNotEmpty)
                      ? 'Lleva: ${_request!.objectDescription}'
                      : 'Lleva objeto grande',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.info,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // Mascota con detalles
        if (_request!.hasPet) ...[
          Row(
            children: [
              Text(_request!.petIcon,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getDetailedPetLabel(),
                  style: AppTextStyles.body2.copyWith(
                    color: Colors.amber.shade800,
                  ),
                ),
              ),
            ],
          ),
        ],
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
          style: AppTextStyles.body1.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Nombre corto: "Juan P."
  String _getShortName() {
    if (_passengerUser == null) return 'Pasajero';
    final first = _passengerUser!.firstName;
    final lastInitial = _passengerUser!.lastName.isNotEmpty
        ? '${_passengerUser!.lastName[0].toUpperCase()}.'
        : '';
    return '$first $lastInitial';
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

  String _getPetLabel() {
    switch (_request!.petType) {
      case 'perro':
        return _request!.petSize != null
            ? 'Perro (${_request!.petSize})'
            : 'Perro';
      case 'gato':
        return 'Gato';
      case 'otro':
        return 'Otra mascota';
      default:
        return 'Mascota';
    }
  }

  String _getDetailedPetLabel() {
    final base = _getPetLabel();
    if (_request!.petType == 'otro' &&
        _request!.petDescription != null &&
        _request!.petDescription!.isNotEmpty) {
      return '$base: ${_request!.petDescription}';
    }
    return base;
  }

  /// Botón principal "Agregar al viaje"
  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : _acceptPassenger,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
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
    );
  }
}
