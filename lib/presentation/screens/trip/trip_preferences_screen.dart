// lib/presentation/screens/trip/trip_preferences_screen.dart
// Pantalla "Detalles de Recogida" - Estilo Uber
// Permite configurar qué lleva el pasajero (mochila, objeto grande, mascota)
// Rediseñado: selector de mascota con perro(+tamaño)/gato/otro

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
  // Selección múltiple de opciones principales
  bool _hasMochila = true; // Por defecto seleccionada
  bool _hasObjetoGrande = false;
  bool _hasMascota = false;

  // Tipo de mascota
  String? _petType; // 'perro', 'gato', 'otro'
  String? _petSize; // 'grande', 'mediano', 'pequeño' (solo para perros)

  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _petDescriptionController = TextEditingController();

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
    _petDescriptionController.dispose();
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
    // Si tiene mascota, necesita tipo
    if (_hasMascota && _petType == null) {
      return false;
    }
    // Si es perro, necesita tamaño
    if (_hasMascota && _petType == 'perro' && _petSize == null) {
      return false;
    }
    // Si es "otro", necesita descripción
    if (_hasMascota && _petType == 'otro' && _petDescriptionController.text.trim().isEmpty) {
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
      } else if (_hasMascota && _petType == null) {
        message = 'Selecciona el tipo de mascota';
      } else if (_hasMascota && _petType == 'perro' && _petSize == null) {
        message = 'Selecciona el tamaño de tu perro';
      } else if (_hasMascota && _petType == 'otro' && _petDescriptionController.text.trim().isEmpty) {
        message = 'Describe qué mascota llevas';
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
      'petType': _petType,
      'petSize': _petSize,
      'petDescription': _petDescriptionController.text.trim(),
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
          'Detalles de Solicitud',
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

            // Selector de mascota (solo si seleccionó mascota)
            if (_hasMascota) ...[
              _buildPetTypeSelector(),
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
          onTap: () => setState(() {
            _hasMascota = !_hasMascota;
            if (!_hasMascota) {
              _petType = null;
              _petSize = null;
              _petDescriptionController.clear();
            }
          }),
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

  // Sugerencias predeterminadas para objeto grande
  static const List<String> _objetoGrandeSuggestions = [
    'Maqueta mediana',
    'Maqueta grande',
    'Prototipo',
    'Maleta grande',
    'Instrumento musical',
    'Cuadro / lienzo',
  ];

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

        // Burbujas de sugerencias predeterminadas
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _objetoGrandeSuggestions.map((suggestion) {
            final isSelected = _descriptionController.text.trim() == suggestion;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _descriptionController.text = suggestion;
                  _descriptionController.selection = TextSelection.fromPosition(
                    TextPosition(offset: suggestion.length),
                  );
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.15)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  suggestion,
                  style: AppTextStyles.caption.copyWith(
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        TextField(
          controller: _descriptionController,
          style: AppTextStyles.body2,
          maxLines: 3,
          maxLength: 100,
          decoration: InputDecoration(
            hintText: 'O escribe una descripción personalizada...',
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

  Widget _buildPetTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '¿Qué mascota llevas?',
              style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              'Obligatorio',
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Opciones de tipo de mascota en horizontal
        Row(
          children: [
            Expanded(
              child: _buildPetTypeCard(
                type: 'perro',
                emoji: '🐕',
                label: 'Perro',
                isSelected: _petType == 'perro',
                onTap: () => setState(() {
                  _petType = 'perro';
                  _petDescriptionController.clear();
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildPetTypeCard(
                type: 'gato',
                emoji: '🐱',
                label: 'Gato',
                isSelected: _petType == 'gato',
                onTap: () => setState(() {
                  _petType = 'gato';
                  _petSize = null;
                  _petDescriptionController.clear();
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildPetTypeCard(
                type: 'otro',
                emoji: '🐾',
                label: 'Otro',
                isSelected: _petType == 'otro',
                onTap: () => setState(() {
                  _petType = 'otro';
                  _petSize = null;
                }),
              ),
            ),
          ],
        ),

        // Selector de tamaño (solo para perros)
        if (_petType == 'perro') ...[
          const SizedBox(height: 20),
          _buildDogSizeSelector(),
        ],

        // Campo de descripción (solo para "otro")
        if (_petType == 'otro') ...[
          const SizedBox(height: 20),
          _buildOtherPetField(),
        ],

        const SizedBox(height: 12),
        Text(
          'Es importante que el conductor sepa qué mascota llevas por posibles alergias.',
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildPetTypeCard({
    required String type,
    required String emoji,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.body2.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDogSizeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿De qué tamaño es tu perro?',
          style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDogSizeOption(
                size: 'pequeño',
                label: 'Pequeño',
                description: '< 10 kg',
                isSelected: _petSize == 'pequeño',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDogSizeOption(
                size: 'mediano',
                label: 'Mediano',
                description: '10-25 kg',
                isSelected: _petSize == 'mediano',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDogSizeOption(
                size: 'grande',
                label: 'Grande',
                description: '> 25 kg',
                isSelected: _petSize == 'grande',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDogSizeOption({
    required String size,
    required String label,
    required String description,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _petSize = size),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.tertiary.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: AppTextStyles.body2.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: AppTextStyles.caption.copyWith(
                fontSize: 10,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Sugerencias predeterminadas para mascota "otro"
  static const List<String> _otherPetSuggestions = [
    'Conejo',
    'Cuy',
    'Tortuga',
    'Hámster',
    'Ave / pájaro',
    'Pez (pecera)',
  ];

  Widget _buildOtherPetField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Qué mascota es?',
          style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),

        // Burbujas de sugerencias
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _otherPetSuggestions.map((suggestion) {
            final isSelected = _petDescriptionController.text.trim() == suggestion;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _petDescriptionController.text = suggestion;
                  _petDescriptionController.selection = TextSelection.fromPosition(
                    TextPosition(offset: suggestion.length),
                  );
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.15)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  suggestion,
                  style: AppTextStyles.caption.copyWith(
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        TextField(
          controller: _petDescriptionController,
          style: AppTextStyles.body2,
          maxLength: 50,
          decoration: InputDecoration(
            hintText: 'O escribe qué mascota llevas...',
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
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            counterText: '${_petDescriptionController.text.length}/50',
          ),
          onChanged: (_) => setState(() {}),
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
