// lib/presentation/screens/trip/trip_preferences_screen.dart
// Pantalla "Detalles de Recogida" - Estilo Uber
// Permite configurar qué lleva el pasajero (mochila, objeto grande, mascota)
// Ahora con selección múltiple

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class TripPreferencesScreen extends StatefulWidget {
  final String userId;
  final String? currentPreference;
  final String? currentDescription;

  const TripPreferencesScreen({
    super.key,
    required this.userId,
    this.currentPreference,
    this.currentDescription,
  });

  @override
  State<TripPreferencesScreen> createState() => _TripPreferencesScreenState();
}

class _TripPreferencesScreenState extends State<TripPreferencesScreen> {
  // Selección múltiple de opciones
  bool _hasMochila = true; // Por defecto seleccionada
  bool _hasObjetoGrande = false;
  bool _hasMascota = false;

  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _petController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Parsear preferencias actuales si existen
    if (widget.currentPreference != null) {
      final prefs = widget.currentPreference!.split(',');
      _hasMochila = prefs.contains('mochila');
      _hasObjetoGrande = prefs.contains('objeto_grande');
      _hasMascota = prefs.contains('mascota');
    }
    _descriptionController.text = widget.currentDescription ?? '';
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _petController.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    // Al menos una opción debe estar seleccionada
    if (!_hasMochila && !_hasObjetoGrande && !_hasMascota) {
      return false;
    }
    // Si tiene objeto grande, necesita descripción
    if (_hasObjetoGrande && _descriptionController.text.trim().isEmpty) {
      return false;
    }
    // Si tiene mascota, necesita especificar cuál (OBLIGATORIO)
    if (_hasMascota && _petController.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  String get _selectedPreferencesString {
    List<String> prefs = [];
    if (_hasMochila) prefs.add('mochila');
    if (_hasObjetoGrande) prefs.add('objeto_grande');
    if (_hasMascota) prefs.add('mascota');
    return prefs.join(',');
  }

  void _onConfirm() {
    if (!_canConfirm) {
      String message = 'Por favor completa los campos requeridos';
      if (!_hasMochila && !_hasObjetoGrande && !_hasMascota) {
        message = 'Selecciona al menos una opción';
      } else if (_hasObjetoGrande && _descriptionController.text.trim().isEmpty) {
        message = 'Describe qué objeto grande vas a llevar';
      } else if (_hasMascota && _petController.text.trim().isEmpty) {
        message = 'Indica qué mascota llevas (obligatorio para el conductor)';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Retornar las preferencias seleccionadas
    context.pop({
      'preference': _selectedPreferencesString,
      'description': _descriptionController.text.trim(),
      'pet': _petController.text.trim(),
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
          'Detalles de Recogida',
          style: AppTextStyles.h3,
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ¿Qué vas a llevar? (selección múltiple)
            _buildPreferencesSection(),

            const SizedBox(height: 24),

            // Descripción (solo para objeto grande)
            if (_hasObjetoGrande) ...[
              _buildDescriptionField(),
              const SizedBox(height: 24),
            ],

            // Mascota (solo si seleccionó mascota - OBLIGATORIO)
            if (_hasMascota) ...[
              _buildPetField(),
              const SizedBox(height: 24),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomButton(),
    );
  }

  Widget _buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Qué vas a llevar?',
          style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),

        // Opción: Mochila (checkbox múltiple)
        _buildPreferenceOption(
          isSelected: _hasMochila,
          icon: Icons.backpack,
          label: 'Mochila',
          onTap: () => setState(() => _hasMochila = !_hasMochila),
        ),

        const SizedBox(height: 12),

        // Opción: Objeto grande
        _buildPreferenceOption(
          isSelected: _hasObjetoGrande,
          icon: Icons.inventory_2,
          label: 'Objeto grande',
          onTap: () => setState(() => _hasObjetoGrande = !_hasObjetoGrande),
        ),

        const SizedBox(height: 12),

        // Opción: Mascota
        _buildPreferenceOption(
          isSelected: _hasMascota,
          icon: Icons.pets,
          label: 'Mascota',
          onTap: () => setState(() => _hasMascota = !_hasMascota),
        ),
      ],
    );
  }

  Widget _buildPreferenceOption({
    required bool isSelected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.2)
                    : AppColors.tertiary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body1.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            // Checkbox en lugar de radio button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Describe qué vas a llevar',
              style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              'Obligatorio',
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          style: AppTextStyles.body2,
          maxLines: 3,
          maxLength: 100,
          decoration: InputDecoration(
            hintText: 'Ej: maqueta de arquitectura 80x60cm',
            hintStyle: AppTextStyles.body2.copyWith(
              color: AppColors.textTertiary,
            ),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 48),
              child: Icon(
                Icons.inventory_2,
                color: AppColors.textSecondary,
              ),
            ),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.border, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            counterText: '${_descriptionController.text.length}/100',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildPetField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '¿Qué mascota?',
              style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              'Obligatorio',
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _petController,
          style: AppTextStyles.body2,
          maxLength: 50,
          decoration: InputDecoration(
            hintText: 'Ej: Perro pequeño, gato',
            hintStyle: AppTextStyles.body2.copyWith(
              color: AppColors.textTertiary,
            ),
            prefixIcon: const Icon(
              Icons.pets,
              color: AppColors.textSecondary,
            ),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.border, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            counterText: '${_petController.text.length}/50',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(
          'Es importante que el conductor sepa qué mascota llevas por posibles alergias.',
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildBottomButton() {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
        top: 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _canConfirm ? _onConfirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.disabled,
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Confirmar y buscar viaje',
                style: AppTextStyles.button,
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
