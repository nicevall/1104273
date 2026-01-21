// lib/data/models/vehicle_model.dart
// Modelo de Vehículo con serialización Firestore

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class VehicleModel extends Equatable {
  final String vehicleId;
  final String ownerId; // userId del propietario
  final String brand;
  final String model;
  final int year;
  final String color;
  final String plate;
  final int capacity; // 1-4 pasajeros
  final bool hasAirConditioning;
  final String photoUrl;
  final String licensePhotoUrl;
  final bool isVerified; // Verificado por admin
  final DateTime createdAt;

  const VehicleModel({
    required this.vehicleId,
    required this.ownerId,
    required this.brand,
    required this.model,
    required this.year,
    required this.color,
    required this.plate,
    required this.capacity,
    this.hasAirConditioning = false,
    required this.photoUrl,
    required this.licensePhotoUrl,
    this.isVerified = false,
    required this.createdAt,
  });

  // Descripción completa del vehículo
  String get fullDescription => '$brand $model $year - $color';

  // Crear desde JSON (Firestore)
  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      vehicleId: json['vehicleId'] as String,
      ownerId: json['ownerId'] as String,
      brand: json['brand'] as String,
      model: json['model'] as String,
      year: json['year'] as int,
      color: json['color'] as String,
      plate: json['plate'] as String,
      capacity: json['capacity'] as int,
      hasAirConditioning: json['hasAirConditioning'] as bool? ?? false,
      photoUrl: json['photoUrl'] as String,
      licensePhotoUrl: json['licensePhotoUrl'] as String,
      isVerified: json['isVerified'] as bool? ?? false,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
    );
  }

  // Convertir a JSON (Firestore)
  Map<String, dynamic> toJson() {
    return {
      'vehicleId': vehicleId,
      'ownerId': ownerId,
      'brand': brand,
      'model': model,
      'year': year,
      'color': color,
      'plate': plate,
      'capacity': capacity,
      'hasAirConditioning': hasAirConditioning,
      'photoUrl': photoUrl,
      'licensePhotoUrl': licensePhotoUrl,
      'isVerified': isVerified,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  // Crear desde DocumentSnapshot
  factory VehicleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VehicleModel.fromJson({...data, 'vehicleId': doc.id});
  }

  // CopyWith
  VehicleModel copyWith({
    String? vehicleId,
    String? ownerId,
    String? brand,
    String? model,
    int? year,
    String? color,
    String? plate,
    int? capacity,
    bool? hasAirConditioning,
    String? photoUrl,
    String? licensePhotoUrl,
    bool? isVerified,
    DateTime? createdAt,
  }) {
    return VehicleModel(
      vehicleId: vehicleId ?? this.vehicleId,
      ownerId: ownerId ?? this.ownerId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      year: year ?? this.year,
      color: color ?? this.color,
      plate: plate ?? this.plate,
      capacity: capacity ?? this.capacity,
      hasAirConditioning: hasAirConditioning ?? this.hasAirConditioning,
      photoUrl: photoUrl ?? this.photoUrl,
      licensePhotoUrl: licensePhotoUrl ?? this.licensePhotoUrl,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        vehicleId,
        ownerId,
        brand,
        model,
        year,
        color,
        plate,
        capacity,
        hasAirConditioning,
        photoUrl,
        licensePhotoUrl,
        isVerified,
        createdAt,
      ];
}
