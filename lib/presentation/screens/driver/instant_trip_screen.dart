// lib/presentation/screens/driver/instant_trip_screen.dart
// Pantalla para ofrecer disponibilidad inmediata (conductor)
// Flujo: Ruta (origen GPS + destino) -> Preferencias -> Publicar

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/google_places_service.dart';
import 'package:google_maps_webservice/places.dart' as gmaps;
import '../../../data/services/google_directions_service.dart';
import '../../../data/services/pricing_service.dart';
import '../../../data/services/location_cache_service.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../blocs/trip/trip_event.dart';
import '../../blocs/trip/trip_state.dart';

class InstantTripScreen extends StatefulWidget {
  final String userId;

  const InstantTripScreen({
    super.key,
    required this.userId,
  });

  @override
  State<InstantTripScreen> createState() => _InstantTripScreenState();
}

class _InstantTripScreenState extends State<InstantTripScreen> {
  final _placesService = GooglePlacesService();

  // === Fase ===
  bool _routeConfirmed = false;

  // === Ruta ===
  TripLocation? _origin;
  TripLocation? _destination;
  String _originText = '';
  String _destinationText = '';
  bool _isLoadingLocation = true;
  double? _originLatitude;
  double? _originLongitude;

  // === Búsqueda destino ===
  final _destController = TextEditingController();
  final _destFocusNode = FocusNode();
  List<PlaceSuggestion> _destSuggestions = [];
  bool _isSearchingDest = false;
  Timer? _searchDebounce;

  // === Capacidad y Precio ===
  int _capacity = 3;
  int _maxCapacity = 4;
  final _directionsService = GoogleDirectionsService();
  final _pricingService = PricingService();
  FareResult? _fareResult;
  bool _isCalculatingFare = false;

  // === Preferencias ===
  bool _allowsLuggage = true;
  bool _allowsPets = true; // Instantáneo: acepta todo para máximas solicitudes
  String _chatLevel = 'moderado';
  int _maxWaitMinutes = 2;

  // === Estado ===
  VehicleModel? _vehicle;
  bool _isLoading = false;
  // _confirmDataCorrect removed — button auto-enables when inputs valid

  /// Validates all required fields for publishing
  bool get _isFormValid {
    return _routeConfirmed &&
        _origin != null &&
        _destination != null &&
        _vehicle != null &&
        _capacity > 0 &&
        _chatLevel.isNotEmpty &&
        _maxWaitMinutes > 0;
  }

  @override
  void initState() {
    super.initState();
    _loadVehicle();
    _initializeLocationFromCache();
  }

  /// Intenta usar la ubicación cacheada primero para carga instantánea
  void _initializeLocationFromCache() {
    final cache = LocationCacheService();

    // Si hay ubicación fresca en caché, usarla inmediatamente
    if (cache.hasFreshLocation) {
      final cached = cache.cachedLocation!;
      setState(() {
        _originLatitude = cached.latitude;
        _originLongitude = cached.longitude;
        _origin = TripLocation(
          name: cached.shortName ?? 'Mi ubicación',
          address: cached.fullAddress ?? '${cached.latitude}, ${cached.longitude}',
          latitude: cached.latitude,
          longitude: cached.longitude,
        );
        _originText = cached.shortName ?? 'Mi ubicación';
        _isLoadingLocation = false;
      });
    } else {
      // Si no hay caché o está desactualizada, detectar ubicación normalmente
      _detectCurrentLocation();
    }
  }

  @override
  void dispose() {
    _destController.dispose();
    _destFocusNode.dispose();
    _searchDebounce?.cancel();
    _placesService.dispose();
    super.dispose();
  }

  // ============================================================
  // DATA LOADING
  // ============================================================

  Future<void> _loadVehicle() async {
    try {
      final vehicle =
          await FirestoreService().getUserVehicle(widget.userId);
      if (vehicle != null && mounted) {
        setState(() {
          _vehicle = vehicle;
          _maxCapacity = vehicle.capacity;
          if (_capacity > _maxCapacity) {
            _capacity = _maxCapacity;
          }
        });
      }
    } catch (e) {
      // Vehicle info is optional for display
    }
  }

