// lib/data/models/ride_request_model.dart
// Modelo de Solicitud de Viaje del Pasajero
// El pasajero publica su solicitud y los conductores deciden aceptar

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'trip_model.dart';

/// Estado de la solicitud de viaje
enum RideRequestStatus {
  searching,   // Buscando conductor
  reviewing,   // Un conductor está viendo la solicitud
  accepted,    // Conductor aceptó
  cancelled,   // Pasajero canceló
  expired,     // Expiró sin conductor
  completed,   // Viaje completado
}

/// Modelo de Solicitud de Viaje
///
/// Flujo:
/// 1. Pasajero crea solicitud → status: searching
/// 2. Conductor acepta → status: accepted, driverId y tripId asignados
/// 3. Viaje completo → status: completed
class RideRequestModel extends Equatable {
  final String requestId;
  final String passengerId;

  // Estado
  final String status; // 'searching', 'accepted', 'cancelled', 'expired', 'completed'

  // Ubicaciones
  final TripLocation origin;
  final TripLocation destination;
  final TripLocation pickupPoint;
  final String? referenceNote;

  // Preferencias del pasajero
  final List<String> preferences; // ['mochila', 'objeto_grande', 'mascota']
  final String? objectDescription;
  final String? petType;
  final String? petSize;
  final String? petDescription;

  // Pago
  final String paymentMethod; // 'Efectivo', 'Transferencia'
  final double? maxPrice; // Precio máximo que está dispuesto a pagar

  // Horario
  final DateTime requestedAt;
  final DateTime? departureTime; // Hora deseada de salida (null = ahora)
  final DateTime expiresAt; // Cuándo expira la solicitud

  // Conductor asignado (después de aceptar)
  final String? driverId;
  final String? tripId;
  final double? agreedPrice;
  final DateTime? acceptedAt;

  // Timestamps
  final DateTime createdAt;
  final DateTime? completedAt;

  const RideRequestModel({
    required this.requestId,
    required this.passengerId,
    required this.status,
    required this.origin,
    required this.destination,
    required this.pickupPoint,
    this.referenceNote,
    this.preferences = const ['mochila'],
    this.objectDescription,
    this.petType,
    this.petSize,
    this.petDescription,
    this.paymentMethod = 'Efectivo',
    this.maxPrice,
    required this.requestedAt,
    this.departureTime,
    required this.expiresAt,
    this.driverId,
    this.tripId,
    this.agreedPrice,
    this.acceptedAt,
    required this.createdAt,
    this.completedAt,
  });

  // === Getters ===

  /// Si la solicitud está activa (buscando conductor)
  bool get isSearching => status == 'searching';

  /// Si un conductor está revisando la solicitud
  bool get isReviewing => status == 'reviewing';

  /// Si ya fue aceptada
  bool get isAccepted => status == 'accepted';

  /// Si está cancelada o expirada
  bool get isCancelled => status == 'cancelled' || status == 'expired';

  /// Si ya expiró
  bool get isExpired {
    if (status == 'expired') return true;
    return DateTime.now().isAfter(expiresAt);
  }

  /// Tiempo restante antes de expirar (en minutos)
  int get minutesUntilExpiry {
    final diff = expiresAt.difference(DateTime.now());
    return diff.inMinutes;
  }

  /// Si es viaje inmediato (sin hora específica)
  bool get isImmediate => departureTime == null;

  /// Si lleva mascota
  bool get hasPet => preferences.contains('mascota') && petType != null;

  /// Si lleva objeto grande
  bool get hasLargeObject => preferences.contains('objeto_grande');

  /// Icono de mascota
  String get petIcon {
    switch (petType) {
      case 'perro':
        return '🐕';
      case 'gato':
        return '🐱';
      case 'otro':
        return '🐾';
      default:
        return '';
    }
  }

  /// Descripción corta de la ruta
  String get routeDescription => '${origin.name} → ${destination.name}';

  // === Serialización ===

