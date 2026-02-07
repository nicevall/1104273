// lib/presentation/screens/driver/create_trip_screen.dart
// Pantalla para crear un viaje programado (conductor)
// Wizard de 4 pasos: Fecha/Hora, Capacidad/Precio, Preferencias, Confirmacion

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:widget_to_marker/widget_to_marker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/google_places_service.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../blocs/trip/trip_event.dart';
import '../../blocs/trip/trip_state.dart';
import '../../widgets/common/progress_bar.dart';

class CreateTripScreen extends StatefulWidget {
  final String userId;

  const CreateTripScreen({
    super.key,
    required this.userId,
  });

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _placesService = GooglePlacesService();

  // === Wizard ===
  int _currentStep = 0;
  final PageController _pageController = PageController();
  bool _routeConfirmed = false;

  // === Ruta ===
  TripLocation? _origin;
  TripLocation? _destination;
  String _originText = '';
  String _destinationText = '';

  // === Horario (Step 1) ===
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  List<int> _recurringDays = [];
  bool _isRecurring = false;

  // === Capacidad y Precio (Step 2) ===
  int _capacity = 3;
  int _maxCapacity = 4;
  bool _useSmartPricing = true;
  double _smartPrice = 1.50;
  double _manualPrice = 1.50;

  // === Preferencias (Step 3) ===
  bool _allowsLuggage = true;
  bool _allowsPets = false;
  String _chatLevel = 'flexible';
  int _maxWaitMinutes = 5;
  final _notesController = TextEditingController();

  // === Confirmacion (Step 4) ===
  bool _confirmDataCorrect = false;
  GoogleMapController? _confirmMapController;
  Set<Marker> _confirmMarkers = {};
  Set<Polyline> _confirmPolylines = {};
  bool _confirmMarkersCreated = false;

  // === Estado ===
  VehicleModel? _vehicle;
  bool _isLoading = false;

