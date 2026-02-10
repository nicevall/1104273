// lib/presentation/screens/trip/plan_trip_screen.dart
// Pantalla "Planifica tu viaje" - Estilo Uber
// Permite seleccionar origen, destino con autocompletado de Google Places

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_webservice/places.dart' as gmaps;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/services/google_places_service.dart';
import '../../../data/services/location_cache_service.dart';

class PlanTripScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final Map<String, dynamic>? preselectedDestination;

  const PlanTripScreen({
    super.key,
    required this.userId,
    required this.userRole,
    this.preselectedDestination,
  });

  @override
  State<PlanTripScreen> createState() => _PlanTripScreenState();
}

class _PlanTripScreenState extends State<PlanTripScreen> {
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocus = FocusNode();

  bool _isLoadingLocation = true;
  bool _isSearching = false;

  // Coordenadas del origen actual
  double? _originLatitude;
  double? _originLongitude;
  String? _originAddress; // Dirección completa del origen

  // Servicio de Google Places
  late final GooglePlacesService _placesService;

  // Sugerencias de lugares
  List<PlaceSuggestion> _suggestions = [];

  // Timer para debounce de búsqueda
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _placesService = GooglePlacesService();

    // Primero intentar usar ubicación cacheada, luego detectar si no hay
    _initializeLocationFromCache();

    // Si hay destino preseleccionado
    if (widget.preselectedDestination != null) {
      _destinationController.text = widget.preselectedDestination!['name'] ?? '';
    }

    // Escuchar cambios de foco solo en destino (limpiar sugerencias al perder foco)
    _destinationFocus.addListener(() {
      if (!_destinationFocus.hasFocus) {
        setState(() {
          _suggestions = [];
        });
      }
    });

    // Escuchar cambios en el campo de destino para autocompletado
    _destinationController.addListener(_onDestinationChanged);