  factory RideRequestModel.fromJson(Map<String, dynamic> json) {
    return RideRequestModel(
      requestId: json['requestId'] as String,
      passengerId: json['passengerId'] as String,
      status: json['status'] as String? ?? 'searching',
      origin: TripLocation.fromJson(json['origin'] as Map<String, dynamic>),
      destination: TripLocation.fromJson(json['destination'] as Map<String, dynamic>),
      pickupPoint: TripLocation.fromJson(json['pickupPoint'] as Map<String, dynamic>),
      referenceNote: json['referenceNote'] as String?,
      preferences: (json['preferences'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['mochila'],
      objectDescription: json['objectDescription'] as String?,
      petType: json['petType'] as String?,
      petSize: json['petSize'] as String?,
      petDescription: json['petDescription'] as String?,
      paymentMethod: json['paymentMethod'] as String? ?? 'Efectivo',
      maxPrice: (json['maxPrice'] as num?)?.toDouble(),
      requestedAt: json['requestedAt'] is Timestamp
          ? (json['requestedAt'] as Timestamp).toDate()
          : DateTime.parse(json['requestedAt'] as String),
      departureTime: json['departureTime'] != null
          ? (json['departureTime'] is Timestamp
              ? (json['departureTime'] as Timestamp).toDate()
              : DateTime.parse(json['departureTime'] as String))
          : null,
      expiresAt: json['expiresAt'] is Timestamp
          ? (json['expiresAt'] as Timestamp).toDate()
          : DateTime.parse(json['expiresAt'] as String),
      driverId: json['driverId'] as String?,
      tripId: json['tripId'] as String?,
      agreedPrice: (json['agreedPrice'] as num?)?.toDouble(),
      acceptedAt: json['acceptedAt'] != null
          ? (json['acceptedAt'] is Timestamp
              ? (json['acceptedAt'] as Timestamp).toDate()
              : DateTime.parse(json['acceptedAt'] as String))
          : null,
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null
          ? (json['completedAt'] is Timestamp
              ? (json['completedAt'] as Timestamp).toDate()
              : DateTime.parse(json['completedAt'] as String))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'passengerId': passengerId,
      'status': status,
      'origin': origin.toJson(),
      'destination': destination.toJson(),
      'pickupPoint': pickupPoint.toJson(),
      'referenceNote': referenceNote,
      'preferences': preferences,
      'objectDescription': objectDescription,
      'petType': petType,
      'petSize': petSize,
      'petDescription': petDescription,
      'paymentMethod': paymentMethod,
      'maxPrice': maxPrice,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'departureTime': departureTime != null
          ? Timestamp.fromDate(departureTime!)
          : null,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'driverId': driverId,
      'tripId': tripId,
      'agreedPrice': agreedPrice,
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'completedAt': completedAt != null
          ? Timestamp.fromDate(completedAt!)
          : null,
      // Campos para búsqueda geográfica
      'originLat': origin.latitude,
      'originLng': origin.longitude,
      'destLat': destination.latitude,
      'destLng': destination.longitude,
      'pickupLat': pickupPoint.latitude,
      'pickupLng': pickupPoint.longitude,
    };
  }

  factory RideRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RideRequestModel.fromJson({...data, 'requestId': doc.id});
  }

  RideRequestModel copyWith({
    String? requestId,
    String? passengerId,
    String? status,
    TripLocation? origin,
    TripLocation? destination,
    TripLocation? pickupPoint,
    String? referenceNote,
    List<String>? preferences,
    String? objectDescription,
    String? petType,
    String? petSize,
    String? petDescription,
    String? paymentMethod,
    double? maxPrice,
    DateTime? requestedAt,
    DateTime? departureTime,
    DateTime? expiresAt,
    String? driverId,
    String? tripId,
    double? agreedPrice,
    DateTime? acceptedAt,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return RideRequestModel(
      requestId: requestId ?? this.requestId,
      passengerId: passengerId ?? this.passengerId,
      status: status ?? this.status,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      pickupPoint: pickupPoint ?? this.pickupPoint,
      referenceNote: referenceNote ?? this.referenceNote,
      preferences: preferences ?? this.preferences,
      objectDescription: objectDescription ?? this.objectDescription,
      petType: petType ?? this.petType,
      petSize: petSize ?? this.petSize,
      petDescription: petDescription ?? this.petDescription,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      maxPrice: maxPrice ?? this.maxPrice,
      requestedAt: requestedAt ?? this.requestedAt,
      departureTime: departureTime ?? this.departureTime,
      expiresAt: expiresAt ?? this.expiresAt,
      driverId: driverId ?? this.driverId,
      tripId: tripId ?? this.tripId,
      agreedPrice: agreedPrice ?? this.agreedPrice,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  List<Object?> get props => [
        requestId,
        passengerId,
        status,
        origin,
        destination,
        pickupPoint,
        referenceNote,
        preferences,
        objectDescription,
        petType,
        petSize,
        petDescription,
        paymentMethod,
        maxPrice,
        requestedAt,
        departureTime,
        expiresAt,
        driverId,
        tripId,
        agreedPrice,
        acceptedAt,
        createdAt,
        completedAt,
      ];
}
