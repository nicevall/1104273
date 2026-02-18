// lib/presentation/screens/profile/profile_screen.dart
// Pantalla de Perfil del usuario
// Contextual al rol activo: conductor muestra vehículo, pasajero no
// Permite cambiar foto de perfil desde galería

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/firebase_storage_service.dart';
import '../../../data/services/permission_handler_service.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/driver/vehicle_info_card.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String activeRole; // 'pasajero' o 'conductor'

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.activeRole,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  VehicleModel? _vehicle;
  bool _isLoadingVehicle = true;
  bool _isUploadingPhoto = false;

  // Datos del usuario cargados directamente de Firestore
  String _userName = 'Usuario';
  String _userEmail = 'correo@uide.edu.ec';
  double _userRating = 5.0;
  int _totalTrips = 0;
  int _tripsAsDriver = 0;
  int _tripsAsPassenger = 0;
  String _userRole = 'pasajero';
  String? _profilePhotoUrl;
  String _career = '';
  int _semester = 0;
  String _phoneNumber = '';
  DateTime? _createdAt;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadVehicle();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await FirestoreService().getUser(widget.userId);
      if (user != null && mounted) {
        setState(() {
          _userName = user.fullName;
          _userEmail = user.email;
          _userRating = user.rating;
          _totalTrips = user.totalTrips;
          _tripsAsDriver = user.tripsAsDriver;
          _tripsAsPassenger = user.tripsAsPassenger;
          _userRole = user.role;
          _profilePhotoUrl = user.profilePhotoUrl;
          _career = user.career;
          _semester = user.semester;
          _phoneNumber = user.phoneNumber;
          _createdAt = user.createdAt;
          _isLoadingUser = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingUser = false);
      }
    } catch (e) {
      debugPrint('Error cargando datos de usuario: $e');
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  Future<void> _loadVehicle() async {
    if (widget.activeRole != 'conductor') {
      setState(() => _isLoadingVehicle = false);
      return;
    }
    try {
      final vehicle = await FirestoreService().getUserVehicle(widget.userId);
      if (mounted) {
        setState(() {
          _vehicle = vehicle;
          _isLoadingVehicle = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingVehicle = false);
      }
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    // Solicitar permiso de galería con diálogo educativo
    final permissionService = PermissionHandlerService();
    final hasPermission = await permissionService.requestGalleryWithDialog(context);

    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se necesita permiso de galería para cambiar tu foto'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final file = File(pickedFile.path);
      final storageService = FirebaseStorageService();
      final downloadUrl = await storageService.uploadProfilePhoto(
        userId: widget.userId,
        imageFile: file,
      );

      // Actualizar profilePhotoUrl en Firestore
      // Nota: profilePhotoUrl es único por usuario — aplica para ambos roles
      // (pasajero y conductor comparten la misma foto de perfil)
      await FirestoreService().updateUserFields(widget.userId, {
        'profilePhotoUrl': downloadUrl,
      });

      // Refrescar datos locales y AuthBloc
      if (mounted) {
        setState(() => _profilePhotoUrl = downloadUrl);
        context.read<AuthBloc>().add(const UpdateUserEvent());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto de perfil actualizada'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar foto: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) {
          context.go('/welcome');
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: Text('Perfil', style: AppTextStyles.h2),
          centerTitle: false,
        ),
        body: _isLoadingUser
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),

                    // Header: Avatar + Nombre + Email + Rating + Badge
                    _buildProfileHeader(
                      userName: _userName,
                      userEmail: _userEmail,
                      userRating: _userRating,
                      totalTrips: _totalTrips,
                      tripsAsDriver: _tripsAsDriver,
                      tripsAsPassenger: _tripsAsPassenger,
                      userRole: _userRole,
                      profilePhotoUrl: _profilePhotoUrl,
                    ),

                    const SizedBox(height: 28),

                    // Info personal
                    _buildInfoSection(
                      career: _career,
                      semester: _semester,
                      phoneNumber: _phoneNumber,
                      createdAt: _createdAt,
                    ),

                    // Vehículo (solo conductor)
                    if (widget.activeRole == 'conductor') ...[
                      const SizedBox(height: 20),
                      _buildVehicleSection(),
                    ],

                    const SizedBox(height: 28),

                    // Quick links
                    _buildQuickLinks(context),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }

  // ============================================================
  // HEADER: Avatar + Nombre + Rating + Badge
  // ============================================================

  Widget _buildProfileHeader({
    required String userName,
    required String userEmail,
    required double userRating,
    required int totalTrips,
    required int tripsAsDriver,
    required int tripsAsPassenger,
    required String userRole,
    String? profilePhotoUrl,
  }) {
    return Center(
      child: Column(
        children: [
          // Avatar tappable con overlay de cámara
          GestureDetector(
            onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
            child: Stack(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.tertiary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary,
                      width: 3,
                    ),
                    image: profilePhotoUrl != null
                        ? DecorationImage(
                            image: NetworkImage(profilePhotoUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _isUploadingPhoto
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2.5,
                          ),
                        )
                      : profilePhotoUrl == null
                          ? const Icon(
                              Icons.person,
                              size: 50,
                              color: AppColors.textSecondary,
                            )
                          : null,
                ),

                // Icono de cámara
                if (!_isUploadingPhoto)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Nombre
          Text(userName, style: AppTextStyles.h2),
          const SizedBox(height: 4),

          // Email
          Text(
            userEmail,
            style: AppTextStyles.body2.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),

          // Rating + viajes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star, size: 20, color: AppColors.warning),
              const SizedBox(width: 4),
              Text(
                userRating.toStringAsFixed(1),
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Viajes por rol
          if (userRole == 'ambos') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTripCountChip(
                  icon: Icons.directions_car,
                  count: tripsAsDriver,
                  label: 'como conductor',
                ),
                const SizedBox(width: 12),
                _buildTripCountChip(
                  icon: Icons.directions_walk,
                  count: tripsAsPassenger,
                  label: 'como pasajero',
                ),
              ],
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.activeRole == 'conductor'
                      ? Icons.directions_car
                      : Icons.directions_walk,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '$totalTrips viajes',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),

          // Badge del rol activo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.activeRole == 'conductor'
                      ? Icons.directions_car
                      : Icons.directions_walk,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.activeRole == 'conductor' ? 'Conductor' : 'Pasajero',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCountChip({
    required IconData icon,
    required int count,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            '$count $label',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INFO PERSONAL
  // ============================================================

  Widget _buildInfoSection({
    required String career,
    required int semester,
    required String phoneNumber,
    DateTime? createdAt,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Información',
              style: AppTextStyles.body1.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),

            // Carrera + Semestre
            _buildInfoRow(
              icon: Icons.school_outlined,
              label: career.isNotEmpty ? career : 'Sin carrera',
              value: semester > 0 ? 'Semestre $semester' : '',
            ),

            const Divider(height: 20, color: AppColors.divider),

            // Teléfono
            _buildInfoRow(
              icon: Icons.phone_outlined,
              label: 'Teléfono',
              value: phoneNumber.isNotEmpty ? phoneNumber : 'Sin registrar',
            ),

            const Divider(height: 20, color: AppColors.divider),

            // Miembro desde
            _buildInfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Miembro desde',
              value: createdAt != null
                  ? DateFormat('MMMM yyyy', 'es').format(createdAt)
                  : 'N/A',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: value.isNotEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                )
              : Text(
                  label,
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ],
    );
  }

  // ============================================================
  // VEHÍCULO (solo conductor)
  // ============================================================

  Widget _buildVehicleSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mi vehículo',
            style: AppTextStyles.body1.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),

          if (_isLoadingVehicle)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_vehicle != null)
            VehicleInfoCard(vehicle: _vehicle!)
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.tertiary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.directions_car_outlined,
                    size: 36,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sin vehículo registrado',
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // QUICK LINKS
  // ============================================================

  Widget _buildQuickLinks(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Historial de viajes
          _buildOptionTile(
            icon: Icons.history,
            title: 'Historial de viajes',
            iconColor: AppColors.textSecondary,
            titleColor: AppColors.textPrimary,
            onTap: () {
              context.push('/historial', extra: {
                'userId': widget.userId,
                'activeRole': widget.activeRole,
              });
            },
          ),

          const Divider(height: 1, color: AppColors.divider),

          // Cerrar sesión
          _buildOptionTile(
            icon: Icons.logout,
            title: 'Cerrar sesión',
            iconColor: AppColors.error,
            titleColor: AppColors.error,
            onTap: () => _showLogoutDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required Color iconColor,
    required Color titleColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      title: Text(
        title,
        style: AppTextStyles.body1.copyWith(color: titleColor),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: titleColor.withOpacity(0.5),
      ),
      onTap: onTap,
    );
  }

  // ============================================================
  // DIÁLOGO CERRAR SESIÓN
  // ============================================================

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Cerrar sesión?', style: AppTextStyles.h3),
        content: Text(
          '¿Estás seguro de que deseas cerrar sesión?',
          style: AppTextStyles.body2,
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
                  onPressed: () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Cancelar',
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    context.read<AuthBloc>().add(const LogoutEvent());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Cerrar sesión',
                    style: AppTextStyles.button.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