    // Auto-focus en destino
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.preselectedDestination == null) {
        _destinationFocus.requestFocus();
      }
    });
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
        _originController.text = cached.shortName ?? 'Mi ubicación';
        _originAddress = cached.fullAddress;
        _isLoadingLocation = false;
      });
    } else {
      // Si no hay caché o está desactualizada, detectar ubicación normalmente
      _detectCurrentLocation();
    }
  }

  void _onDestinationChanged() {
    // Cancelar timer anterior
    _debounceTimer?.cancel();

    final query = _destinationController.text;

    if (query.length < 2) {
      setState(() {
        _suggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    // Debounce: esperar 300ms antes de buscar
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _searchPlaces(query);
    });
  }

  Future<void> _searchPlaces(String query) async {
    try {
      // Usar ubicación actual para sesgar resultados si está disponible
      gmaps.Location? location;
      if (_originLatitude != null && _originLongitude != null) {
        location = gmaps.Location(lat: _originLatitude!, lng: _originLongitude!);
      }

      final suggestions = await _placesService.searchPlaces(
        query: query,
        location: location,
      );

      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _isSearching = false;
        });
      }
    } catch (e) {
      print('Error al buscar lugares: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _detectCurrentLocation() async {
    try {
      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _originController.text = 'Tu ubicación';
          _isLoadingLocation = false;
        });
        return;
      }

      // Verificar si el servicio de ubicación está habilitado
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _originController.text = 'Tu ubicación';
          _isLoadingLocation = false;
        });
        return;
      }

      // Obtener ubicación actual
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      _originLatitude = position.latitude;
      _originLongitude = position.longitude;

      // Usar Google Geocoding API directamente (mejor resultados en Ecuador)
      try {
        final geocodeResult = await _placesService.reverseGeocode(
          position.latitude,
          position.longitude,
        );

        if (geocodeResult != null && mounted) {
          // Actualizar el caché con la nueva ubicación
          LocationCacheService().updateLocation(
            latitude: position.latitude,
            longitude: position.longitude,
            shortName: geocodeResult.shortName,
            fullAddress: geocodeResult.fullAddress,
          );

          setState(() {
            _originController.text = geocodeResult.shortName;
            _originAddress = geocodeResult.fullAddress;
            _isLoadingLocation = false;
          });
        } else {
          // Fallback al paquete geocoding
          List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );

          if (placemarks.isNotEmpty) {
            Placemark place = placemarks.first;
            String address = _buildAddressFromPlacemark(place);
            String fullAddress = _buildFullAddress(place);

            setState(() {
              _originController.text = address;
              _originAddress = fullAddress;
              _isLoadingLocation = false;
            });
          } else {
            setState(() {
              _originController.text = 'Tu ubicación actual';
              _originAddress = 'Tu ubicación actual';
              _isLoadingLocation = false;
            });
          }
        }
      } catch (e) {
        print('Error en geocoding: $e');
        setState(() {
          _originController.text = 'Tu ubicación actual';
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      setState(() {
        _originController.text = 'Tu ubicación';
        _isLoadingLocation = false;
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _originController.dispose();
    _destinationController.removeListener(_onDestinationChanged);
    _destinationController.dispose();
    _destinationFocus.dispose();
    _placesService.dispose();
    super.dispose();
  }

  /// Construye una dirección legible desde un Placemark
  /// Evita mostrar Plus Codes (formato: XXXX+XXX)
  String _buildAddressFromPlacemark(Placemark place) {
    bool isPlusCode(String? text) {
      if (text == null || text.isEmpty) return false;
      return RegExp(r'^[A-Z0-9]{4,6}\+[A-Z0-9]{2,4}$', caseSensitive: false).hasMatch(text);
    }

    // Lista de candidatos para la dirección
    List<String?> candidates = [
      place.thoroughfare,
      place.street,
      place.subLocality,
      place.locality,
      place.subAdministrativeArea,
    ];

    for (String? candidate in candidates) {
      if (candidate != null && candidate.isNotEmpty && !isPlusCode(candidate)) {
        if (place.thoroughfare != null &&
            place.thoroughfare!.isNotEmpty &&
            !isPlusCode(place.thoroughfare)) {
          String result = place.thoroughfare!;
          if (place.subThoroughfare != null &&
              place.subThoroughfare!.isNotEmpty &&
              !isPlusCode(place.subThoroughfare)) {
            result = '${place.thoroughfare} ${place.subThoroughfare}';
          }
          return result;
        }
        return candidate;
      }
    }

    if (place.name != null && place.name!.isNotEmpty && !isPlusCode(place.name)) {
      return place.name!;
    }

    if (place.locality != null && place.locality!.isNotEmpty) {
      return place.locality!;
    }

    return 'Tu ubicación actual';
  }

  /// Construye la dirección completa incluyendo calle, número y barrio
  String _buildFullAddress(Placemark place) {
    List<String> parts = [];

    // Calle y número
    if (place.thoroughfare != null && place.thoroughfare!.isNotEmpty) {
      String street = place.thoroughfare!;
      if (place.subThoroughfare != null && place.subThoroughfare!.isNotEmpty) {
        street = '$street ${place.subThoroughfare}';
      }
      parts.add(street);
    }

    // Barrio/Sector
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      parts.add(place.subLocality!);
    }

    // Ciudad
    if (place.locality != null && place.locality!.isNotEmpty) {
      parts.add(place.locality!);
    }

    if (parts.isEmpty) {
      return _originController.text;
    }

    return parts.join(', ');
  }

  Future<void> _onSuggestionSelected(PlaceSuggestion suggestion) async {
    // Verificar que el origen esté detectado
    if (_isLoadingLocation || _originLatitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Espera a que se detecte tu ubicación'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Obtener detalles del lugar
    final details = await _placesService.getPlaceDetails(suggestion.placeId);

    if (details != null) {
      setState(() {
        _destinationController.text = suggestion.mainText;
        _suggestions = [];
      });

      // Guardar en búsquedas recientes
      _saveRecentSearch(suggestion, details);

      // Navegar al mapa
      _navigateToConfirmPickup(details);
    }
  }

  // Lista de búsquedas recientes (en memoria por ahora)
  static final List<Map<String, dynamic>> _recentSearches = [];

  void _saveRecentSearch(PlaceSuggestion suggestion, PlaceDetails details) {
    // Evitar duplicados
    _recentSearches.removeWhere((s) => s['placeId'] == suggestion.placeId);

    // Agregar al inicio
    _recentSearches.insert(0, {
      'placeId': suggestion.placeId,
      'mainText': suggestion.mainText,
      'secondaryText': suggestion.secondaryText,
      'latitude': details.latitude,
      'longitude': details.longitude,
      'address': details.address,
    });

    // Máximo 5 recientes
    if (_recentSearches.length > 5) {
      _recentSearches.removeLast();
    }
  }

  void _navigateToConfirmPickup(PlaceDetails destination) {
    final originLat = _originLatitude ?? -3.9931;
    final originLng = _originLongitude ?? -79.2042;

    context.push('/trip/confirm-pickup', extra: {
      'userId': widget.userId,
      'userRole': widget.userRole,
      'origin': {
        'name': _originController.text,
        'address': _originAddress ?? _originController.text,
        'latitude': originLat,
        'longitude': originLng,
      },
      'destination': {
        'name': destination.name,
        'address': destination.address,
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Planifica tu viaje',
          style: AppTextStyles.h3,
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),

          // Campos de origen y destino
          _buildRouteInputs(),

          const SizedBox(height: 16),

          // Separador
          const Divider(height: 1, color: AppColors.divider),

          // Lista de sugerencias o mensaje vacío
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInputs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Campo origen (solo lectura - no seleccionable)
          IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.tertiary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.my_location,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isLoadingLocation
                          ? 'Obteniendo ubicación...'
                          : _originController.text,
                      style: AppTextStyles.body1.copyWith(
                        fontSize: 16,
                        color: _isLoadingLocation
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_isLoadingLocation)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  else
                    Icon(
                      Icons.gps_fixed,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Campo destino
          TextField(
            controller: _destinationController,
            focusNode: _destinationFocus,
            textInputAction: TextInputAction.search,
            keyboardType: TextInputType.streetAddress,
            style: AppTextStyles.body1.copyWith(
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: '¿A dónde vas?',
              hintStyle: AppTextStyles.body1.copyWith(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
              prefixIcon: Icon(
                Icons.location_on,
                color: AppColors.primary,
                size: 24,
              ),
              suffixIcon: _isSearching
                  ? Container(
                      width: 20,
                      height: 20,
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : _destinationController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _destinationController.clear();
                              _suggestions = [];
                            });
                            _destinationFocus.requestFocus();
                          },
                        )
                      : null,
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.border,
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.border,
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // Si hay sugerencias, mostrarlas
    if (_suggestions.isNotEmpty) {
      return _buildSuggestionsList();
    }

    // Mostrar opción de elegir en mapa + estado vacío
    return _buildOptionsWithEmptyState();
  }

  Widget _buildOptionsWithEmptyState() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Opción: Elegir en el mapa
          _buildMapPickerOption(),

          // Ubicación predeterminada: UIDE Loja
          _buildUideShortcut(),

          const Divider(height: 1, indent: 20, endIndent: 20),

          // Búsquedas recientes
          if (_recentSearches.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Recientes',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ..._recentSearches.map((search) => _buildRecentSearchTile(search)),
          ] else ...[
            // Estado vacío si no hay recientes
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search,
                    size: 64,
                    color: AppColors.textSecondary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Busca tu destino',
                    style: AppTextStyles.h3.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Escribe una dirección, lugar o establecimiento',
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentSearchTile(Map<String, dynamic> search) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.tertiary,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.history,
          color: AppColors.textSecondary,
          size: 22,
        ),
      ),
      title: Text(
        search['mainText'] ?? '',
        style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        search['secondaryText'] ?? '',
        style: AppTextStyles.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _onRecentSearchSelected(search),
    );
  }

  void _onRecentSearchSelected(Map<String, dynamic> search) {
    // Verificar que el origen esté detectado
    if (_isLoadingLocation || _originLatitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Espera a que se detecte tu ubicación'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final destination = PlaceDetails(
      placeId: search['placeId'] ?? '',
      name: search['mainText'] ?? 'Destino',
      address: search['address'] ?? '',
      latitude: search['latitude'] as double,
      longitude: search['longitude'] as double,
    );

    _navigateToConfirmPickup(destination);
  }

  Widget _buildMapPickerOption() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.map_outlined,
          color: AppColors.primary,
          size: 24,
        ),
      ),
      title: Text(
        'Elegir en el mapa',
        style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        'Coloca un pin en tu destino',
        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: AppColors.textSecondary,
      ),
      onTap: _onChooseOnMap,
    );
  }

  void _onChooseOnMap() {
    // Verificar que el origen esté detectado
    if (_isLoadingLocation || _originLatitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Espera a que se detecte tu ubicación'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Navegar a la pantalla de selección en mapa
    context.push('/trip/pick-location', extra: {
      'userId': widget.userId,
      'userRole': widget.userRole,
      'originLatitude': _originLatitude ?? -3.9931,
      'originLongitude': _originLongitude ?? -79.2042,
      'originAddress': _originAddress ?? _originController.text,
    }).then((result) {
      if (result != null && result is Map<String, dynamic>) {
        // Recibir ubicación seleccionada y navegar al mapa de ruta
        final destination = PlaceDetails(
          placeId: 'map_selected_${DateTime.now().millisecondsSinceEpoch}',
          name: result['name'] ?? 'Destino seleccionado',
          address: result['address'] ?? '',
          latitude: result['latitude'] as double,
          longitude: result['longitude'] as double,
        );
        _navigateToConfirmPickup(destination);
      }
    });
  }

  Widget _buildUideShortcut() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.school,
          color: AppColors.primary,
          size: 24,
        ),
      ),
      title: Text(
        'UIDE Loja',
        style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        'Universidad Internacional del Ecuador - Loja',
        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: AppColors.textSecondary,
      ),
      onTap: _onUideSelected,
    );
  }

  void _onUideSelected() {
    // Verificar que el origen esté detectado
    if (_isLoadingLocation || _originLatitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Espera a que se detecte tu ubicación'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Coordenadas de la UIDE Loja (verificadas en mapa)
    final destination = PlaceDetails(
      placeId: 'uide_loja_predefined',
      name: 'UIDE Loja',
      address: 'Universidad Internacional del Ecuador, Agustín Carrión Palacios, Loja, Ecuador',
      latitude: -3.97245,
      longitude: -79.19933,
    );

    _navigateToConfirmPickup(destination);
  }

  Widget _buildSuggestionsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return _buildSuggestionTile(suggestion);
      },
    );
  }

  Widget _buildSuggestionTile(PlaceSuggestion suggestion) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.tertiary,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.location_on_outlined,
          color: AppColors.textSecondary,
          size: 22,
        ),
      ),
      title: Text(
        suggestion.mainText,
        style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        suggestion.secondaryText,
        style: AppTextStyles.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _onSuggestionSelected(suggestion),
    );
  }

}
