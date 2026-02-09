// lib/presentation/screens/trip/searching_drivers_screen.dart
// Pantalla de búsqueda de conductores disponibles
// Accesibilidad AA - Interacción Hombre Computadora

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/trip_model.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../blocs/trip/trip_event.dart';
import '../../blocs/trip/trip_state.dart';

class SearchingDriversScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final Map<String, dynamic> origin;
  final Map<String, dynamic> destination;
  final Map<String, dynamic> pickupLocation;
  final String preference;
  final String preferenceDescription;
  final String paymentMethod;

  const SearchingDriversScreen({
    super.key,
    required this.userId,
    required this.userRole,
    required this.origin,
    required this.destination,
    required this.pickupLocation,
    required this.preference,
    required this.preferenceDescription,
    required this.paymentMethod,
  });

  @override
  State<SearchingDriversScreen> createState() => _SearchingDriversScreenState();
}

class _SearchingDriversScreenState extends State<SearchingDriversScreen>
    with TickerProviderStateMixin {
  // Constantes de tiempo
  static const int _searchDurationSeconds = 180; // 3 minutos

  // Controladores de animación
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Timer y estado
  Timer? _searchTimer;
  int _remainingSeconds = _searchDurationSeconds;
  bool _searchCompleted = false;
  bool _driversFound = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startSearch();
  }

  void _initAnimations() {
    // Rotación continua del arco (3 segundos por vuelta)
    _rotationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    // Pulso del icono central
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startSearch() {
    // === DEBUG: Imprimir todos los datos de la solicitud de viaje ===
    // Obtener datos del usuario desde AuthBloc
    String userName = 'No disponible';
    String userPhone = 'No disponible';
    String userEmail = 'No disponible';
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      userName = authState.user.fullName;
      userPhone = authState.user.phoneNumber;
      userEmail = authState.user.email;
    }

    debugPrint('╔══════════════════════════════════════════════════════════╗');
    debugPrint('║          SOLICITUD DE VIAJE - DATOS COMPLETOS          ║');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║ PASAJERO:');
    debugPrint('║   nombre: $userName');
    debugPrint('║   email: $userEmail');
    debugPrint('║   teléfono: $userPhone');
    debugPrint('║   userId: ${widget.userId}');
    debugPrint('║   userRole: ${widget.userRole}');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║ ORIGEN:');
    debugPrint('║   name: ${widget.origin['name']}');
    debugPrint('║   address: ${widget.origin['address']}');
    debugPrint('║   latitude: ${widget.origin['latitude']}');
    debugPrint('║   longitude: ${widget.origin['longitude']}');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║ DESTINO:');
    debugPrint('║   name: ${widget.destination['name']}');
    debugPrint('║   address: ${widget.destination['address']}');
    debugPrint('║   latitude: ${widget.destination['latitude']}');
    debugPrint('║   longitude: ${widget.destination['longitude']}');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║ PUNTO DE RECOGIDA:');
    debugPrint('║   address: ${widget.pickupLocation['address']}');
    debugPrint('║   latitude: ${widget.pickupLocation['latitude']}');
    debugPrint('║   longitude: ${widget.pickupLocation['longitude']}');
    debugPrint('║   reference: ${widget.pickupLocation['reference']}');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║ PREFERENCIAS:');
    debugPrint('║   preference: ${widget.preference}');
    debugPrint('║   description: ${widget.preferenceDescription}');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║ MÉTODO DE PAGO: ${widget.paymentMethod}');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║ TIMESTAMP: ${DateTime.now().toIso8601String()}');
    debugPrint('╚══════════════════════════════════════════════════════════╝');
    // === FIN DEBUG ===

    _searchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _onSearchTimeout();
      }
    });

    // Buscar viajes reales en Firestore
    _searchTripsInFirestore();
  }

  void _searchTripsInFirestore() {
    final originLat = widget.origin['latitude'] as double?;
    final originLng = widget.origin['longitude'] as double?;
    final destLat = widget.destination['latitude'] as double?;
    final destLng = widget.destination['longitude'] as double?;

    if (originLat != null && originLng != null &&
        destLat != null && destLng != null) {
      context.read<TripBloc>().add(SearchTripsEvent(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        departureDate: DateTime.now(),
        radiusKm: 5.0,
      ));
    }
  }

  void _onTripsFound(List<TripModel> trips) {
    _searchTimer?.cancel();
    if (trips.isNotEmpty) {
      // Navegar a resultados con los viajes encontrados
      final pickupPoint = widget.pickupLocation['latitude'] != null
          ? TripLocation(
              name: widget.pickupLocation['address'] as String? ?? '',
              address: widget.pickupLocation['address'] as String? ?? '',
              latitude: widget.pickupLocation['latitude'] as double,
              longitude: widget.pickupLocation['longitude'] as double,
            )
          : null;

      context.pushReplacement('/trip/results', extra: {
        'trips': trips,
        'userId': widget.userId,
        'pickupPoint': pickupPoint,
        'referenceNote': widget.pickupLocation['reference'] as String?,
        'preferences': [widget.preference],
        'preferenceDescription': widget.preferenceDescription,
      });
    } else {
      setState(() {
        _searchCompleted = true;
        _driversFound = false;
      });
    }
  }

  void _onSearchTimeout() {
    _searchTimer?.cancel();
    setState(() {
      _searchCompleted = true;
      _driversFound = false;
    });
  }

  void _cancelSearch() {
    _searchTimer?.cancel();
    context.go('/home', extra: {
      'userId': widget.userId,
      'userRole': widget.userRole,
      'hasVehicle': false,
    });
  }

  void _retrySearch() {
    setState(() {
      _searchCompleted = false;
      _driversFound = false;
      _remainingSeconds = _searchDurationSeconds;
    });
    _startSearch();
  }

  Future<bool> _onWillPop() async {
    if (_searchCompleted) {
      return true;
    }

    // Vibración háptica para feedback
    HapticFeedback.mediumImpact();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildBackConfirmationDialog(),
    );

    if (result == 'cancel') {
      _cancelSearch();
      return false;
    } else if (result == 'retry') {
      _retrySearch();
      return false;
    }

    return false;
  }

  Widget _buildBackConfirmationDialog() {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(
        '¿Qué deseas hacer?',
        style: AppTextStyles.h3,
        textAlign: TextAlign.center,
      ),
      content: Text(
        'Estamos buscando conductores disponibles cerca de ti.',
        style: AppTextStyles.body2.copyWith(
          color: AppColors.textSecondary,
        ),
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Botón principal: Volver a solicitar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, 'retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Volver a solicitar',
                  style: AppTextStyles.button,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Botón secundario: Cancelar solicitud (destructivo → rojo)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Cancelar solicitud',
                  style: AppTextStyles.button.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _onWillPop();
        }
      },
      child: BlocListener<TripBloc, TripState>(
        listener: (context, state) {
          if (state is TripsSearchResults) {
            _onTripsFound(state.trips);
          } else if (state is TripError) {
            // Si hay error en la búsqueda, continuar con el timer
            debugPrint('🔍 Error en búsqueda de viajes: ${state.error}');
          }
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: _searchCompleted && !_driversFound
                ? _buildNoDriversFoundView()
                : _buildSearchingView(),
          ),
        ),
      ),
    );
  }

  /// Formatear segundos a MM:SS
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildSearchingView() {
    return Column(
      children: [
        const Spacer(flex: 2),
        // Animación de búsqueda
        _buildSearchAnimation(),
        const SizedBox(height: 32),
        // Temporizador
        _buildTimer(),
        const SizedBox(height: 24),
        // Texto principal
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              Text(
                'Buscando conductores\ndisponibles cerca de ti...',
                style: AppTextStyles.h2.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Esto puede tomar unos momentos',
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const Spacer(flex: 2),
        // Información del viaje
        _buildTripInfoCard(),
        const SizedBox(height: 16),
        // Botón cancelar
        _buildCancelButton(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTimer() {
    // Calcular el progreso (de 1.0 a 0.0)
    final progress = _remainingSeconds / _searchDurationSeconds;

    return Column(
      children: [
        // Tiempo restante grande
        Text(
          _formatTime(_remainingSeconds),
          style: AppTextStyles.h1.copyWith(
            fontSize: 48,
            fontWeight: FontWeight.w300,
            color: AppColors.primary,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        // Barra de progreso
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 60),
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.tertiary,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCancelButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () async {
            HapticFeedback.mediumImpact();
            final result = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (context) => _buildBackConfirmationDialog(),
            );
            if (result == 'cancel') {
              _cancelSearch();
            } else if (result == 'retry') {
              _retrySearch();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Text(
            'Cancelar búsqueda',
            style: AppTextStyles.button.copyWith(
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAnimation() {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Círculo de fondo con gradiente suave
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withOpacity(0.08),
                  AppColors.primary.withOpacity(0.02),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Arco rotatorio
          AnimatedBuilder(
            animation: _rotationController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationController.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(170, 170),
                  painter: _ArcPainter(
                    color: AppColors.primary,
                    strokeWidth: 4,
                    sweepAngle: 0.7, // 70% del círculo
                  ),
                ),
              );
            },
          ),
          // Círculo interior
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.background,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          // Icono del auto con pulso
          ScaleTransition(
            scale: _pulseAnimation,
            child: Icon(
              Icons.directions_car_rounded,
              size: 48,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripInfoCard() {
    final pickupAddress = widget.pickupLocation['address'] as String? ?? 'Punto de recogida';
    final destinationName = widget.destination['name'] as String? ?? 'Destino';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Punto de recogida
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recogida',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      pickupAddress,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
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
            margin: const EdgeInsets.only(left: 5),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 20,
                  color: AppColors.divider,
                ),
              ],
            ),
          ),
          // Destino
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF6CCC91),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6CCC91).withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Destino',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      destinationName,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
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

  Widget _buildNoDriversFoundView() {
    return Column(
      children: [
        const Spacer(flex: 2),
        // Icono de no encontrado
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.tertiary,
          ),
          child: Icon(
            Icons.search_off_rounded,
            size: 56,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 32),
        // Mensaje
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              Text(
                'No se encontraron\nconductores disponibles',
                style: AppTextStyles.h2.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'No hay conductores disponibles en este momento para tu ruta. Intenta de nuevo más tarde.',
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const Spacer(flex: 2),
        // Botones de acción
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              // Volver a solicitar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _retrySearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Volver a solicitar',
                    style: AppTextStyles.button,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Cancelar solicitud (destructivo → rojo)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _cancelSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Cancelar solicitud',
                    style: AppTextStyles.button.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

/// Painter para dibujar el arco de carga
class _ArcPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double sweepAngle;

  _ArcPainter({
    required this.color,
    required this.strokeWidth,
    required this.sweepAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Dibujar arco (sweepAngle en radianes)
    canvas.drawArc(
      rect,
      -math.pi / 2, // Empezar desde arriba
      sweepAngle * 2 * math.pi, // Convertir a radianes
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.sweepAngle != sweepAngle;
  }
}
