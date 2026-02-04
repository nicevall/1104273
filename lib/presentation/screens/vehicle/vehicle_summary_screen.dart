import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../blocs/registration/registration_bloc.dart';
import '../../blocs/registration/registration_event.dart';
import '../../blocs/registration/registration_state.dart';
import '../../widgets/common/custom_button.dart';

/// Pantalla de resumen de registro de vehículo
/// Muestra todos los datos extraídos en modo solo lectura
/// Permite al usuario confirmar y registrar el vehículo
class VehicleSummaryScreen extends StatelessWidget {
  final String userId;
  final String role;
  final String vehicleOwnership;
  final String driverRelation;
  final String matriculaPhotoPath;
  final String licensePhotoPath;
  final Map<String, dynamic>? licenseData;
  final Map<String, String> vehicleData;
  final String vehiclePhotoPath;

  const VehicleSummaryScreen({
    super.key,
    required this.userId,
    required this.role,
    required this.vehicleOwnership,
    required this.driverRelation,
    required this.matriculaPhotoPath,
    required this.licensePhotoPath,
    this.licenseData,
    required this.vehicleData,
    required this.vehiclePhotoPath,
  });

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RegistrationBloc, RegistrationState>(
      listener: (context, state) {
        if (state is RegistrationSuccess) {
          // Registro exitoso, navegar al home con datos del usuario
          context.go('/home', extra: {
            'userId': state.userId,
            'userRole': state.role,
            'hasVehicle': true,
          });
        } else if (state is RegistrationFailure) {
          // Mostrar mensaje de error
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al registrar: ${state.error}'),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => context.pop(),
            ),
            title: Text(
              'Resumen',
              style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppDimensions.paddingL),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProgressIndicator(4, 4),
                        const SizedBox(height: AppDimensions.spacingL),

                        Text('Confirma los datos', style: AppTextStyles.h1),
                        const SizedBox(height: AppDimensions.spacingS),
                        Text(
                          'Revisa que toda la información sea correcta',
                          style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: AppDimensions.spacingXL),

                        // Foto del vehículo
                        _buildVehiclePhotoSection(),
                        const SizedBox(height: AppDimensions.spacingL),

                        // Datos del vehículo
                        _buildSectionCard(
                          title: 'Datos del vehículo',
                          icon: Icons.directions_car,
                          children: [
                            if (vehicleData['placa'] != null)
                              _buildDataRow('Placa', vehicleData['placa']!),
                            if (vehicleData['marca'] != null)
                              _buildDataRow('Marca', vehicleData['marca']!),
                            if (vehicleData['modelo'] != null)
                              _buildDataRow('Modelo', vehicleData['modelo']!),
                            if (vehicleData['año'] != null)
                              _buildDataRow('Año', vehicleData['año']!),
                            if (vehicleData['color'] != null)
                              _buildDataRow('Color', vehicleData['color']!),
                            if (vehicleData.isEmpty)
                              Text(
                                'Datos pendientes de verificación manual',
                                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppDimensions.spacingM),

                        // Datos del conductor
                        _buildSectionCard(
                          title: 'Datos del conductor',
                          icon: Icons.person,
                          children: [
                            if (licenseData?['numero_licencia'] != null)
                              _buildDataRow('N° Licencia', licenseData!['numero_licencia']),
                            if (licenseData?['nombres'] != null && licenseData?['apellidos'] != null)
                              _buildDataRow('Titular', '${licenseData!['nombres']} ${licenseData!['apellidos']}'),
                            if (licenseData?['categoria'] != null)
                              _buildDataRow('Categoría', licenseData!['categoria']),
                            if (licenseData?['fecha_vencimiento'] != null)
                              _buildDataRow('Vencimiento', licenseData!['fecha_vencimiento']),
                            _buildDataRow(
                              'Propietario',
                              _getOwnershipLabel(vehicleOwnership),
                            ),
                            _buildDataRow(
                              'Conductor',
                              _getDriverLabel(driverRelation),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppDimensions.spacingM),

                        // Documentos verificados
                        _buildSectionCard(
                          title: 'Documentos verificados',
                          icon: Icons.verified,
                          children: [
                            _buildDocumentRow('Matrícula vehicular', true),
                            _buildDocumentRow('Licencia de conducir', true),
                            _buildDocumentRow('Foto del vehículo', true),
                          ],
                        ),
                        const SizedBox(height: AppDimensions.spacingL),

                        // Nota informativa
                        Container(
                          padding: const EdgeInsets.all(AppDimensions.paddingM),
                          decoration: BoxDecoration(
                            color: AppColors.info.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
                            border: Border.all(color: AppColors.info.withOpacity(0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline, color: AppColors.info, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Al registrar tu vehículo, confirmas que la información proporcionada es verídica y aceptas los términos de uso.',
                                  style: AppTextStyles.caption.copyWith(color: AppColors.info),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Botón de registro
                Padding(
                  padding: const EdgeInsets.all(AppDimensions.paddingL),
                  child: CustomButton.primary(
                    text: 'Registrar vehículo',
                    onPressed: state is RegistrationLoading
                        ? null
                        : () => _handleRegister(context),
                    isLoading: state is RegistrationLoading,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleRegister(BuildContext context) {
    context.read<RegistrationBloc>().add(
      RegisterVehicleEvent(
        userId: userId,
        vehiclePhoto: File(vehiclePhotoPath),
        registrationPhoto: File(matriculaPhotoPath),
        licensePhoto: File(licensePhotoPath),
        vehicleData: vehicleData,
        licenseData: licenseData,
        vehicleOwnership: vehicleOwnership,
        driverRelation: driverRelation,
      ),
    );
  }

  String _getOwnershipLabel(String ownership) {
    switch (ownership) {
      case 'mio':
        return 'Vehículo propio';
      case 'familiar':
        return 'De un familiar';
      case 'amigo':
        return 'De un amigo';
      default:
        return ownership;
    }
  }

  String _getDriverLabel(String driver) {
    switch (driver) {
      case 'yo':
        return 'El titular';
      case 'familiar':
        return 'Un familiar';
      case 'amigo':
        return 'Un amigo';
      default:
        return driver;
    }
  }

  Widget _buildProgressIndicator(int current, int total) {
    return Row(
      children: List.generate(total, (index) {
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index < total - 1 ? 8 : 0),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildVehiclePhotoSection() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius - 1),
        child: Image.file(
          File(vehiclePhotoPath),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.paddingM),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.label),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentRow(String document, bool isVerified) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            isVerified ? Icons.check_circle : Icons.cancel,
            color: isVerified ? AppColors.success : AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            document,
            style: AppTextStyles.body2,
          ),
        ],
      ),
    );
  }
}