  // === Search ===
  final _originSearchController = TextEditingController();
  final _destSearchController = TextEditingController();
  List<PlaceSuggestion> _originSuggestions = [];
  List<PlaceSuggestion> _destSuggestions = [];
  bool _showOriginSearch = false;
  bool _showDestSearch = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadVehicle();
    _detectCurrentLocation();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _notesController.dispose();
    _originSearchController.dispose();
    _destSearchController.dispose();
    _searchDebounce?.cancel();
    _confirmMapController?.dispose();
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
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final result = await _placesService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (result != null && mounted) {
        setState(() {
          _origin = TripLocation(
            name: result.shortName,
            address: result.fullAddress,
            latitude: position.latitude,
            longitude: position.longitude,
          );
          _originText = result.shortName;
        });
      }
    } catch (e) {
      // Location detection failed - user can set manually
    }
  }

  // ============================================================
  // SEARCH PLACES
  // ============================================================

  void _searchOriginPlaces(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (query.length < 2) {
        setState(() => _originSuggestions = []);
        return;
      }
      try {
        final results = await _placesService.searchPlaces(query: query);
        if (mounted) {
          setState(() => _originSuggestions = results);
        }
      } catch (_) {}
    });
  }

  void _searchDestPlaces(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (query.length < 2) {
        setState(() => _destSuggestions = []);
        return;
      }
      try {
        final results = await _placesService.searchPlaces(query: query);
        if (mounted) {
          setState(() => _destSuggestions = results);
        }
      } catch (_) {}
    });
  }

  Future<void> _selectOriginPlace(PlaceSuggestion suggestion) async {
    try {
      final details =
          await _placesService.getPlaceDetails(suggestion.placeId);
      if (details != null && mounted) {
        setState(() {
          _origin = TripLocation(
            name: suggestion.mainText,
            address: suggestion.secondaryText,
            latitude: details.latitude,
            longitude: details.longitude,
          );
          _originText = suggestion.mainText;
          _showOriginSearch = false;
          _originSuggestions = [];
          _originSearchController.clear();
        });
      }
    } catch (_) {}
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
          _showDestSearch = false;
          _destSuggestions = [];
          _destSearchController.clear();
        });
      }
    } catch (_) {}
  }

  // ============================================================
  // WIZARD NAVIGATION
  // ============================================================

  void _goToNextStep() {
    if (_currentStep < 3) {
      _pageController.animateToPage(
        _currentStep + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPreviousStep() {
    if (_currentStep > 0) {
      _pageController.animateToPage(
        _currentStep - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0: // Fecha y Hora
        final departureTime = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          _selectedTime.hour,
          _selectedTime.minute,
        );
        return departureTime.isAfter(DateTime.now());
      case 1: // Capacidad y Precio
        if (_useSmartPricing) return true;
        return _manualPrice > 0;
      case 2: // Preferencias
        return true;
      case 3: // Confirmacion
        return _confirmDataCorrect;
      default:
        return false;
    }
  }

  // ============================================================
  // TIME PICKER
  // ============================================================

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.background,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  // ============================================================
  // RECURRING DAYS
  // ============================================================

  void _toggleRecurringDay(int day) {
    setState(() {
      if (_recurringDays.contains(day)) {
        _recurringDays.remove(day);
      } else {
        _recurringDays.add(day);
      }
      _recurringDays.sort();
    });
  }

  // ============================================================
  // CONFIRMATION MAP (Step 4)
  // ============================================================

  void _onConfirmMapCreated(GoogleMapController controller) {
    _confirmMapController = controller;
    Future.delayed(const Duration(milliseconds: 500), () {
      _fitConfirmBounds();
    });
  }

  void _fitConfirmBounds() {
    if (_confirmMapController == null ||
        _origin == null ||
        _destination == null) return;

    final originLatLng = LatLng(_origin!.latitude, _origin!.longitude);
    final destLatLng = LatLng(_destination!.latitude, _destination!.longitude);

    final bounds = LatLngBounds(
      southwest: LatLng(
        originLatLng.latitude < destLatLng.latitude
            ? originLatLng.latitude
            : destLatLng.latitude,
        originLatLng.longitude < destLatLng.longitude
            ? originLatLng.longitude
            : destLatLng.longitude,
      ),
      northeast: LatLng(
        originLatLng.latitude > destLatLng.latitude
            ? originLatLng.latitude
            : destLatLng.latitude,
        originLatLng.longitude > destLatLng.longitude
            ? originLatLng.longitude
            : destLatLng.longitude,
      ),
    );

    _confirmMapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  void _createConfirmPolyline() {
    if (_origin == null || _destination == null) return;

    final originLatLng = LatLng(_origin!.latitude, _origin!.longitude);
    final destLatLng = LatLng(_destination!.latitude, _destination!.longitude);

    _confirmPolylines = {
      Polyline(
        polylineId: const PolylineId('confirm_route_base'),
        points: [originLatLng, destLatLng],
        color: const Color(0xFF6CCC91).withOpacity(0.3),
        width: 5,
      ),
      Polyline(
        polylineId: const PolylineId('confirm_route'),
        points: [originLatLng, destLatLng],
        color: const Color(0xFF6CCC91),
        width: 5,
        patterns: [
          PatternItem.dash(16),
          PatternItem.gap(10),
        ],
      ),
    };
  }

  Future<void> _createConfirmMarkers() async {
    if (_confirmMarkersCreated ||
        _origin == null ||
        _destination == null) return;
    _confirmMarkersCreated = true;

    final originLatLng = LatLng(_origin!.latitude, _origin!.longitude);
    final destLatLng = LatLng(_destination!.latitude, _destination!.longitude);

    try {
      final originIcon =
          await _buildMarkerWidget(AppColors.primary).toBitmapDescriptor(
        logicalSize: const Size(48, 58),
        imageSize: const Size(96, 116),
      );

      final destinationIcon =
          await _buildMarkerWidget(const Color(0xFF6CCC91))
              .toBitmapDescriptor(
        logicalSize: const Size(48, 58),
        imageSize: const Size(96, 116),
      );

      if (mounted) {
        setState(() {
          _confirmMarkers = {
            Marker(
              markerId: const MarkerId('confirm_origin'),
              position: originLatLng,
              icon: originIcon,
              anchor: const Offset(0.5, 1.0),
            ),
            Marker(
              markerId: const MarkerId('confirm_destination'),
              position: destLatLng,
              icon: destinationIcon,
              anchor: const Offset(0.5, 1.0),
            ),
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _confirmMarkers = {
            Marker(
              markerId: const MarkerId('confirm_origin'),
              position: originLatLng,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueCyan),
            ),
            Marker(
              markerId: const MarkerId('confirm_destination'),
              position: destLatLng,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen),
            ),
          };
        });
      }
    }
  }

  Widget _buildMarkerWidget(Color color) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 48,
        height: 58,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
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

  // ============================================================
  // PUBLISH TRIP
  // ============================================================

  void _publishTrip() {
    if (_origin == null) {
      _showError('Selecciona un punto de origen');
      return;
    }
    if (_destination == null) {
      _showError('Selecciona un destino');
      return;
    }
    if (_vehicle == null) {
      _showError('No se encontr\u00f3 tu veh\u00edculo registrado');
      return;
    }

    final price = _useSmartPricing ? _smartPrice : _manualPrice;

    final departureTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    if (departureTime.isBefore(DateTime.now())) {
      _showError('La hora de salida debe ser en el futuro');
      return;
    }

    final trip = TripModel(
      tripId: '',
      driverId: widget.userId,
      vehicleId: _vehicle!.vehicleId,
      status: 'scheduled',
      origin: _origin!,
      destination: _destination!,
      departureTime: departureTime,
      recurringDays: _isRecurring && _recurringDays.isNotEmpty
          ? _recurringDays
          : null,
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
          context.go('/driver/trip-created', extra: {
            'trip': state.trip,
          });
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
              if (_routeConfirmed && _currentStep > 0) {
                _goToPreviousStep();
              } else if (_routeConfirmed && _currentStep == 0) {
                setState(() => _routeConfirmed = false);
              } else {
                context.pop();
              }
            },
          ),
          title: Text(
            'Crear viaje',
            style:
                AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
          ),
          centerTitle: true,
        ),
        body: _routeConfirmed
            ? _buildWizardContent()
            : _buildRouteSelection(),
      ),
    );
  }

  // ============================================================
  // PRE-WIZARD: ROUTE SELECTION
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

                // Origen
                _buildLocationField(
                  label: 'Origen',
                  value: _originText,
                  icon: Icons.circle,
                  iconColor: AppColors.primary,
                  isSearching: _showOriginSearch,
                  onTap: () =>
                      setState(() => _showOriginSearch = true),
                  onClear: () => setState(() {
                    _origin = null;
                    _originText = '';
                  }),
                ),
                if (_showOriginSearch) _buildOriginSearch(),

                const SizedBox(height: 12),

                // Destino
                _buildLocationField(
                  label: 'Destino',
                  value: _destinationText,
                  icon: Icons.circle,
                  iconColor: AppColors.success,
                  isSearching: _showDestSearch,
                  onTap: () =>
                      setState(() => _showDestSearch = true),
                  onClear: () => setState(() {
                    _destination = null;
                    _destinationText = '';
                  }),
                ),
                if (_showDestSearch) _buildDestSearch(),
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

  // ============================================================
  // WIZARD CONTENT
  // ============================================================

  Widget _buildWizardContent() {
    return Column(
      children: [
        // Route summary card (compact)
        _buildRouteSummaryCard(),

        // Progress bar
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: ProgressBar(
            currentStep: _currentStep + 1,
            totalSteps: 4,
            showText: true,
          ),
        ),

        // Step header
        _buildStepHeader(),

        // PageView
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) => setState(() {
              _currentStep = index;
              // Prepare Step 4 map when navigating to it
              if (index == 3) {
                _createConfirmPolyline();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _createConfirmMarkers();
                });
              }
            }),
            children: [
              _buildStep1DateAndTime(),
              _buildStep2CapacityAndPrice(),
              _buildStep3Preferences(),
              _buildStep4Confirmation(),
            ],
          ),
        ),

        // Navigation buttons
        _buildNavigationButtons(),
      ],
    );
  }

  Widget _buildRouteSummaryCard() {
    return GestureDetector(
      onTap: () => setState(() {
        _routeConfirmed = false;
        _confirmMarkersCreated = false;
      }),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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

  Widget _buildStepHeader() {
    final titles = [
      'Fecha y Hora',
      'Capacidad y Precio',
      'Preferencias',
      'Confirmaci\u00f3n',
    ];
    final subtitles = [
      'Selecciona cu\u00e1ndo sales',
      'Define asientos y precio',
      'Configura tu viaje',
      'Revisa y publica',
    ];

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titles[_currentStep],
            style: AppTextStyles.h2,
          ),
          const SizedBox(height: 2),
          Text(
            subtitles[_currentStep],
            style: AppTextStyles.body2.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
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
      child: Row(
        children: [
          // Back button
          if (_currentStep > 0) ...[
            Expanded(
              child: SizedBox(
                height: AppDimensions.buttonHeightLarge,
                child: OutlinedButton(
                  onPressed: _goToPreviousStep,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          AppDimensions.buttonRadius),
                    ),
                  ),
                  child: Text(
                    'Atr\u00e1s',
                    style: AppTextStyles.body1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Next / Publish button
          Expanded(
            child: SizedBox(
              height: AppDimensions.buttonHeightLarge,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : (_canProceed()
                        ? (_currentStep == 3
                            ? _publishTrip
                            : _goToNextStep)
                        : null),
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
                        _currentStep == 3
                            ? 'PUBLICAR VIAJE'
                            : 'Siguiente',
                        style: AppTextStyles.button,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STEP 1: FECHA Y HORA
  // ============================================================

  Widget _buildStep1DateAndTime() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar
          _buildSectionHeader('Fecha', Icons.calendar_today),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius:
                  BorderRadius.circular(AppDimensions.radiusM),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: AppColors.primary,
                  onPrimary: Colors.white,
                  surface: AppColors.inputFill,
                  onSurface: AppColors.textPrimary,
                ),
              ),
              child: CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime.now(),
                lastDate:
                    DateTime.now().add(const Duration(days: 7)),
                onDateChanged: (date) =>
                    setState(() => _selectedDate = date),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Time
          _buildSectionHeader(
              'Hora de salida', Icons.access_time),
          const SizedBox(height: 8),
          _buildPickerField(
            label: _selectedTime.format(context),
            icon: Icons.access_time,
            onTap: _selectTime,
          ),

          const SizedBox(height: 20),

          // Recurring toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Viaje recurrente',
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Switch(
                value: _isRecurring,
                onChanged: (v) =>
                    setState(() => _isRecurring = v),
                activeColor: AppColors.primary,
              ),
            ],
          ),

          if (_isRecurring) ...[
            const SizedBox(height: 8),
            _buildDayChips(),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // STEP 2: CAPACIDAD Y PRECIO
  // ============================================================

  Widget _buildStep2CapacityAndPrice() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Capacity
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

          // Pricing
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
        ],
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

  // ============================================================
  // STEP 3: PREFERENCIAS
  // ============================================================

  Widget _buildStep3Preferences() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              'Nivel de conversaci\u00f3n', Icons.chat),
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
              'Tiempo de espera m\u00e1ximo',
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
        ],
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

  // ============================================================
  // STEP 4: CONFIRMACION
  // ============================================================

  Widget _buildStep4Confirmation() {
    final price =
        _useSmartPricing ? _smartPrice : _manualPrice;
    final departureTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Map preview
          if (_origin != null && _destination != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(
                  AppDimensions.radiusM),
              child: SizedBox(
                height: 180,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                        _origin!.latitude, _origin!.longitude),
                    zoom: 13,
                  ),
                  onMapCreated: _onConfirmMapCreated,
                  markers: _confirmMarkers,
                  polylines: _confirmPolylines,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  scrollGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  liteModeEnabled: true,
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Trip summary card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(
                  AppDimensions.radiusM),
              border:
                  Border.all(color: AppColors.inputBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Route
                Row(
                  children: [
                    const Icon(Icons.circle,
                        size: 10, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _originText,
                        style: AppTextStyles.body2.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Container(
                    width: 1,
                    height: 12,
                    color: AppColors.divider,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.circle,
                        size: 10, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _destinationText,
                        style: AppTextStyles.body2.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const Divider(height: 24),

                // Date & Time
                _buildSummaryRow(
                  Icons.calendar_today,
                  'Fecha',
                  DateFormat('EEE d MMM yyyy', 'es')
                      .format(departureTime),
                ),
                const SizedBox(height: 8),
                _buildSummaryRow(
                  Icons.access_time,
                  'Hora de salida',
                  _selectedTime.format(context),
                ),

                if (_isRecurring &&
                    _recurringDays.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    Icons.repeat,
                    'Recurrente',
                    _recurringDays
                        .map((d) => [
                              '',
                              'L',
                              'M',
                              'X',
                              'J',
                              'V',
                              'S',
                              'D'
                            ][d])
                        .join(', '),
                  ),
                ],

                const Divider(height: 24),

                // Capacity & Price
                _buildSummaryRow(
                  Icons.people_outline,
                  'Asientos',
                  '$_capacity pasajeros',
                ),
                const SizedBox(height: 8),
                _buildSummaryRow(
                  Icons.attach_money,
                  'Precio',
                  '\$${price.toStringAsFixed(2)} por pasajero${_useSmartPricing ? ' (inteligente)' : ''}',
                ),

                if (_vehicle != null) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    Icons.directions_car,
                    'Veh\u00edculo',
                    '${_vehicle!.brand} ${_vehicle!.model} - ${_vehicle!.plate}',
                  ),
                ],

                const Divider(height: 24),

                // Preferences
                _buildSummaryRow(
                  Icons.luggage_outlined,
                  'Equipaje grande',
                  _allowsLuggage ? 'S\u00ed' : 'No',
                ),
                const SizedBox(height: 8),
                _buildSummaryRow(
                  Icons.pets_outlined,
                  'Mascotas',
                  _allowsPets ? 'S\u00ed' : 'No',
                ),
                const SizedBox(height: 8),
                _buildSummaryRow(
                  Icons.chat,
                  'Conversaci\u00f3n',
                  _chatLevel == 'silencioso'
                      ? 'Silencioso'
                      : _chatLevel == 'moderado'
                          ? 'Moderado'
                          : 'Hablador',
                ),
                const SizedBox(height: 8),
                _buildSummaryRow(
                  Icons.timer_outlined,
                  'Espera m\u00e1x.',
                  '$_maxWaitMinutes min',
                ),

                if (_notesController.text
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    Icons.note_outlined,
                    'Notas',
                    _notesController.text.trim(),
                  ),
                ],
              ],
            ),
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
    );
  }

  Widget _buildSummaryRow(
      IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.body2.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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

  Widget _buildLocationField({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required bool isSearching,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return GestureDetector(
      onTap: value.isEmpty ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingL,
          vertical: AppDimensions.paddingM,
        ),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius:
              BorderRadius.circular(AppDimensions.radiusM),
          border: Border.all(
            color: isSearching
                ? AppColors.primary
                : AppColors.inputBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: value.isNotEmpty
                  ? Text(
                      value,
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      label,
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
            ),
            if (value.isNotEmpty)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close,
                    size: 18,
                    color: AppColors.textSecondary),
              )
            else
              const Icon(Icons.search,
                  size: 18,
                  color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildOriginSearch() {
    return Column(
      children: [
        const SizedBox(height: 8),
        TextField(
          controller: _originSearchController,
          autofocus: true,
          onChanged: _searchOriginPlaces,
          decoration: InputDecoration(
            hintText: 'Buscar origen...',
            hintStyle: AppTextStyles.body2
                .copyWith(color: AppColors.textTertiary),
            prefixIcon: const Icon(Icons.search,
                color: AppColors.textSecondary),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() {
                _showOriginSearch = false;
                _originSuggestions = [];
                _originSearchController.clear();
              }),
            ),
            filled: true,
            fillColor: AppColors.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                  AppDimensions.radiusM),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12),
          ),
          style: AppTextStyles.body2,
        ),
        if (_originSuggestions.isNotEmpty)
          Container(
            constraints:
                const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(
                  AppDimensions.radiusM),
              boxShadow: [
                BoxShadow(
                    color: AppColors.shadow, blurRadius: 8)
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _originSuggestions.length,
              itemBuilder: (context, index) {
                final s = _originSuggestions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: AppColors.textSecondary),
                  title: Text(s.mainText,
                      style: AppTextStyles.body2.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500)),
                  subtitle: Text(s.secondaryText,
                      style: AppTextStyles.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  onTap: () => _selectOriginPlace(s),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDestSearch() {
    return Column(
      children: [
        const SizedBox(height: 8),
        TextField(
          controller: _destSearchController,
          autofocus: true,
          onChanged: _searchDestPlaces,
          decoration: InputDecoration(
            hintText: 'Buscar destino...',
            hintStyle: AppTextStyles.body2
                .copyWith(color: AppColors.textTertiary),
            prefixIcon: const Icon(Icons.search,
                color: AppColors.textSecondary),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() {
                _showDestSearch = false;
                _destSuggestions = [];
                _destSearchController.clear();
              }),
            ),
            filled: true,
            fillColor: AppColors.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                  AppDimensions.radiusM),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12),
          ),
          style: AppTextStyles.body2,
        ),
        if (_destSuggestions.isNotEmpty)
          Container(
            constraints:
                const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(
                  AppDimensions.radiusM),
              boxShadow: [
                BoxShadow(
                    color: AppColors.shadow, blurRadius: 8)
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _destSuggestions.length,
              itemBuilder: (context, index) {
                final s = _destSuggestions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: AppColors.textSecondary),
                  title: Text(s.mainText,
                      style: AppTextStyles.body2.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500)),
                  subtitle: Text(s.secondaryText,
                      style: AppTextStyles.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  onTap: () => _selectDestPlace(s),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildPickerField({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingL,
          vertical: AppDimensions.paddingM,
        ),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius:
              BorderRadius.circular(AppDimensions.radiusM),
          border: Border.all(color: AppColors.inputBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayChips() {
    const days = [
      {'day': 1, 'label': 'L'},
      {'day': 2, 'label': 'M'},
      {'day': 3, 'label': 'X'},
      {'day': 4, 'label': 'J'},
      {'day': 5, 'label': 'V'},
      {'day': 6, 'label': 'S'},
      {'day': 7, 'label': 'D'},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: days.map((d) {
        final dayNum = d['day'] as int;
        final isSelected =
            _recurringDays.contains(dayNum);
        return GestureDetector(
          onTap: () => _toggleRecurringDay(dayNum),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.inputFill,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.inputBorder,
              ),
            ),
            child: Center(
              child: Text(
                d['label'] as String,
                style: AppTextStyles.caption.copyWith(
                  color: isSelected
                      ? Colors.white
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
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
}
