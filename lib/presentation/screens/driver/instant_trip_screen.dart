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
  bool _useSmartPricing = true;
  double _smartPrice = 1.50;
  double _manualPrice = 1.50;

  // === Preferencias ===
  bool _allowsLuggage = true;
  bool _allowsPets = false;
  String _chatLevel = 'flexible';
  int _maxWaitMinutes = 5;
  final _notesController = TextEditingController();

  // === Estado ===
  VehicleModel? _vehicle;
  bool _isLoading = false;
  bool _confirmDataCorrect = false;

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
    _notesController.dispose();
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
        final results = await _placesService.searchPlaces(query: query);
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

    final price = _useSmartPricing ? _smartPrice : _manualPrice;

    final trip = TripModel(
      tripId: '',
      driverId: widget.userId,
      vehicleId: _vehicle!.vehicleId,
      status: 'active',
      origin: _origin!,
      destination: _destination!,
      departureTime: DateTime.now(),
      recurringDays: null,
      pricePerPassenger: price,
      totalCapacity: _capacity,
      availableSeats: _capacity,
      allowsLuggage: _allowsLuggage,
      allowsPets: _allowsPets,
      chatLevel: _chatLevel,
      maxWaitMinutes: _maxWaitMinutes,
      additionalNotes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
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
          // Viaje instantáneo → ir a pantalla de viaje activo (mapa + solicitudes)
          if (state.trip.isActive) {
            context.go('/driver/active-trip/${state.trip.tripId}');
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
                  ? () => setState(() => _routeConfirmed = true)
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

                // ===== PRICING =====
                _buildSectionHeader(
                    'Precio por pasajero', Icons.attach_money),
                const SizedBox(height: 12),

                // Smart pricing card
                _buildPricingCard(
                  title: 'Precio Inteligente',
                  subtitle:
                      'Calculado en base a la distancia y hora',
                  price: _smartPrice,
                  isSelected: _useSmartPricing,
                  isRecommended: true,
                  onTap: () =>
                      setState(() => _useSmartPricing = true),
                ),

                const SizedBox(height: 12),

                // Manual pricing card
                _buildManualPricingCard(),

                const SizedBox(height: 28),

                // ===== PREFERENCES =====
                _buildSectionHeader('Preferencias', Icons.tune),
                const SizedBox(height: 12),

                // Luggage toggle
                _buildToggleRow(
                  icon: Icons.luggage_outlined,
                  label: 'Permite equipaje grande',
                  value: _allowsLuggage,
                  onChanged: (v) =>
                      setState(() => _allowsLuggage = v),
                ),

                const SizedBox(height: 4),

                // Pets toggle
                _buildToggleRow(
                  icon: Icons.pets_outlined,
                  label: 'Permite mascotas',
                  value: _allowsPets,
                  onChanged: (v) =>
                      setState(() => _allowsPets = v),
                ),

                const SizedBox(height: 20),

                // Conversation level
                _buildSectionHeader(
                    'Nivel de conversación', Icons.chat),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildWaitTimeChip(3),
                    const SizedBox(width: 8),
                    _buildWaitTimeChip(5),
                    const SizedBox(width: 8),
                    _buildWaitTimeChip(10),
                    const SizedBox(width: 8),
                    _buildWaitTimeChip(15),
                  ],
                ),

                const SizedBox(height: 24),

                // Additional notes
                _buildSectionHeader(
                    'Notas adicionales', Icons.note_outlined),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  maxLength: 150,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'Ej: Salgo puntual, paso por la av. principal...',
                    hintStyle: AppTextStyles.body2.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    filled: true,
                    fillColor: AppColors.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          AppDimensions.radiusM),
                      borderSide: const BorderSide(
                          color: AppColors.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          AppDimensions.radiusM),
                      borderSide: const BorderSide(
                          color: AppColors.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          AppDimensions.radiusM),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 2),
                    ),
                    counterStyle: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  style: AppTextStyles.body2,
                  onChanged: (_) => setState(() {}),
                ),

                const SizedBox(height: 16),

                // Confirmation checkbox
                CheckboxListTile(
                  value: _confirmDataCorrect,
                  onChanged: (v) => setState(
                      () => _confirmDataCorrect = v ?? false),
                  title: Text(
                    'Confirmo que los datos son correctos',
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  activeColor: AppColors.primary,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
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
              : (_confirmDataCorrect ? _publishTrip : null),
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
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.1)
                : AppColors.inputFill,
            borderRadius: BorderRadius.circular(
                AppDimensions.radiusM),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.inputBorder,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontWeight: isSelected
                      ? FontWeight.w600
                      : FontWeight.w400,
                  fontSize: 11,
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
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.1)
                : AppColors.inputFill,
            borderRadius:
                BorderRadius.circular(AppDimensions.radiusM),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.inputBorder,
            ),
          ),
          child: Center(
            child: Text(
              '$minutes min',
              style: AppTextStyles.caption.copyWith(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight: isSelected
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String subtitle,
    required double price,
    required bool isSelected,
    required VoidCallback onTap,
    bool isRecommended = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.05)
              : AppColors.inputFill,
          borderRadius:
              BorderRadius.circular(AppDimensions.radiusM),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.inputBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.disabled,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.body2.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success
                                .withOpacity(0.15),
                            borderRadius:
                                BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Recomendado',
                            style:
                                AppTextStyles.caption.copyWith(
                              fontSize: 10,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '\$${price.toStringAsFixed(2)}',
              style: AppTextStyles.h3.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualPricingCard() {
    final isSelected = !_useSmartPricing;
    return GestureDetector(
      onTap: () => setState(() => _useSmartPricing = false),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.05)
              : AppColors.inputFill,
          borderRadius:
              BorderRadius.circular(AppDimensions.radiusM),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.inputBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Radio indicator
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.disabled,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Precio Manual',
                        style: AppTextStyles.body2.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Establece tu propio precio',
                        style:
                            AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStepperButton(
                    icon: Icons.remove,
                    enabled: _manualPrice > 0.25,
                    onTap: () {
                      if (_manualPrice > 0.25) {
                        setState(() => _manualPrice =
                            double.parse(
                                (_manualPrice - 0.25)
                                    .toStringAsFixed(2)));
                      }
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24),
                    child: Text(
                      '\$${_manualPrice.toStringAsFixed(2)}',
                      style: AppTextStyles.h2.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  _buildStepperButton(
                    icon: Icons.add,
                    enabled: _manualPrice < 10.00,
                    onTap: () {
                      if (_manualPrice < 10.00) {
                        setState(() => _manualPrice =
                            double.parse(
                                (_manualPrice + 0.25)
                                    .toStringAsFixed(2)));
                      }
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
