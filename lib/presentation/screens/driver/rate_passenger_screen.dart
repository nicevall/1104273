// lib/presentation/screens/driver/rate_passenger_screen.dart
// Pantalla de calificación del pasajero por parte del conductor
// Se muestra después de confirmar el pago del pasajero

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/rating_service.dart';

class RatePassengerScreen extends StatefulWidget {
  final String tripId;
  final String driverId; // Conductor que califica (raterId)
  final String passengerId; // Pasajero calificado (ratedUserId)
  final String passengerName;
  final double fare;

  const RatePassengerScreen({
    super.key,
    required this.tripId,
    required this.driverId,
    required this.passengerId,
    required this.passengerName,
    required this.fare,
  });

  @override
  State<RatePassengerScreen> createState() => _RatePassengerScreenState();
}

class _RatePassengerScreenState extends State<RatePassengerScreen> {
  final _firestoreService = FirestoreService();
  final _ratingService = RatingService();
  final _commentController = TextEditingController();

  UserModel? _passengerUser;

  int _selectedRating = 5;
  final Set<String> _selectedTags = {};
  bool _isSubmitting = false;

  // Emojis para cada rating
  static const List<String> _emojis = ['😡', '😟', '😐', '😊', '😁'];

  // Tags dinámicos según rating - perspectiva del conductor sobre el pasajero
  static const Map<int, List<String>> _tagsByRating = {
    5: [
      'Puntual',
      'Respetuoso',
      'Amable',
      'Limpio',
      'Excelente pasajero',
    ],
    4: [
      'Puntual',
      'Buena actitud',
      'Ordenado',
      'Cooperativo',
    ],
    3: [
      'Normal',
      'Aceptable',
      'Sin problemas',
    ],
    2: [
      'Impuntual',
      'Desordenado',
      'Poco cooperativo',
      'Mala actitud',
    ],
    1: [
      'No se presentó',
      'Irrespetuoso',
      'Daño al vehículo',
      'Peligroso',
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadPassengerData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadPassengerData() async {
    try {
      final user = await _firestoreService.getUser(widget.passengerId);
      if (mounted) {
        setState(() {
          _passengerUser = user;
        });
      }
    } catch (e) {
      debugPrint('Error cargando datos del pasajero: $e');
    }
  }

  Future<void> _submitRating() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      await _ratingService.submitRating(
        tripId: widget.tripId,
        raterId: widget.driverId,
        ratedUserId: widget.passengerId,
        raterRole: 'conductor',
        stars: _selectedRating,
        tags: _selectedTags.toList(),
        comment: _commentController.text.trim().isNotEmpty
            ? _commentController.text.trim()
            : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Calificación enviada!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context); // Volver al mapa del conductor
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

  void _skipRating() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _skipRating();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: _skipRating,
          ),
          title: Text(
            'Calificar pasajero',
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // === Sección del pasajero ===
              _buildPassengerSection(),

              const SizedBox(height: 8),

              // === Info tarifa ===
              _buildFareInfo(),

              const SizedBox(height: 28),

              // === Emojis de calificación ===
              _buildEmojiRow(),

              const SizedBox(height: 24),

              // === Tags dinámicos ===
              _buildTagsSection(),

              const SizedBox(height: 20),

              // === Omitir calificación ===
              GestureDetector(
                onTap: _skipRating,
                child: Text(
                  'Omitir calificación',
                  style: AppTextStyles.body2.copyWith(
                    decoration: TextDecoration.underline,
                    color: AppColors.primary,
                    decorationColor: AppColors.primary,
                  ),
                ),
              ),

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
  // SECCIÓN DEL PASAJERO
  // ============================================================

  Widget _buildPassengerSection() {
    final displayName = _passengerUser != null
        ? '${_passengerUser!.firstName} ${_passengerUser!.lastName}'
        : widget.passengerName;

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
            child: _passengerUser?.profilePhotoUrl != null
                ? CachedNetworkImage(
                    imageUrl: _passengerUser!.profilePhotoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _buildPlaceholder(),
                    errorWidget: (_, __, ___) => _buildPlaceholder(),
                  )
                : _buildPlaceholder(),
          ),
        ),
        const SizedBox(width: 14),

        // Nombre + rating
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),

        // Rating actual
        if (_passengerUser != null)
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
                  _passengerUser!.rating.toStringAsFixed(2),
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

  Widget _buildPlaceholder() {
    final initials = _passengerUser != null
        ? '${_passengerUser!.firstName.isNotEmpty ? _passengerUser!.firstName[0] : ''}${_passengerUser!.lastName.isNotEmpty ? _passengerUser!.lastName[0] : ''}'
        : widget.passengerName.isNotEmpty
            ? widget.passengerName[0]
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
  // INFO TARIFA
  // ============================================================

  Widget _buildFareInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.payments_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            'Tarifa: \$${widget.fare.toStringAsFixed(2)}',
            style: AppTextStyles.body2.copyWith(
              fontWeight: FontWeight.w600,
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
    return Column(
      children: [
        // Emoji grande
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _emojis[_selectedRating - 1],
            key: ValueKey(_selectedRating),
            style: const TextStyle(fontSize: 56),
          ),
        ),
        const SizedBox(height: 8),

        // Texto descriptivo
        Text(
          _getRatingText(),
          style: AppTextStyles.body1.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),

        // Estrellas
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final rating = index + 1;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedRating = rating;
                  _selectedTags.clear();
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  rating <= _selectedRating ? Icons.star : Icons.star_border,
                  size: 40,
                  color: rating <= _selectedRating
                      ? AppColors.warning
                      : AppColors.divider,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  String _getRatingText() {
    switch (_selectedRating) {
      case 5:
        return '¡Excelente pasajero!';
      case 4:
        return 'Buen pasajero';
      case 3:
        return 'Normal';
      case 2:
        return 'Podría mejorar';
      case 1:
        return 'Mala experiencia';
      default:
        return '';
    }
  }

  // ============================================================
  // TAGS DINÁMICOS
  // ============================================================

  Widget _buildTagsSection() {
    final tags = _tagsByRating[_selectedRating] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Qué destacas del pasajero?',
          style: AppTextStyles.body2.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
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
                      : AppColors.tertiary,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.divider,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  tag,
                  style: AppTextStyles.body2.copyWith(
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ============================================================
  // COMENTARIO OPCIONAL
  // ============================================================

  Widget _buildCommentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comentario adicional (opcional)',
          style: AppTextStyles.body2.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _commentController,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: 'Escribe un comentario sobre tu experiencia...',
            hintStyle: AppTextStyles.body2.copyWith(
              color: AppColors.textTertiary,
            ),
            filled: true,
            fillColor: AppColors.tertiary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BOTÓN ENVIAR
  // ============================================================

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitRating,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                'Enviar calificación',
                style: AppTextStyles.button.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
