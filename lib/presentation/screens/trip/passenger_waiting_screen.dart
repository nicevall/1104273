// lib/presentation/screens/trip/passenger_waiting_screen.dart
// Pantalla de espera mientras se busca conductor
// Muestra animación de búsqueda y permite cancelar

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/ride_request_model.dart';
import '../../../data/models/trip_model.dart';
import '../../../data/services/ride_requests_service.dart';

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
    with SingleTickerProviderStateMixin {
  final _requestsService = RideRequestsService();

  String? _requestId;
  RideRequestModel? _currentRequest;
  StreamSubscription<RideRequestModel?>? _requestSubscription;

  bool _isLoading = true;
  bool _isCancelling = false;
  String? _error;

  // Animación
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Timer para mostrar tiempo restante
  Timer? _expiryTimer;
  int _minutesRemaining = 30;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _createRequest();
  }

  void _initAnimation() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _requestSubscription?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _createRequest() async {
    try {
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
      _requestSubscription = _requestsService
          .getRequestStream(requestId)
          .listen(_onRequestUpdate);

      // Iniciar timer de expiración
      _startExpiryTimer();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _minutesRemaining = 30;
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
    if (request == null) return;

    setState(() {
      _currentRequest = request;
    });

    // Si fue aceptado, ir a pantalla de confirmación
    if (request.status == 'accepted') {
      _showAcceptedDialog(request);
    }

    // Si expiró, mostrar mensaje
    if (request.status == 'expired') {
      _showExpiredDialog();
    }
  }

  void _startExpiryTimer() {
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted && _currentRequest != null) {
        final remaining = _currentRequest!.minutesUntilExpiry;
        setState(() {
          _minutesRemaining = remaining > 0 ? remaining : 0;
        });

        if (remaining <= 0) {
          timer.cancel();
        }
      }
    });
  }

  void _showAcceptedDialog(RideRequestModel request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '¡Conductor encontrado!',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Un conductor ha aceptado llevarte.\nPrecio acordado: \$${request.agreedPrice?.toStringAsFixed(2) ?? "0.00"}',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // Ir a pantalla de viaje activo
                // TODO: Navegar a pantalla de seguimiento del viaje
                context.go('/home');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Ver detalles del viaje'),
            ),
          ),
        ],
      ),
    );
  }

  void _showExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.timer_off,
                color: AppColors.warning,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Búsqueda expirada',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'No se encontró conductor disponible.\nPuedes intentar de nuevo.',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/home');
            },
            child: const Text('Ir al inicio'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Reiniciar búsqueda
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _createRequest();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Buscar de nuevo'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelRequest() async {
    if (_requestId == null) {
      context.pop();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar búsqueda?'),
        content: const Text(
          'Tu solicitud será cancelada y tendrás que buscar de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Sí, cancelar'),
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _cancelRequest();
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: _isLoading
              ? _buildLoadingState()
              : _error != null
                  ? _buildErrorState()
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
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _createRequest();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingState() {
    return Column(
      children: [
        // Header con botón cancelar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _isCancelling ? null : _cancelRequest,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_minutesRemaining min',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Contenido principal
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animación de búsqueda
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Círculos concéntricos
                        ...List.generate(3, (index) {
                          return Container(
                            width: 140 - (index * 30).toDouble(),
                            height: 140 - (index * 30).toDouble(),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary
                                    .withOpacity(0.3 - (index * 0.1)),
                                width: 2,
                              ),
                            ),
                          );
                        }),
                        const Icon(
                          Icons.search,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                Text(
                  'Buscando conductor...',
                  style: AppTextStyles.h2,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                Text(
                  'Tu solicitud está visible para conductores\nque van hacia tu destino.',
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // Card con resumen de la solicitud
                _buildRequestSummary(),
              ],
            ),
          ),
        ),

        // Botón cancelar
        Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isCancelling ? null : _cancelRequest,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCancelling
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppColors.error),
                      ),
                    )
                  : const Text('Cancelar búsqueda'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Ruta
          Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 30,
                    color: AppColors.divider,
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.pickupPoint.name,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
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

          const SizedBox(height: 16),
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
        emoji = '🐕';
        label = widget.petSize ?? 'Perro';
        break;
      case 'gato':
        emoji = '🐱';
        label = 'Gato';
        break;
      default:
        emoji = '🐾';
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
