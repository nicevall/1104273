// lib/data/models/user_model.dart
// Modelo de Usuario con serialización Firestore

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String userId;
  final String email;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String career;
  final int semester;
  final String role; // 'pasajero', 'conductor', 'ambos'
  final bool isVerified;
  final bool hasVehicle; // true si tiene vehículo registrado
  final double rating;
  final int totalTrips;
  final int tripsAsDriver;
  final int tripsAsPassenger;
  final String? profilePhotoUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int paymentStrikes;       // 0, 1, 2, 3 — strikes por falta de pago
  final DateTime? bannedUntil;    // Fecha hasta la que está suspendido
  final bool accountBlocked;      // true = bloqueado permanente (3 strikes)
  final String? fcmToken;         // Token FCM para notificaciones push

  const UserModel({
    required this.userId,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.career,
    required this.semester,
    required this.role,
    required this.isVerified,
    this.hasVehicle = false,
    this.rating = 5.0,
    this.totalTrips = 0,
    this.tripsAsDriver = 0,
    this.tripsAsPassenger = 0,
    this.profilePhotoUrl,
    required this.createdAt,
    required this.updatedAt,
    this.paymentStrikes = 0,
    this.bannedUntil,
    this.accountBlocked = false,
    this.fcmToken,
  });

  // Nombre completo
  String get fullName => '$firstName $lastName';

  // Es conductor
  bool get isDriver => role == 'conductor' || role == 'ambos';

  // Es pasajero
  bool get isPassenger => role == 'pasajero' || role == 'ambos';

  // Necesita registrar vehículo (es conductor/ambos pero no tiene vehículo)
  bool get needsVehicleRegistration => isDriver && !hasVehicle;

  // Crear desde JSON (Firestore)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['userId'] as String,
      email: json['email'] as String,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      phoneNumber: json['phoneNumber'] as String,
      career: json['career'] as String,
      semester: json['semester'] as int,
      role: json['role'] as String,
      isVerified: json['isVerified'] as bool? ?? false,
      hasVehicle: json['hasVehicle'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalTrips: json['totalTrips'] as int? ?? 0,
      tripsAsDriver: json['tripsAsDriver'] as int? ?? 0,
      tripsAsPassenger: json['tripsAsPassenger'] as int? ?? 0,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      paymentStrikes: json['paymentStrikes'] as int? ?? 0,
      bannedUntil: json['bannedUntil'] != null
          ? (json['bannedUntil'] as Timestamp).toDate()
          : null,
      accountBlocked: json['accountBlocked'] as bool? ?? false,
      fcmToken: json['fcmToken'] as String?,
    );
  }

  // Convertir a JSON (Firestore)
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'career': career,
      'semester': semester,
      'role': role,
      'isVerified': isVerified,
      'hasVehicle': hasVehicle,
      'rating': rating,
      'totalTrips': totalTrips,
      'tripsAsDriver': tripsAsDriver,
      'tripsAsPassenger': tripsAsPassenger,
      'profilePhotoUrl': profilePhotoUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'paymentStrikes': paymentStrikes,
      'bannedUntil': bannedUntil != null ? Timestamp.fromDate(bannedUntil!) : null,
      'accountBlocked': accountBlocked,
      'fcmToken': fcmToken,
    };
  }

  // Crear desde DocumentSnapshot
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel.fromJson(data);
  }

  // CopyWith
  UserModel copyWith({
    String? userId,
    String? email,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? career,
    int? semester,
    String? role,
    bool? isVerified,
    bool? hasVehicle,
    double? rating,
    int? totalTrips,
    int? tripsAsDriver,
    int? tripsAsPassenger,
    String? profilePhotoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? paymentStrikes,
    DateTime? bannedUntil,
    bool? accountBlocked,
    String? fcmToken,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      career: career ?? this.career,
      semester: semester ?? this.semester,
      role: role ?? this.role,
      isVerified: isVerified ?? this.isVerified,
      hasVehicle: hasVehicle ?? this.hasVehicle,
      rating: rating ?? this.rating,
      totalTrips: totalTrips ?? this.totalTrips,
      tripsAsDriver: tripsAsDriver ?? this.tripsAsDriver,
      tripsAsPassenger: tripsAsPassenger ?? this.tripsAsPassenger,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      paymentStrikes: paymentStrikes ?? this.paymentStrikes,
      bannedUntil: bannedUntil ?? this.bannedUntil,
      accountBlocked: accountBlocked ?? this.accountBlocked,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        email,
        firstName,
        lastName,
        phoneNumber,
        career,
        semester,
        role,
        isVerified,
        hasVehicle,
        rating,
        totalTrips,
        tripsAsDriver,
        tripsAsPassenger,
        profilePhotoUrl,
        createdAt,
        updatedAt,
        paymentStrikes,
        bannedUntil,
        accountBlocked,
        fcmToken,
      ];
}
