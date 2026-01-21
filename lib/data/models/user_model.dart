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
  final double rating;
  final int totalTrips;
  final String? profilePhotoUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

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
    this.rating = 5.0,
    this.totalTrips = 0,
    this.profilePhotoUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  // Nombre completo
  String get fullName => '$firstName $lastName';

  // Es conductor
  bool get isDriver => role == 'conductor' || role == 'ambos';

  // Es pasajero
  bool get isPassenger => role == 'pasajero' || role == 'ambos';

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
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalTrips: json['totalTrips'] as int? ?? 0,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
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
      'rating': rating,
      'totalTrips': totalTrips,
      'profilePhotoUrl': profilePhotoUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
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
    double? rating,
    int? totalTrips,
    String? profilePhotoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
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
      rating: rating ?? this.rating,
      totalTrips: totalTrips ?? this.totalTrips,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
        rating,
        totalTrips,
        profilePhotoUrl,
        createdAt,
        updatedAt,
      ];
}
