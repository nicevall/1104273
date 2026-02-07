import 'package:equatable/equatable.dart';
import '../../../data/models/trip_model.dart';

/// Estados del TripBloc
/// Representa el estado actual de las operaciones de viaje
abstract class TripState extends Equatable {
  const TripState();

  @override
  List<Object?> get props => [];
}

/// Estado inicial
class TripInitial extends TripState {
  const TripInitial();
}

/// Cargando operación
class TripLoading extends TripState {
  const TripLoading();
}

/// Viaje creado exitosamente
class TripCreated extends TripState {
  final TripModel trip;

  const TripCreated({required this.trip});

  @override
  List<Object?> get props => [trip];
}

/// Viajes del conductor cargados
class DriverTripsLoaded extends TripState {
  final List<TripModel> trips;

  const DriverTripsLoaded({required this.trips});

  /// Viajes programados (próximos)
  List<TripModel> get scheduledTrips =>
      trips.where((t) => t.isScheduled).toList();

  /// Viajes activos
  List<TripModel> get activeTrips =>
      trips.where((t) => t.isActive).toList();

  /// Viajes completados
  List<TripModel> get completedTrips =>
      trips.where((t) => t.isCompleted).toList();

  /// Total de solicitudes pendientes en todos los viajes
  int get totalPendingRequests =>
      trips.fold(0, (sum, trip) => sum + trip.pendingRequestsCount);

  @override
  List<Object?> get props => [trips];
}

/// Detalle de un viaje cargado
class TripDetailLoaded extends TripState {
  final TripModel trip;

  const TripDetailLoaded({required this.trip});

  @override
  List<Object?> get props => [trip];
}

/// Resultados de búsqueda de viajes (pasajero)
class TripsSearchResults extends TripState {
  final List<TripModel> trips;

  const TripsSearchResults({required this.trips});

  @override
  List<Object?> get props => [trips];
}

/// Solicitud de viaje enviada exitosamente
class JoinRequestSent extends TripState {
  final String tripId;

  const JoinRequestSent({required this.tripId});

  @override
  List<Object?> get props => [tripId];
}

/// Pasajero aceptado exitosamente
class PassengerAccepted extends TripState {
  final String tripId;
  final String passengerId;

  const PassengerAccepted({
    required this.tripId,
    required this.passengerId,
  });

  @override
  List<Object?> get props => [tripId, passengerId];
}

/// Pasajero rechazado exitosamente
class PassengerRejected extends TripState {
  final String tripId;
  final String passengerId;

  const PassengerRejected({
    required this.tripId,
    required this.passengerId,
  });

  @override
  List<Object?> get props => [tripId, passengerId];
}

/// Viaje iniciado exitosamente (scheduled → active)
class TripStarted extends TripState {
  final String tripId;

  const TripStarted({required this.tripId});

  @override
  List<Object?> get props => [tripId];
}

/// Viaje completado/finalizado exitosamente (active → completed)
class TripCompleted extends TripState {
  final String tripId;

  const TripCompleted({required this.tripId});

  @override
  List<Object?> get props => [tripId];
}

/// Viaje cancelado exitosamente
class TripCancelled extends TripState {
  final String tripId;

  const TripCancelled({required this.tripId});

  @override
  List<Object?> get props => [tripId];
}

/// Estado de pasajero actualizado (picked_up, no_show, dropped_off)
class PassengerStatusUpdated extends TripState {
  final String tripId;
  final String passengerId;
  final String newStatus;

  const PassengerStatusUpdated({
    required this.tripId,
    required this.passengerId,
    required this.newStatus,
  });

  @override
  List<Object?> get props => [tripId, passengerId, newStatus];
}

/// Error en operación de viaje
class TripError extends TripState {
  final String error;

  const TripError({required this.error});

  @override
  List<Object?> get props => [error];
}
