// lib/presentation/screens/trip/rate_driver_screen.dart
// Pantalla de calificación del conductor por parte del pasajero
// Se muestra después de completar un viaje o cuando el conductor cancela

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/rating_service.dart';

class RateDriverScreen extends StatefulWidget {
  final String tripId;
  final String passengerId;
  final String driverId;
  final String ratingContext; // 'completed' o 'cancelled'
  final double? fare;

  const RateDriverScreen({
    super.key,
    required this.tripId,
    required this.passengerId,
    required this.driverId,
    required this.ratingContext,
    this.fare,
  });

  @override
  State<RateDriverScreen> createState() => _RateDriverScreenState();
}

class _RateDriverScreenState extends State<RateDriverScreen> {
  final _firestoreService = FirestoreService();
  final _ratingService = RatingService();
  final _commentController = TextEditingController();

  UserModel? _driverUser;
  VehicleModel? _driverVehicle;

  int _selectedRating = 5; // Por defecto 5 estrellas
  final Set<String> _selectedTags = {};
  bool _isSubmitting = false;

  // Emojis para cada rating
  static const List<String> _emojis = ['😡', '😟', '😐', '😊', '😁'];

  // Tags dinámicos según rating
  static const Map<int, List<String>> _tagsByRating = {
    5: [
      'Excelente servicio',
      'Conducción excepcional',
      'Puntualidad perfecta',
      'Vehículo impecable',
      'Muy amable',
    ],
    4: [
      'Tiempo de espera corto',
      'Conducción suave',
      'Servicio amable',
      'Vehículo muy limpio',
    ],
    3: [
      'Tiempo de espera aceptable',
      'Conducción normal',
      'Servicio estándar',
      'Vehículo limpio',
    ],
    2: [
      'Tiempo de espera largo',
      'Conducción brusca',
      'Servicio poco amable',
      'Vehículo desordenado',
      'No llegó a tiempo',
    ],
    1: [
      'Lento',
      'Conducción peligrosa',
      'Mal servicio',
      'Conductor cancela',
      'Vehículo sucio',
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadDriverData() async {
    try {
      final user = await _firestoreService.getUser(widget.driverId);
      final vehicle = await _firestoreService.getUserVehicle(widget.driverId);
      if (mounted) {
        setState(() {
          _driverUser = user;
          _driverVehicle = vehicle;
        });
      }
    } catch (e) {
      debugPrint('Error cargando datos del conductor: $e');
    }
  }

  Future<void> _submitRating() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      await _ratingService.submitRating(
        tripId: widget.tripId,
        raterId: widget.passengerId,
        ratedUserId: widget.driverId,
        raterRole: 'pasajero',
        stars: _selectedRating,
        tags: _selectedTags.toList(),
        comment: _commentController.text.trim().isNotEmpty
            ? _commentController.text.trim()
            : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Gracias por tu calificación!'),
            backgroundColor: AppColors.success,
          ),
        );
        // Limpiar ride_request y verificar si hay más reseñas pendientes
        await _cleanupAndNavigate();
      }
    } catch (e) {
      debugPrint('Error al enviar calificación: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al enviar calificación'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _skipRating() async {
    // Registrar en Firestore que se omitió la calificación
    // para que hasRated() retorne true y no quede pendiente para siempre
    await _ratingService.submitSkippedRating(
      tripId: widget.tripId,
      raterId: widget.passengerId,
      ratedUserId: widget.driverId,
      raterRole: 'pasajero',
    );
    _cleanupAndNavigate();
  }

  /// Limpiar ride_request del pasajero y navegar a siguiente reseña pendiente o home
  Future<void> _cleanupAndNavigate() async {
    try {
      // Limpiar ride_requests activas de este pasajero
      final firestore = FirebaseFirestore.instance;
      final activeReqs = await firestore
          .collection('ride_requests')
          .where('passengerId', isEqualTo: widget.passengerId)
          .where('status', whereIn: ['searching', 'reviewing', 'accepted'])
          .get();

      for (final doc in activeReqs.docs) {
        await doc.reference.update({
          'status': 'completed',
          'completedAt': Timestamp.now(),
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error limpiando ride_request: $e');
    }

    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            'Califica al conductor',
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // === Sección del conductor ===
              _buildDriverSection(),

              const SizedBox(height: 8),

              // === Vehículo ===
              _buildVehicleSection(),

              const SizedBox(height: 28),

              // === Emojis de calificación ===
              _buildEmojiRow(),

              const SizedBox(height: 24),

              // === Tags dinámicos ===
              _buildTagsSection(),

              const SizedBox(height: 24),

              // === Comentario ===
              _buildCommentField(),

              const SizedBox(height: 24),

              // === Botón calificar ===
              _buildSubmitButton(),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SECCIÓN DEL CONDUCTOR
  // ============================================================

  Widget _buildDriverSection() {
    return Row(
      children: [
        // Avatar
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.tertiary,
            border: Border.all(color: AppColors.divider, width: 2),
          ),
          child: ClipOval(
            child: _driverUser?.profilePhotoUrl != null
                ? CachedNetworkImage(
                    imageUrl: _driverUser!.profilePhotoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _buildDriverPlaceholder(),
                    errorWidget: (_, __, ___) => _buildDriverPlaceholder(),
                  )
                : _buildDriverPlaceholder(),
          ),
        ),
        const SizedBox(width: 14),

        // Nombre + rating
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _driverUser != null
                    ? '${_driverUser!.firstName} ${_driverUser!.lastName}'
                    : 'Conductor',
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),

        // Rating actual
        if (_driverUser != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _driverUser!.rating.toStringAsFixed(2),
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.star, size: 14, color: AppColors.warning),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDriverPlaceholder() {
    final initials = _driverUser != null
        ? '${_driverUser!.firstName.isNotEmpty ? _driverUser!.firstName[0] : ''}${_driverUser!.lastName.isNotEmpty ? _driverUser!.lastName[0] : ''}'
        : '?';
    return Container(
      color: AppColors.primary.withOpacity(0.1),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: AppTextStyles.body1.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SECCIÓN DEL VEHÍCULO
  // ============================================================

  Widget _buildVehicleSection() {
    if (_driverVehicle == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Foto del vehículo
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _driverVehicle!.photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _driverVehicle!.photoUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.directions_car,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : const Icon(
                      Icons.directions_car,
                      color: AppColors.textSecondary,
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_driverVehicle!.plate} - ${_driverVehicle!.year}',
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_driverVehicle!.brand} ${_driverVehicle!.model}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Badge verificado
          if (_driverVehicle!.isVerified)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.verified_user,
                size: 22,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // EMOJIS DE CALIFICACIÓN
  // ============================================================

  Widget _buildEmojiRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final rating = index + 1;
        final isSelected = _selectedRating == rating;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedRating = rating;
              _selectedTags.clear(); // Limpiar tags al cambiar rating
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedScale(
              scale: isSelected ? 1.3 : 0.9,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: isSelected ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _emojis[index],
                  style: TextStyle(
                    fontSize: isSelected ? 48 : 36,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ============================================================
  // TAGS DINÁMICOS
  // ============================================================

  Widget _buildTagsSection() {
    final tags = _tagsByRating[_selectedRating] ?? [];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Wrap(
        key: ValueKey(_selectedRating),
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: tags.map((tag) {
          final isSelected = _selectedTags.contains(tag);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedTags.remove(tag);
                } else {
                  _selectedTags.add(tag);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.12)
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                tag,
                style: AppTextStyles.caption.copyWith(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ============================================================
  // COMENTARIO
  // ============================================================

  Widget _buildCommentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Coméntanos tu experiencia',
          style: AppTextStyles.body2.copyWith(
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _commentController,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: 'Escribir comentario',
            hintStyle: AppTextStyles.body2.copyWith(
              color: AppColors.textTertiary,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.all(14),
            counterText: '',
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BOTÓN SUBMIT
  // ============================================================

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitRating,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Calificar y terminar',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
