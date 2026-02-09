// lib/presentation/screens/trip/passenger_waiting_screen.dart
// Pantalla de espera mientras se busca conductor
// Muestra temporizador de 3 minutos con countdown visual y permite cancelar/reintentar

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/ride_request_model.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/services/ride_requests_service.dart';
import '../../../data/services/trips_service.dart';

class PassengerWaitingScreen extends StatefulWidget {
  final String userId;
  final TripLocation origin;
  final TripLocation destination;
  final TripLocation pickupPoint;
  final String? referenceNote;
  final List<String> preferences;
  final String? objectDescription;
  final String? petType;
  final String? petSize;
  final String? petDescription;
  final String paymentMethod;

  const PassengerWaitingScreen({
    super.key,
    required this.userId,
    required this.origin,
    required this.destination,
    required this.pickupPoint,
    this.referenceNote,
    this.preferences = const ['mochila'],
    this.objectDescription,
    this.petType,
    this.petSize,
    this.petDescription,
    this.paymentMethod = 'Efectivo',
  });

  @override
  State<PassengerWaitingScreen> createState() => _PassengerWaitingScreenState();
}

class _PassengerWaitingScreenState extends State<PassengerWaitingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _requestsService = RideRequestsService();
  final _tripsService = TripsService();

  // Constantes
  static const int _searchDurationSeconds = 180; // 3 minutos

  // Estado de la solicitud
  String? _requestId;
  RideRequestModel? _currentRequest;
  StreamSubscription<RideRequestModel?>? _requestSubscription;

  bool _isLoading = true;
  bool _isCancelling = false;
  bool _searchExpired = false;
  String? _error;

  // Estado de conductor encontrado
  bool _driverFound = false;
  String? _assignedTripId;
  StreamSubscription<TripModel?>? _tripSubscription;

  // Animaciones
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Timer countdown
  Timer? _countdownTimer;
  int _remainingSeconds = _searchDurationSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAnimations();
    _createRequest();
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _requestSubscription?.cancel();
    _tripSubscription?.cancel();
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Interceptar botón back nativo de Android
  @override
  Future<bool> didPopRoute() async {
    debugPrint('🔙 didPopRoute interceptado en PassengerWaitingScreen');
    if (_searchExpired) {
      context.go('/home');
    } else {
      _cancelRequest();
    }
    return true; // Consumir el evento, no cerrar la app
  }

  // ==================== Lógica de solicitud ====================

  Future<void> _createRequest() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _searchExpired = false;
        _remainingSeconds = _searchDurationSeconds;
      });

      // Crear modelo de solicitud
      final request = _requestsService.createRequestModel(
        passengerId: widget.userId,
        origin: widget.origin,
        destination: widget.destination,
        pickupPoint: widget.pickupPoint,
        referenceNote: widget.referenceNote,
        preferences: widget.preferences,
        objectDescription: widget.objectDescription,
        petType: widget.petType,
        petSize: widget.petSize,
        petDescription: widget.petDescription,
        paymentMethod: widget.paymentMethod,
      );

      // Guardar en Firebase
      final requestId = await _requestsService.createRequest(request);
      _requestId = requestId;

      // Escuchar cambios en tiempo real
      _requestSubscription?.cancel();
      _requestSubscription = _requestsService
          .getRequestStream(requestId)
          .listen(_onRequestUpdate);

      // Iniciar countdown
      _startCountdown();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _onRequestUpdate(RideRequestModel? request) {
    if (request == null || !mounted) return;

    setState(() {
      _currentRequest = request;
    });

    // Si fue aceptado → transicionar a estado "Conductor encontrado"
    if (request.status == 'accepted' && !_driverFound) {
      _countdownTimer?.cancel();
      setState(() {
        _driverFound = true;
        _assignedTripId = request.tripId;
      });

      // Suscribirse al trip para detectar cuando se inicie
      if (request.tripId != null) {
        _tripSubscription?.cancel();
        _tripSubscription = _tripsService
            .getTripStream(request.tripId!)
            .listen(_onTripUpdate);
      }
    }

    // Si expiró desde el servidor
    if (request.status == 'expired') {
      _countdownTimer?.cancel();
      setState(() {
        _searchExpired = true;
        _remainingSeconds = 0;
      });
    }
  }

  void _onTripUpdate(TripModel? trip) {
    if (trip == null || !mounted) return;

    // Cuando el conductor inicia el viaje (in_progress) → auto-navegar a tracking
    if (trip.status == 'in_progress') {
      _tripSubscription?.cancel();
      context.go('/trip/tracking', extra: {
        'tripId': trip.tripId,
        'userId': widget.userId,
        'pickupPoint': widget.pickupPoint,
        'destination': widget.destination,
      });
    }

    // Si el viaje fue cancelado
    if (trip.status == 'cancelled') {
      _tripSubscription?.cancel();
      if (mounted) {
        _showTripCancelledDialog();
      }
    }
  }

  void _showTripCancelledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Viaje cancelado'),
        content: const Text(
          'El conductor ha cancelado el viaje. Tu solicitud será cancelada.',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/home');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Entendido'),
            ),
          ),
        ],
      ),
    );
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        _onSearchExpired();
      }
    });
  }

  void _onSearchExpired() {
    if (!mounted) return;
    setState(() {
      _searchExpired = true;
    });
    // Cancelar la solicitud en Firebase
    if (_requestId != null) {
      _requestsService.cancelRequest(_requestId!).catchError((_) {});
    }
  }

  Future<void> _retrySearch() async {
    // Cancelar solicitud anterior si existe
    if (_requestId != null) {
      try {
        await _requestsService.cancelRequest(_requestId!);
      } catch (_) {}
    }
    _requestSubscription?.cancel();
    _requestId = null;
    _currentRequest = null;

    // Crear nueva solicitud
    _createRequest();
  }

  Future<void> _cancelRequest() async {
    if (_requestId == null) {
      context.go('/home');
      return;
    }

    // Vibración háptica
    HapticFeedback.mediumImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar búsqueda?'),
        content: const Text(
          'Tu solicitud será cancelada y tendrás que buscar de nuevo.',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('No'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Sí, cancelar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCancelling = true);

    try {
      await _requestsService.cancelRequest(_requestId!);
      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ==================== Utilidades ====================

  /// Formatear segundos a MM:SS
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// Color del timer — siempre turquesa
  Color get _timerColor => AppColors.primary;

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          if (_searchExpired) {
            context.go('/home');
          } else {
            _cancelRequest();
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: _isLoading
              ? _buildLoadingState()
              : _error != null
                  ? _buildErrorState()
                  : _driverFound
                      ? _buildDriverFoundState()
                      : _searchExpired
                          ? _buildExpiredState()
                          : _buildSearchingState(),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 20),
          Text('Publicando tu solicitud...'),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 20),
            Text(
              'Error al crear solicitud',
              style: AppTextStyles.h3,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Error desconocido',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _createRequest();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: const Text('Reintentar'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go('/home'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Ir al inicio'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Estado: Buscando ====================

  Widget _buildSearchingState() {
    return Column(
      children: [
        const Spacer(flex: 2),

        // Animación de búsqueda
        _buildSearchAnimation(),

        const SizedBox(height: 32),

        // Temporizador MM:SS
        _buildTimer(),

        const SizedBox(height: 24),

        // Texto principal
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              Text(
                'Buscando conductor...',
                style: AppTextStyles.h2.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Tu solicitud está visible para conductores\nque van hacia tu destino.',
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        const Spacer(flex: 2),

        // Card con resumen de la solicitud
        _buildTripInfoCard(),

        const SizedBox(height: 16),

        // Botón cancelar
        _buildCancelButton(),

        const SizedBox(height: 24),
      ],
    );
  }

  // ==================== Estado: Conductor encontrado ====================

  Widget _buildDriverFoundState() {
    return Column(
      children: [
        const Spacer(flex: 2),

        // Checkmark con pulso
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withOpacity(0.1),
            ),
            child: Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success.withOpacity(0.15),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 60,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),

        Text(
          '¡Conductor encontrado!',
          style: AppTextStyles.h2.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.success,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 12),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Espere un momento mientras el conductor\ninicia el viaje.',
            style: AppTextStyles.body2.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 24),

        // Indicador de carga
        SizedBox(
          width: 200,
          child: Column(
            children: [
              const LinearProgressIndicator(
                backgroundColor: Color(0xFFE0E0E0),
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.success),
              ),
              const SizedBox(height: 8),
              Text(
                'Esperando que inicie el viaje...',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        const Spacer(flex: 2),

        // Card con info del viaje
        _buildTripInfoCard(),

        const SizedBox(height: 16),

        // Botón cancelar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                _tripSubscription?.cancel();
                if (_requestId != null) {
                  try {
                    await _requestsService.cancelRequest(_requestId!);
                  } catch (_) {}
                }
                if (mounted) context.go('/home');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Cancelar viaje'),
            ),
          ),
        ),

        const SizedBox(height: 24),
      ],
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
                    color: _timerColor,
                    strokeWidth: 4,
                    sweepAngle: 0.7,
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
          // Icono de búsqueda con pulso
          ScaleTransition(
            scale: _pulseAnimation,
            child: Icon(
              Icons.search,
              size: 48,
              color: _timerColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimer() {
    final progress = _remainingSeconds / _searchDurationSeconds;

    return Column(
      children: [
        // Tiempo restante grande
        Text(
          _formatTime(_remainingSeconds),
          style: AppTextStyles.h1.copyWith(
            fontSize: 48,
            fontWeight: FontWeight.w300,
            color: _timerColor,
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
              valueColor: AlwaysStoppedAnimation<Color>(_timerColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTripInfoCard() {
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
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      widget.pickupPoint.name,
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
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withOpacity(0.3),
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
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      widget.destination.name,
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

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Iconos de preferencias
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPreferenceIcon(
                icon: widget.paymentMethod == 'Efectivo'
                    ? Icons.payments
                    : Icons.phone_android,
                label: widget.paymentMethod,
              ),
              if (widget.preferences.contains('objeto_grande')) ...[
                const SizedBox(width: 16),
                _buildPreferenceIcon(
                  icon: Icons.inventory_2,
                  label: 'Grande',
                ),
              ],
              if (widget.petType != null) ...[
                const SizedBox(width: 16),
                _buildPetIcon(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCancelButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isCancelling ? null : () async {
            HapticFeedback.mediumImpact();
            _cancelRequest();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.error.withOpacity(0.5),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: _isCancelling
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(
                  'Cancelar búsqueda',
                  style: AppTextStyles.button,
                ),
        ),
      ),
    );
  }

  // ==================== Estado: Expirado ====================

  Widget _buildExpiredState() {
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
                'No hay conductores disponibles en este momento para tu ruta. Intenta de nuevo.',
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
                    'Buscar de nuevo',
                    style: AppTextStyles.button,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Cancelar solicitud
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => context.go('/home'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: Text(
                    'Ir al inicio',
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.textSecondary,
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

  // ==================== Widgets de preferencias ====================

  Widget _buildPreferenceIcon({
    required IconData icon,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildPetIcon() {
    String emoji;
    String label;

    switch (widget.petType) {
      case 'perro':
        emoji = '\u{1F415}';
        label = widget.petSize ?? 'Perro';
        break;
      case 'gato':
        emoji = '\u{1F431}';
        label = 'Gato';
        break;
      default:
        emoji = '\u{1F43E}';
        label = 'Mascota';
    }

    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontSize: 10,
          ),
        ),
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

    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweepAngle * 2 * math.pi,
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