  Future<void> _detectCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
            _originText = 'Tu ubicación';
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      _originLatitude = position.latitude;
      _originLongitude = position.longitude;

      final result = await _placesService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (result != null && mounted) {
        // Actualizar el caché con la nueva ubicación
        LocationCacheService().updateLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          shortName: result.shortName,
          fullAddress: result.fullAddress,
        );

        setState(() {
          _origin = TripLocation(
            name: result.shortName,
            address: result.fullAddress,
            latitude: position.latitude,
            longitude: position.longitude,
          );
          _originText = result.shortName;
          _isLoadingLocation = false;
        });
      } else if (mounted) {
        // Actualizar el caché incluso sin geocoding
        LocationCacheService().updateLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          shortName: 'Mi ubicación',
          fullAddress: '${position.latitude}, ${position.longitude}',
        );

        setState(() {
          _origin = TripLocation(
            name: 'Mi ubicación',
            address: '${position.latitude}, ${position.longitude}',
            latitude: position.latitude,
            longitude: position.longitude,
          );
          _originText = 'Mi ubicación';
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _originText = 'Tu ubicación';
        });
      }
    }
  }

  // ============================================================
  // SEARCH DESTINATION
  // ============================================================

  void _searchDestPlaces(String query) {
    _searchDebounce?.cancel();

    if (query.length < 2) {
      setState(() {
        _destSuggestions = [];
        _isSearchingDest = false;
      });
      return;
    }

    setState(() => _isSearchingDest = true);

    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        gmaps.Location? loc;
        if (_originLatitude != null && _originLongitude != null) {
          loc = gmaps.Location(lat: _originLatitude!, lng: _originLongitude!);
        }
        final results = await _placesService.searchPlaces(
          query: query,
          location: loc,
        );
        if (mounted) {
          setState(() {
            _destSuggestions = results;
            _isSearchingDest = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingDest = false);
      }
    });
  }

  Future<void> _selectDestPlace(PlaceSuggestion suggestion) async {
    try {
      final details =
          await _placesService.getPlaceDetails(suggestion.placeId);
      if (details != null && mounted) {
        setState(() {
          _destination = TripLocation(
            name: suggestion.mainText,
            address: suggestion.secondaryText,
            latitude: details.latitude,
            longitude: details.longitude,
          );
          _destinationText = suggestion.mainText;
          _destController.text = suggestion.mainText;
          _destSuggestions = [];
          _destFocusNode.unfocus();
        });
      }
    } catch (_) {}
  }

  void _onChooseOnMap() {
    if (_isLoadingLocation || _originLatitude == null) {
      _showError('Esperando ubicación GPS...');
      return;
    }

    context.push('/trip/pick-location', extra: {
      'userId': widget.userId,
      'userRole': 'conductor',
      'originLatitude': _originLatitude ?? -3.9931,
      'originLongitude': _originLongitude ?? -79.2042,
      'originAddress': _originText,
    }).then((result) {
      if (result != null && result is Map<String, dynamic>) {
        setState(() {
          _destination = TripLocation(
            name: result['name'] ?? 'Destino seleccionado',
            address: result['address'] ?? '',
            latitude: result['latitude'] as double,
            longitude: result['longitude'] as double,
          );
          _destinationText = result['name'] ?? 'Destino seleccionado';
          _destController.text = _destinationText;
          _destSuggestions = [];
        });
      }
    });
  }

  void _clearDestination() {
    setState(() {
      _destination = null;
      _destinationText = '';
      _destController.clear();
      _destSuggestions = [];
    });
  }

  // ============================================================
  // FARE CALCULATION
  // ============================================================

  Future<void> _calculateFare() async {
    if (_origin == null || _destination == null) return;

    setState(() => _isCalculatingFare = true);

    try {
      final routeInfo = await _directionsService.getRoute(
        originLat: _origin!.latitude,
        originLng: _origin!.longitude,
        destLat: _destination!.latitude,
        destLng: _destination!.longitude,
      );

      if (routeInfo != null && mounted) {
        final fare = _pricingService.calculateFromMeters(
          distanceMeters: routeInfo.distanceMeters,
          durationSeconds: routeInfo.durationSeconds,
        );
        setState(() {
          _fareResult = fare;
          _isCalculatingFare = false;
        });
      } else if (mounted) {
        setState(() => _isCalculatingFare = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCalculatingFare = false);
      }
    }
  }

  // ============================================================
  // PUBLISH TRIP
  // ============================================================

  void _publishTrip() {
    if (_origin == null) {
      _showError('Esperando ubicación GPS...');
      return;
    }
    if (_destination == null) {
      _showError('Selecciona un destino');
      return;
    }
    if (_vehicle == null) {
      _showError('No se encontró tu vehículo registrado');
      return;
    }
    final trip = TripModel(
      tripId: '',
      driverId: widget.userId,
      vehicleId: _vehicle!.vehicleId,
      status: 'active',
      origin: _origin!,
      destination: _destination!,
      departureTime: DateTime.now(),
      recurringDays: null,
      pricePerPassenger: 0.0,
      useTaximeter: true,
      distanceKm: _fareResult?.distanceKm ?? 0.0,
      durationMinutes: _fareResult?.durationMinutes ?? 0,
      totalCapacity: _capacity,
      availableSeats: _capacity,
      allowsLuggage: _allowsLuggage,
      allowsPets: _allowsPets,
      chatLevel: _chatLevel,
      maxWaitMinutes: _maxWaitMinutes,
      additionalNotes: null,
      createdAt: DateTime.now(),
    );

    context.read<TripBloc>().add(CreateTripEvent(trip: trip));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return BlocListener<TripBloc, TripState>(
      listener: (context, state) {
        if (state is TripCreated) {
          // Viaje instantáneo → ir directo a lista de pasajeros disponibles
          if (state.trip.isActive) {
            context.go('/driver/active-requests/${state.trip.tripId}');
          } else {
            // Viaje programado → ir a confirmación
            context.go('/driver/trip-created', extra: {
              'trip': state.trip,
            });
          }
        } else if (state is TripError) {
          _showError(state.error);
          setState(() => _isLoading = false);
        } else if (state is TripLoading) {
          setState(() => _isLoading = true);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon:
                const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () {
              if (_routeConfirmed) {
                setState(() => _routeConfirmed = false);
              } else {
                context.pop();
              }
            },
          ),
          title: Text(
            'Viaje inmediato',
            style:
                AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
          ),
          centerTitle: true,
        ),
        body: _routeConfirmed
            ? _buildPreferencesForm()
            : _buildRouteSelection(),
      ),
    );
  }

  // ============================================================
  // FASE A: ROUTE SELECTION
  // ============================================================

  Widget _buildRouteSelection() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Ruta del viaje', Icons.route),
                const SizedBox(height: 8),
                Text(
                  'Selecciona el origen y destino de tu viaje',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),

                // Origen (read-only, GPS)
                _buildOriginField(),

                const SizedBox(height: 12),

                // Destino (editable)
                _buildDestinationField(),

                // Sugerencias de destino
                if (_destSuggestions.isNotEmpty) _buildDestSuggestions(),

                // Opción elegir en el mapa
                _buildMapPickerOption(),

                // Ubicación predeterminada: UIDE Loja
                _buildUideShortcut(),
              ],
            ),
          ),
        ),

        // Boton confirmar ruta
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: AppColors.background,
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: AppDimensions.buttonHeightLarge,
            child: ElevatedButton(
              onPressed: (_origin != null && _destination != null)
                  ? () {
                      setState(() => _routeConfirmed = true);
                      _calculateFare();
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.tertiary,
                disabledForegroundColor: AppColors.disabled,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                      AppDimensions.buttonRadius),
                ),
                elevation: 0,
              ),
              child:
                  Text('Confirmar Ruta', style: AppTextStyles.button),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOriginField() {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.tertiary,
          borderRadius: BorderRadius.circular(AppDimensions.radiusM),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(
              Icons.my_location,
              color: AppColors.primary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isLoadingLocation
                    ? 'Obteniendo ubicación...'
                    : _originText,
                style: AppTextStyles.body2.copyWith(
                  color: _isLoadingLocation
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_isLoadingLocation)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            else
              const Icon(
                Icons.gps_fixed,
                color: AppColors.textSecondary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestinationField() {
    return TextField(
      controller: _destController,
      focusNode: _destFocusNode,
      textInputAction: TextInputAction.search,
      onChanged: (value) {
        _searchDestPlaces(value);
        // Si borra texto, limpiar destino seleccionado
        if (value.isEmpty && _destination != null) {
          setState(() {
            _destination = null;
            _destinationText = '';
          });
        }
      },
      style: AppTextStyles.body2.copyWith(
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: '¿A dónde vas?',
        hintStyle: AppTextStyles.body2.copyWith(
          color: AppColors.textTertiary,
        ),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 12, right: 8),
          child: Icon(
            Icons.circle,
            color: AppColors.success,
            size: 12,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 0,
        ),
        suffixIcon: _isSearchingDest
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              )
            : _destController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary,
                    onPressed: _clearDestination,
                  )
                : const Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusM),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusM),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusM),
          borderSide: const BorderSide(
              color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _buildDestSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppDimensions.radiusM),
        boxShadow: [
          BoxShadow(color: AppColors.shadow, blurRadius: 8),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _destSuggestions.length,
        itemBuilder: (context, index) {
          final s = _destSuggestions[index];
          return ListTile(
            dense: true,
            leading: const Icon(
              Icons.location_on_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            title: Text(
              s.mainText,
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              s.secondaryText,
              style: AppTextStyles.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _selectDestPlace(s),
          );
        },
      ),
    );
  }

  Widget _buildMapPickerOption() {
    return GestureDetector(
      onTap: _onChooseOnMap,
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(AppDimensions.radiusM),
          border: Border.all(color: AppColors.inputBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.map_outlined,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Elegir en el mapa',
                    style: AppTextStyles.body2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Mueve el mapa para seleccionar tu destino',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUideShortcut() {
    return GestureDetector(
      onTap: _onUideSelected,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(AppDimensions.radiusM),
          border: Border.all(color: AppColors.inputBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.school,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UIDE Loja',
                    style: AppTextStyles.body2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Universidad Internacional del Ecuador',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _onUideSelected() {
    if (_isLoadingLocation || _originLatitude == null) {
      _showError('Esperando ubicación GPS...');
      return;
    }

    setState(() {
      _destination = TripLocation(
        name: 'UIDE Loja',
        address: 'Universidad Internacional del Ecuador, Agustín Carrión Palacios, Loja, Ecuador',
        latitude: -3.97245,
        longitude: -79.19933,
      );
      _destinationText = 'UIDE Loja';
      _destController.text = 'UIDE Loja';
      _destSuggestions = [];
      _destFocusNode.unfocus();
      // Avanzar directamente a preferencias (igual que "Confirmar Ruta")
      _routeConfirmed = true;
    });
    _calculateFare();
  }

  // ============================================================
  // FASE B: PREFERENCES FORM
  // ============================================================

  Widget _buildPreferencesForm() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Route summary (tappable to go back)
                _buildRouteSummaryCard(),

                const SizedBox(height: 24),

                // ===== CAPACITY =====
                _buildSectionHeader(
                    'Asientos disponibles', Icons.people_outline),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStepperButton(
                      icon: Icons.remove,
                      enabled: _capacity > 1,
                      onTap: () {
                        if (_capacity > 1) setState(() => _capacity--);
                      },
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          Text(
                            '$_capacity',
                            style: AppTextStyles.h1.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            'pasajeros',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStepperButton(
                      icon: Icons.add,
                      enabled: _capacity < _maxCapacity,
                      onTap: () {
                        if (_capacity < _maxCapacity) {
                          setState(() => _capacity++);
                        }
                      },
                    ),
                  ],
                ),

                // Seat icons
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _maxCapacity,
                    (i) => Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.event_seat,
                        size: 28,
                        color: i < _capacity
                            ? AppColors.primary
                            : AppColors.tertiary,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Conversation level
                _buildSectionHeader(
                    'Nivel de conversación', Icons.chat),
                const SizedBox(height: 4),
                Text(
                  '¿Qué ambiente prefieres durante el viaje?',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildChatChip('silencioso', Icons.volume_off,
                        'Silencioso'),
                    const SizedBox(width: 8),
                    _buildChatChip('moderado',
                        Icons.chat_bubble_outline, 'Moderado'),
                    const SizedBox(width: 8),
                    _buildChatChip('hablador',
                        Icons.record_voice_over, 'Hablador'),
                  ],
                ),

                const SizedBox(height: 24),

                // Max wait time
                _buildSectionHeader(
                    'Tiempo de espera máximo',
                    Icons.timer_outlined),
                const SizedBox(height: 4),
                Text(
                  '¿Cuánto esperas a un pasajero en el punto de recogida?',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildWaitTimeChip(1),
                    const SizedBox(width: 8),
                    _buildWaitTimeChip(2),
                    const SizedBox(width: 8),
                    _buildWaitTimeChip(3),
                  ],
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // Publish button
        _buildPublishButton(),
      ],
    );
  }

  Widget _buildRouteSummaryCard() {
    return GestureDetector(
      onTap: () => setState(() => _routeConfirmed = false),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius:
              BorderRadius.circular(AppDimensions.radiusM),
          border: Border.all(color: AppColors.inputBorder),
        ),
        child: Row(
          children: [
            Column(
              children: [
                const Icon(Icons.circle,
                    size: 10, color: AppColors.primary),
                Container(
                    width: 1, height: 16, color: AppColors.divider),
                const Icon(Icons.circle,
                    size: 10, color: AppColors.success),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _originText,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _destinationText,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildPublishButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: AppDimensions.buttonHeightLarge,
        child: ElevatedButton(
          onPressed: _isLoading
              ? null
              : (_isFormValid ? _publishTrip : null),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.tertiary,
            disabledForegroundColor: AppColors.disabled,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                  AppDimensions.buttonRadius),
            ),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  'PUBLICAR DISPONIBILIDAD',
                  style: AppTextStyles.button,
                ),
        ),
      ),
    );
  }

  // ============================================================
  // SHARED WIDGETS
  // ============================================================

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.body1.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primary
              : AppColors.tertiary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color:
              enabled ? Colors.white : AppColors.disabled,
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildChatChip(
      String value, IconData icon, String label) {
    final isSelected = _chatLevel == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _chatLevel = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.inputFill,
            borderRadius: BorderRadius.circular(
                AppDimensions.radiusM),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.inputBorder,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  if (isSelected)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontWeight: isSelected
                      ? FontWeight.w700
                      : FontWeight.w400,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaitTimeChip(int minutes) {
    final isSelected = _maxWaitMinutes == minutes;
    return Expanded(
      child: GestureDetector(
        onTap: () =>
            setState(() => _maxWaitMinutes = minutes),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.inputFill,
            borderRadius:
                BorderRadius.circular(AppDimensions.radiusM),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.inputBorder,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              if (isSelected)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(
                    Icons.check_circle,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
              Text(
                '$minutes min',
                style: AppTextStyles.caption.copyWith(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontWeight: isSelected
                      ? FontWeight.w700
                      : FontWeight.w400,
                  fontSize: isSelected ? 13 : 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
