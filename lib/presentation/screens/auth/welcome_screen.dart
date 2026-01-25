import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../widgets/common/custom_button.dart';

/// Pantalla de bienvenida
/// Muestra carrusel auto-scrolling con 3 slides
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pageController = PageController();
  Timer? _autoScrollTimer;
  int _currentPage = 0;

  // Para "presiona atrás otra vez para salir"
  DateTime? _lastBackPressTime;

  // Duración del auto-scroll (10 segundos)
  static const Duration _autoScrollDuration = Duration(seconds: 10);

  // Contenido de los slides
  final List<_WelcomeSlide> _slides = const [
    _WelcomeSlide(
      icon: Icons.directions_car,
      title: 'Comparte tu viaje',
      description:
          'Conecta con otros estudiantes de UIDE y comparte viajes de forma segura y económica.',
    ),
    _WelcomeSlide(
      icon: Icons.attach_money,
      title: 'Ahorra dinero',
      description:
          'Divide los gastos de transporte y ahorra hasta 50% en tus viajes diarios a la universidad.',
    ),
    _WelcomeSlide(
      icon: Icons.eco,
      title: 'Cuida el ambiente',
      description:
          'Reduce tu huella de carbono compartiendo vehículos y contribuye a un planeta más verde.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  /// Iniciar auto-scroll cada 10 segundos
  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(_autoScrollDuration, (timer) {
      if (_currentPage < _slides.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  /// Manejar botón atrás - doble tap para salir
  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Presiona atrás otra vez para salir'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingL),
          child: Column(
            children: [
              // Logo pequeño en la esquina
              _buildTopBar(),
              const SizedBox(height: AppDimensions.spacingL),

              // Carrusel de slides
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    return _buildSlide(_slides[index]);
                  },
                ),
              ),

              // Indicadores de página
              _buildPageIndicators(),
              const SizedBox(height: AppDimensions.spacingXL),

              // Botones de acción
              _buildActionButtons(context),
              const SizedBox(height: AppDimensions.spacingL),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// Barra superior con logo
  Widget _buildTopBar() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.directions_car,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppStrings.appName,
          style: AppTextStyles.h3.copyWith(
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  /// Slide individual del carrusel
  Widget _buildSlide(_WelcomeSlide slide) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Icono grande
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            slide.icon,
            size: 60,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingXL),

        // Título
        Text(
          slide.title,
          style: AppTextStyles.h1.copyWith(
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDimensions.spacingM),

        // Descripción
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingL,
          ),
          child: Text(
            slide.description,
            style: AppTextStyles.body1.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Indicadores de página (puntos)
  Widget _buildPageIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _slides.length,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentPage == index ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: _currentPage == index
                ? AppColors.primary
                : AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  /// Botones de Iniciar Sesión y Registrarse
  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        // Botón primario: Iniciar Sesión
        CustomButton.primary(
          text: 'Iniciar Sesión',
          onPressed: () => context.push('/login'),
        ),
        const SizedBox(height: AppDimensions.spacingM),

        // Botón secundario: Registrarse
        CustomButton.secondary(
          text: 'Registrarse',
          onPressed: () => context.push('/register/step1'),
        ),
      ],
    );
  }
}

/// Modelo de datos para cada slide del carrusel
class _WelcomeSlide {
  final IconData icon;
  final String title;
  final String description;

  const _WelcomeSlide({
    required this.icon,
    required this.title,
    required this.description,
  });
}
