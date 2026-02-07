import 'package:equatable/equatable.dart';
import '../../../data/models/trip_model.dart';

/// Eventos del TripBloc
/// Acciones que el conductor o pasajero pueden realizar
abstract class TripEvent extends Equatable {
  const TripEvent();

  @override
  List<Object?> get props => [];
}

/// Crear un nuevo viaje (conductor)
class CreateTripEvent extends TripEvent {
  final TripModel trip;

  const CreateTripEvent({required this.trip});

  @override
  List<Object?> get props => [trip];
}

/// Cargar viajes del conductor
class LoadDriverTripsEvent extends TripEvent {
  final String driverId;

  const LoadDriverTripsEvent({required this.driverId});

  @override
  List<Object?> get props => [driverId];
}

/// Cancelar un viaje (conductor)
class CancelTripEvent extends TripEvent {
  final String tripId;

  const CancelTripEvent({required this.tripId});

  @override
  List<Object?> get props => [tripId];
}

/// Aceptar pasajero (conductor)
class AcceptPassengerEvent extends TripEvent {
  final String tripId;
  final String passengerId;

  const AcceptPassengerEvent({
    required this.tripId,
    required this.passengerId,
  });

  @override
  List<Object?> get props => [tripId, passengerId];
}

/// Rechazar pasajero (conductor)
class RejectPassengerEvent extends TripEvent {
  final String tripId;
  final String passengerId;
  final String? reason;

  const RejectPassengerEvent({
    required this.tripId,
    required this.passengerId,
    this.reason,
  });

  @override
  List<Object?> get props => [tripId, passengerId, reason];
}

/// Buscar viajes disponibles (pasajero)
class SearchTripsEvent extends TripEvent {
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;
  final DateTime departureDate;
  final double radiusKm;

  const SearchTripsEvent({
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.departureDate,
    this.radiusKm = 5.0,
  });

  @override
  List<Object?> get props =>
      [originLat, originLng, destLat, destLng, departureDate, radiusKm];
}

/// Solicitar unirse a un viaje (pasajero)
class RequestToJoinEvent extends TripEvent {
  final String tripId;
  final TripPassenger passenger;

  const RequestToJoinEvent({
    required this.tripId,
    required this.passenger,
  });

  @override
  List<Object?> get props => [tripId, passenger];
}

/// Cargar detalle de un viaje específico
class LoadTripDetailEvent extends TripEvent {
  final String tripId;

  const LoadTripDetailEvent({required this.tripId});

  @override
  List<Object?> get props => [tripId];
}

/// Iniciar un viaje programado (scheduled → active)
class StartTripEvent extends TripEvent {
  final String tripId;

  const StartTripEvent({required this.tripId});

  @override
  List<Object?> get props => [tripId];
}

/// Completar/finalizar un viaje activo (active → completed)
class CompleteTripEvent extends TripEvent {
  final String tripId;

  const CompleteTripEvent({required this.tripId});

  @override
  List<Object?> get props => [tripId];
}

/// Actualizar estado de un pasajero (picked_up, no_show, dropped_off)
class UpdatePassengerStatusEvent extends TripEvent {
  final String tripId;
  final String passengerId;
  final String newStatus;

  const UpdatePassengerStatusEvent({
    required this.tripId,
    required this.passengerId,
    required this.newStatus,
  });

  @override
  List<Object?> get props => [tripId, passengerId, newStatus];
}
