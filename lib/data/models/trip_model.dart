// lib/data/models/trip_model.dart
// Modelo de Viaje con serialización Firestore

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Modelo de ubicación para origen, destino y puntos de recogida
class TripLocation extends Equatable {
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  const TripLocation({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory TripLocation.fromJson(Map<String, dynamic> json) {
    return TripLocation(
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  TripLocation copyWith({
    String? name,
    String? address,
    double? latitude,
    double? longitude,
  }) {
    return TripLocation(
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  @override
  List<Object?> get props => [name, address, latitude, longitude];
}

/// Modelo de pasajero dentro de un viaje
class TripPassenger extends Equatable {
  final String userId;
  final String status; // 'pending', 'accepted', 'rejected', 'picked_up', 'dropped_off'
  final TripLocation? pickupPoint;
  final double price; // Precio final congelado al hacer drop-off (price = meterFare)
  final String paymentStatus; // 'pending', 'paid'
  final String paymentMethod; // 'Efectivo', 'Transferencia'
  final List<String> preferences; // ['mochila', 'objeto_grande', 'mascota']
  final String? referenceNote; // "Casa blanca con reja azul..."
  final String? objectDescription; // Descripción del objeto grande
  final String? petType; // 'perro', 'gato', 'otro'
  final String? petSize; // 'grande', 'mediano', 'pequeño' (solo para perros)
  final String? petDescription; // Descripción de la mascota (para 'otro')
  final String? rejectionReason;
  final DateTime requestedAt;

  // === Campos del taxímetro ===
  final DateTime? pickedUpAt; // Momento que subió al carro
  final double? pickupLatitude; // GPS lat al momento del pickup
  final double? pickupLongitude; // GPS lng al momento del pickup
  final DateTime? droppedOffAt; // Momento que se bajó
  final double? dropoffLatitude; // GPS lat al bajar
  final double? dropoffLongitude; // GPS lng al bajar
  final double? meterDistanceKm; // Km acumulados por GPS
  final double? meterWaitMinutes; // Minutos de espera (velocidad < 5 km/h)
  final double? meterFare; // Tarifa actual del taxímetro (fuente de verdad)
  final bool? isNightTariff; // Tarifa fijada al pickup (no cambia durante viaje)
  final DateTime? meterLastUpdated; // Última sincronización a Firestore

  const TripPassenger({
    required this.userId,
    required this.status,
    this.pickupPoint,
    required this.price,
    this.paymentStatus = 'pending',
    this.paymentMethod = 'Efectivo',
    this.preferences = const ['mochila'],
    this.referenceNote,
    this.objectDescription,
    this.petType,
    this.petSize,
    this.petDescription,
    this.rejectionReason,
    required this.requestedAt,
    // Taxímetro
    this.pickedUpAt,
    this.pickupLatitude,
    this.pickupLongitude,
    this.droppedOffAt,
    this.dropoffLatitude,
    this.dropoffLongitude,
    this.meterDistanceKm,
    this.meterWaitMinutes,
    this.meterFare,
    this.isNightTariff,
    this.meterLastUpdated,
  });

  /// Si el pasajero lleva mascota
  bool get hasPet => preferences.contains('mascota') && petType != null;

  /// Icono de mascota según el tipo
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

  /// Descripción completa de la mascota
  String get petFullDescription {
    if (petType == null) return '';
    if (petType == 'perro' && petSize != null) {
      return 'Perro ($petSize)';
    }
    if (petType == 'gato') {
      return 'Gato';
    }
    if (petType == 'otro' && petDescription != null) {
      return petDescription!;
    }
    return petType ?? '';
  }

  factory TripPassenger.fromJson(Map<String, dynamic> json) {
    return TripPassenger(
      userId: json['userId'] as String,
      status: json['status'] as String? ?? 'pending',
      pickupPoint: json['pickupPoint'] != null
          ? TripLocation.fromJson(json['pickupPoint'] as Map<String, dynamic>)
          : null,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      paymentStatus: json['paymentStatus'] as String? ?? 'pending',
      paymentMethod: json['paymentMethod'] as String? ?? 'Efectivo',
      preferences: (json['preferences'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['mochila'],
      referenceNote: json['referenceNote'] as String?,
      objectDescription: json['objectDescription'] as String?,
      petType: json['petType'] as String?,
      petSize: json['petSize'] as String?,
      petDescription: json['petDescription'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
      requestedAt: json['requestedAt'] is Timestamp
          ? (json['requestedAt'] as Timestamp).toDate()
          : DateTime.parse(json['requestedAt'] as String),
      // Taxímetro
      pickedUpAt: json['pickedUpAt'] != null
          ? (json['pickedUpAt'] is Timestamp
              ? (json['pickedUpAt'] as Timestamp).toDate()
              : DateTime.parse(json['pickedUpAt'] as String))
          : null,
      pickupLatitude: (json['pickupLatitude'] as num?)?.toDouble(),
      pickupLongitude: (json['pickupLongitude'] as num?)?.toDouble(),
      droppedOffAt: json['droppedOffAt'] != null
          ? (json['droppedOffAt'] is Timestamp
              ? (json['droppedOffAt'] as Timestamp).toDate()
              : DateTime.parse(json['droppedOffAt'] as String))
          : null,
      dropoffLatitude: (json['dropoffLatitude'] as num?)?.toDouble(),
      dropoffLongitude: (json['dropoffLongitude'] as num?)?.toDouble(),
      meterDistanceKm: (json['meterDistanceKm'] as num?)?.toDouble(),
      meterWaitMinutes: (json['meterWaitMinutes'] as num?)?.toDouble(),
      meterFare: (json['meterFare'] as num?)?.toDouble(),
      isNightTariff: json['isNightTariff'] as bool?,
      meterLastUpdated: json['meterLastUpdated'] != null
          ? (json['meterLastUpdated'] is Timestamp
              ? (json['meterLastUpdated'] as Timestamp).toDate()
              : DateTime.parse(json['meterLastUpdated'] as String))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'status': status,
      'pickupPoint': pickupPoint?.toJson(),
      'price': price,
      'paymentStatus': paymentStatus,
      'paymentMethod': paymentMethod,
      'preferences': preferences,
      'referenceNote': referenceNote,
      'objectDescription': objectDescription,
      'petType': petType,
      'petSize': petSize,
      'petDescription': petDescription,
      'rejectionReason': rejectionReason,
      'requestedAt': Timestamp.fromDate(requestedAt),
      // Taxímetro
      if (pickedUpAt != null) 'pickedUpAt': Timestamp.fromDate(pickedUpAt!),
      if (pickupLatitude != null) 'pickupLatitude': pickupLatitude,
      if (pickupLongitude != null) 'pickupLongitude': pickupLongitude,
      if (droppedOffAt != null) 'droppedOffAt': Timestamp.fromDate(droppedOffAt!),
      if (dropoffLatitude != null) 'dropoffLatitude': dropoffLatitude,
      if (dropoffLongitude != null) 'dropoffLongitude': dropoffLongitude,
      if (meterDistanceKm != null) 'meterDistanceKm': meterDistanceKm,
      if (meterWaitMinutes != null) 'meterWaitMinutes': meterWaitMinutes,
      if (meterFare != null) 'meterFare': meterFare,
      if (isNightTariff != null) 'isNightTariff': isNightTariff,
      if (meterLastUpdated != null) 'meterLastUpdated': Timestamp.fromDate(meterLastUpdated!),
    };
  }

  TripPassenger copyWith({
    String? userId,
    String? status,
    TripLocation? pickupPoint,
    double? price,
    String? paymentStatus,
    String? paymentMethod,
    List<String>? preferences,
    String? referenceNote,
    String? objectDescription,
    String? petType,
    String? petSize,
    String? petDescription,
    String? rejectionReason,
    DateTime? requestedAt,
    DateTime? pickedUpAt,
    double? pickupLatitude,
    double? pickupLongitude,
    DateTime? droppedOffAt,
    double? dropoffLatitude,
    double? dropoffLongitude,
    double? meterDistanceKm,
    double? meterWaitMinutes,
    double? meterFare,
    bool? isNightTariff,
    DateTime? meterLastUpdated,
  }) {
    return TripPassenger(
      userId: userId ?? this.userId,
      status: status ?? this.status,
      pickupPoint: pickupPoint ?? this.pickupPoint,
      price: price ?? this.price,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      preferences: preferences ?? this.preferences,
      referenceNote: referenceNote ?? this.referenceNote,
      objectDescription: objectDescription ?? this.objectDescription,
      petType: petType ?? this.petType,
      petSize: petSize ?? this.petSize,
      petDescription: petDescription ?? this.petDescription,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      requestedAt: requestedAt ?? this.requestedAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      pickupLatitude: pickupLatitude ?? this.pickupLatitude,
      pickupLongitude: pickupLongitude ?? this.pickupLongitude,
      droppedOffAt: droppedOffAt ?? this.droppedOffAt,
      dropoffLatitude: dropoffLatitude ?? this.dropoffLatitude,
      dropoffLongitude: dropoffLongitude ?? this.dropoffLongitude,
      meterDistanceKm: meterDistanceKm ?? this.meterDistanceKm,
      meterWaitMinutes: meterWaitMinutes ?? this.meterWaitMinutes,
      meterFare: meterFare ?? this.meterFare,
      isNightTariff: isNightTariff ?? this.isNightTariff,
      meterLastUpdated: meterLastUpdated ?? this.meterLastUpdated,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        status,
        pickupPoint,
        price,
        paymentStatus,
        paymentMethod,
        preferences,
        referenceNote,
        objectDescription,
        petType,
        petSize,
        petDescription,
        rejectionReason,
        requestedAt,
        pickedUpAt,
        pickupLatitude,
        pickupLongitude,
        droppedOffAt,
        dropoffLatitude,
        dropoffLongitude,
        meterDistanceKm,
        meterWaitMinutes,
        meterFare,
        isNightTariff,
        meterLastUpdated,
      ];
}

/// Modelo principal de Viaje
class TripModel extends Equatable {
  final String tripId;
  final String driverId;
  final String vehicleId;
  final String status; // 'scheduled', 'active', 'completed', 'cancelled'

  // Ruta
  final TripLocation origin;
  final TripLocation destination;
  final List<TripLocation> pickupPoints;
  final double? distanceKm;
  final int? durationMinutes;
  final String? encodedPolyline; // Polyline codificada de Google Directions

  // Horario
  final DateTime departureTime;
  final DateTime? estimatedArrival;
  final List<int>? recurringDays; // [1,2,3,4,5] = Lun-Vie (1=Lun, 7=Dom)

  // Precio
  final double pricePerPassenger; // USD - legacy (0.0 cuando usa taxímetro)
  final String currency;
  final bool useTaximeter; // true = taxímetro en tiempo real, false = precio fijo legacy

  // Capacidad
  final int totalCapacity; // 1-4
  final int availableSeats;

  // Pasajeros
  final List<TripPassenger> passengers;

  // Preferencias del conductor
  final bool allowsLuggage;
  final bool allowsPets;
  final String chatLevel; // 'silencioso', 'moderado', 'hablador'
  final int? maxWaitMinutes; // Tiempo de espera máximo en minutos
  final String? additionalNotes; // Notas adicionales (max 150 chars)
  final DateTime? waitingStartedAt; // Timestamp cuando el conductor inicia timer de espera

  // Ubicación en tiempo real del conductor (para tracking del pasajero)
  final double? driverLatitude;
  final double? driverLongitude;
  final DateTime? driverLocationUpdatedAt;

  // Timestamps
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const TripModel({
    required this.tripId,
    required this.driverId,
    required this.vehicleId,
    required this.status,
    required this.origin,
    required this.destination,
    this.pickupPoints = const [],
    this.distanceKm,
    this.durationMinutes,
    this.encodedPolyline,
    required this.departureTime,
    this.estimatedArrival,
    this.recurringDays,
    required this.pricePerPassenger,
    this.currency = 'USD',
    this.useTaximeter = true,
    required this.totalCapacity,
    required this.availableSeats,
    this.passengers = const [],
    this.allowsLuggage = true,
    this.allowsPets = false,
    this.chatLevel = 'flexible',
    this.maxWaitMinutes,
    this.additionalNotes,
    this.waitingStartedAt,
    this.driverLatitude,
    this.driverLongitude,
    this.driverLocationUpdatedAt,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  // === Getters ===

  /// Cantidad de pasajeros con solicitud pendiente
  int get pendingRequestsCount =>
      passengers.where((p) => p.status == 'pending').length;

  /// Cantidad de pasajeros aceptados
  int get acceptedPassengersCount =>
      passengers.where((p) => p.status == 'accepted' || p.status == 'picked_up')
          .length;

  /// Asientos reservados (aceptados + pendientes)
  int get reservedSeats => passengers
      .where((p) => p.status == 'accepted' || p.status == 'picked_up')
      .length;

  /// Si el viaje esta lleno
  bool get isFull => availableSeats <= 0;

  /// Si el viaje esta activo (buscando pasajeros)
  bool get isActive => status == 'active';

  /// Si el viaje está en progreso (conductor conduciendo)
  bool get isInProgress => status == 'in_progress';

  /// Si el viaje esta programado
  bool get isScheduled => status == 'scheduled';

  /// Si el viaje fue cancelado
  bool get isCancelled => status == 'cancelled';

  /// Si el viaje esta completado
  bool get isCompleted => status == 'completed';

  /// Si es viaje recurrente
  bool get isRecurring => recurringDays != null && recurringDays!.isNotEmpty;

  /// Si tiene ubicación reciente del conductor (menos de 30 segundos)
  bool get hasRecentDriverLocation {
    if (driverLatitude == null || driverLongitude == null) return false;
    if (driverLocationUpdatedAt == null) return false;
    return DateTime.now().difference(driverLocationUpdatedAt!).inSeconds < 30;
  }

  /// Descripcion corta de la ruta
  String get routeDescription => '${origin.name} → ${destination.name}';

  // === Serialización ===

  factory TripModel.fromJson(Map<String, dynamic> json) {
    return TripModel(
      tripId: json['tripId'] as String,
      driverId: json['driverId'] as String,
      vehicleId: json['vehicleId'] as String,
      status: json['status'] as String? ?? 'scheduled',
      origin: TripLocation.fromJson(json['origin'] as Map<String, dynamic>),
      destination:
          TripLocation.fromJson(json['destination'] as Map<String, dynamic>),
      pickupPoints: (json['pickupPoints'] as List<dynamic>?)
              ?.map(
                  (e) => TripLocation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      durationMinutes: json['durationMinutes'] as int?,
      encodedPolyline: json['encodedPolyline'] as String?,
      departureTime: json['departureTime'] is Timestamp
          ? (json['departureTime'] as Timestamp).toDate()
          : DateTime.parse(json['departureTime'] as String),
      estimatedArrival: json['estimatedArrival'] != null
          ? (json['estimatedArrival'] is Timestamp
              ? (json['estimatedArrival'] as Timestamp).toDate()
              : DateTime.parse(json['estimatedArrival'] as String))
          : null,
      recurringDays: (json['recurringDays'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
      pricePerPassenger:
          (json['pricePerPassenger'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      useTaximeter: json['useTaximeter'] as bool? ?? true,
      totalCapacity: json['totalCapacity'] as int? ?? 4,
      availableSeats: json['availableSeats'] as int? ?? 4,
      passengers: (json['passengers'] as List<dynamic>?)
              ?.map(
                  (e) => TripPassenger.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      allowsLuggage: json['allowsLuggage'] as bool? ?? true,
      allowsPets: json['allowsPets'] as bool? ?? false,
      chatLevel: json['chatLevel'] as String? ?? 'flexible',
      maxWaitMinutes: json['maxWaitMinutes'] as int?,
      additionalNotes: json['additionalNotes'] as String?,
      waitingStartedAt: json['waitingStartedAt'] != null
          ? (json['waitingStartedAt'] is Timestamp
              ? (json['waitingStartedAt'] as Timestamp).toDate()
              : DateTime.parse(json['waitingStartedAt'] as String))
          : null,
      driverLatitude: (json['driverLatitude'] as num?)?.toDouble(),
      driverLongitude: (json['driverLongitude'] as num?)?.toDouble(),
      driverLocationUpdatedAt: json['driverLocationUpdatedAt'] != null
          ? (json['driverLocationUpdatedAt'] is Timestamp
              ? (json['driverLocationUpdatedAt'] as Timestamp).toDate()
              : DateTime.parse(json['driverLocationUpdatedAt'] as String))
          : null,
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.parse(json['createdAt'] as String),
      startedAt: json['startedAt'] != null
          ? (json['startedAt'] is Timestamp
              ? (json['startedAt'] as Timestamp).toDate()
              : DateTime.parse(json['startedAt'] as String))
          : null,
      completedAt: json['completedAt'] != null
          ? (json['completedAt'] is Timestamp
              ? (json['completedAt'] as Timestamp).toDate()
              : DateTime.parse(json['completedAt'] as String))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tripId': tripId,
      'driverId': driverId,
      'vehicleId': vehicleId,
      'status': status,
      'origin': origin.toJson(),
      'destination': destination.toJson(),
      'pickupPoints': pickupPoints.map((p) => p.toJson()).toList(),
      'distanceKm': distanceKm,
      'durationMinutes': durationMinutes,
      'encodedPolyline': encodedPolyline,
      'departureTime': Timestamp.fromDate(departureTime),
      'estimatedArrival': estimatedArrival != null
          ? Timestamp.fromDate(estimatedArrival!)
          : null,
      'recurringDays': recurringDays,
      'pricePerPassenger': pricePerPassenger,
      'currency': currency,
      'useTaximeter': useTaximeter,
      'totalCapacity': totalCapacity,
      'availableSeats': availableSeats,
      'passengers': passengers.map((p) => p.toJson()).toList(),
      'allowsLuggage': allowsLuggage,
      'allowsPets': allowsPets,
      'chatLevel': chatLevel,
      'maxWaitMinutes': maxWaitMinutes,
      'additionalNotes': additionalNotes,
      'waitingStartedAt': waitingStartedAt != null
          ? Timestamp.fromDate(waitingStartedAt!)
          : null,
      'driverLatitude': driverLatitude,
      'driverLongitude': driverLongitude,
      'driverLocationUpdatedAt': driverLocationUpdatedAt != null
          ? Timestamp.fromDate(driverLocationUpdatedAt!)
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'startedAt':
          startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'completedAt':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    };
  }

  factory TripModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TripModel.fromJson({...data, 'tripId': doc.id});
  }

  TripModel copyWith({
    String? tripId,
    String? driverId,
    String? vehicleId,
    String? status,
    TripLocation? origin,
    TripLocation? destination,
    List<TripLocation>? pickupPoints,
    double? distanceKm,
    int? durationMinutes,
    String? encodedPolyline,
    DateTime? departureTime,
    DateTime? estimatedArrival,
    List<int>? recurringDays,
    double? pricePerPassenger,
    String? currency,
    bool? useTaximeter,
    int? totalCapacity,
    int? availableSeats,
    List<TripPassenger>? passengers,
    bool? allowsLuggage,
    bool? allowsPets,
    String? chatLevel,
    int? maxWaitMinutes,
    String? additionalNotes,
    DateTime? waitingStartedAt,
    double? driverLatitude,
    double? driverLongitude,
    DateTime? driverLocationUpdatedAt,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return TripModel(
      tripId: tripId ?? this.tripId,
      driverId: driverId ?? this.driverId,
      vehicleId: vehicleId ?? this.vehicleId,
      status: status ?? this.status,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      pickupPoints: pickupPoints ?? this.pickupPoints,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      encodedPolyline: encodedPolyline ?? this.encodedPolyline,
      departureTime: departureTime ?? this.departureTime,
      estimatedArrival: estimatedArrival ?? this.estimatedArrival,
      recurringDays: recurringDays ?? this.recurringDays,
      pricePerPassenger: pricePerPassenger ?? this.pricePerPassenger,
      currency: currency ?? this.currency,
      useTaximeter: useTaximeter ?? this.useTaximeter,
      totalCapacity: totalCapacity ?? this.totalCapacity,
      availableSeats: availableSeats ?? this.availableSeats,
      passengers: passengers ?? this.passengers,
      allowsLuggage: allowsLuggage ?? this.allowsLuggage,
      allowsPets: allowsPets ?? this.allowsPets,
      chatLevel: chatLevel ?? this.chatLevel,
      maxWaitMinutes: maxWaitMinutes ?? this.maxWaitMinutes,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      waitingStartedAt: waitingStartedAt ?? this.waitingStartedAt,
      driverLatitude: driverLatitude ?? this.driverLatitude,
      driverLongitude: driverLongitude ?? this.driverLongitude,
      driverLocationUpdatedAt: driverLocationUpdatedAt ?? this.driverLocationUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  List<Object?> get props => [
        tripId,
        driverId,
        vehicleId,
        status,
        origin,
        destination,
        pickupPoints,
        distanceKm,
        durationMinutes,
        encodedPolyline,
        departureTime,
        estimatedArrival,
        recurringDays,
        pricePerPassenger,
        currency,
        useTaximeter,
        totalCapacity,
        availableSeats,
        passengers,
        allowsLuggage,
        allowsPets,
        chatLevel,
        maxWaitMinutes,
        additionalNotes,
        waitingStartedAt,
        driverLatitude,
        driverLongitude,
        driverLocationUpdatedAt,
        createdAt,
        startedAt,
        completedAt,
      ];
}
