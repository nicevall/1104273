import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/trips_service.dart';
import 'trip_event.dart';
import 'trip_state.dart';

/// BLoC de viajes
/// Maneja creación, búsqueda y gestión de viajes
class TripBloc extends Bloc<TripEvent, TripState> {
  final TripsService _tripsService;

  TripBloc({
    required TripsService tripsService,
  })  : _tripsService = tripsService,
        super(const TripInitial()) {
    on<CreateTripEvent>(_onCreateTrip);
    on<LoadDriverTripsEvent>(_onLoadDriverTrips);
    on<LoadTripDetailEvent>(_onLoadTripDetail);
    on<CancelTripEvent>(_onCancelTrip);
    on<AcceptPassengerEvent>(_onAcceptPassenger);
    on<RejectPassengerEvent>(_onRejectPassenger);
    on<SearchTripsEvent>(_onSearchTrips);
    on<RequestToJoinEvent>(_onRequestToJoin);
    on<StartTripEvent>(_onStartTrip);
    on<CompleteTripEvent>(_onCompleteTrip);
    on<UpdatePassengerStatusEvent>(_onUpdatePassengerStatus);
  }

  /// Crear viaje
  Future<void> _onCreateTrip(
    CreateTripEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🚗 TripBloc: Creando viaje...');
    emit(const TripLoading());

    try {
      final tripId = await _tripsService.createTrip(event.trip);
      final createdTrip = event.trip.copyWith(tripId: tripId);

      print('🚗 TripBloc: Viaje creado exitosamente → $tripId');
      emit(TripCreated(trip: createdTrip));
    } catch (e) {
      print('🚗 TripBloc: Error al crear viaje → $e');
      emit(TripError(error: e.toString()));
    }
  }

  /// Cargar viajes del conductor
  Future<void> _onLoadDriverTrips(
    LoadDriverTripsEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🚗 TripBloc: Cargando viajes del conductor ${event.driverId}...');
    emit(const TripLoading());

    try {
      final trips = await _tripsService.getDriverTrips(
        event.driverId,
        statusFilter: ['scheduled', 'active'],
      );

      print('🚗 TripBloc: ${trips.length} viajes encontrados');
      emit(DriverTripsLoaded(trips: trips));
    } catch (e) {
      print('🚗 TripBloc: Error al cargar viajes → $e');
      emit(TripError(error: e.toString()));
    }
  }

  /// Cargar detalle de un viaje
  Future<void> _onLoadTripDetail(
    LoadTripDetailEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🚗 TripBloc: Cargando detalle viaje ${event.tripId}...');
    emit(const TripLoading());

    try {
      final trip = await _tripsService.getTrip(event.tripId);

      if (trip == null) {
        emit(const TripError(error: 'Viaje no encontrado'));
        return;
      }

      print('🚗 TripBloc: Detalle cargado → ${trip.routeDescription}');
      emit(TripDetailLoaded(trip: trip));
    } catch (e) {
      print('🚗 TripBloc: Error al cargar detalle → $e');
      emit(TripError(error: e.toString()));
    }
  }

  /// Cancelar viaje
  Future<void> _onCancelTrip(
    CancelTripEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🚗 TripBloc: Cancelando viaje ${event.tripId}...');
    emit(const TripLoading());

    try {
      await _tripsService.cancelTrip(event.tripId);

      print('🚗 TripBloc: Viaje cancelado exitosamente');
      emit(TripCancelled(tripId: event.tripId));
    } catch (e) {
      print('🚗 TripBloc: Error al cancelar viaje → $e');
      emit(TripError(error: e.toString()));
    }
  }

  /// Aceptar pasajero
  Future<void> _onAcceptPassenger(
    AcceptPassengerEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🚗 TripBloc: Aceptando pasajero ${event.passengerId}...');
    emit(const TripLoading());

    try {
      await _tripsService.acceptPassenger(event.tripId, event.passengerId);

      print('🚗 TripBloc: Pasajero aceptado exitosamente');
      emit(PassengerAccepted(
        tripId: event.tripId,
        passengerId: event.passengerId,
      ));
    } catch (e) {
      print('🚗 TripBloc: Error al aceptar pasajero → $e');
      emit(TripError(error: e.toString()));
    }
  }

  /// Rechazar pasajero
  Future<void> _onRejectPassenger(
    RejectPassengerEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🚗 TripBloc: Rechazando pasajero ${event.passengerId}...');
    emit(const TripLoading());

    try {
      await _tripsService.rejectPassenger(
        event.tripId,
        event.passengerId,
        reason: event.reason,
      );

      print('🚗 TripBloc: Pasajero rechazado');
      emit(PassengerRejected(
        tripId: event.tripId,
        passengerId: event.passengerId,
      ));
    } catch (e) {
      print('🚗 TripBloc: Error al rechazar pasajero → $e');
      emit(TripError(error: e.toString()));
    }
  }

  /// Buscar viajes disponibles (pasajero)
  Future<void> _onSearchTrips(
    SearchTripsEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🔍 TripBloc: Buscando viajes disponibles...');
    emit(const TripLoading());

    try {
      final trips = await _tripsService.searchTrips(
        originLat: event.originLat,
        originLng: event.originLng,
        destLat: event.destLat,
        destLng: event.destLng,
        departureDate: event.departureDate,
        radiusKm: event.radiusKm,
      );

      print('🔍 TripBloc: ${trips.length} viajes encontrados');
      emit(TripsSearchResults(trips: trips));
    } catch (e) {
      print('🔍 TripBloc: Error al buscar viajes → $e');
      emit(TripError(error: e.toString()));
    }
  }

  /// Solicitar unirse a un viaje (pasajero)
  Future<void> _onRequestToJoin(
    RequestToJoinEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🚗 TripBloc: Solicitando unirse al viaje ${event.tripId}...');
    emit(const TripLoading());

    try {
      await _tripsService.requestToJoin(event.tripId, event.passenger);

      print('🚗 TripBloc: Solicitud enviada exitosamente');
      emit(JoinRequestSent(tripId: event.tripId));
    } catch (e) {
      print('🚗 TripBloc: Error al solicitar viaje → $e');
      emit(TripError(error: e.toString()));
    }
  }

  /// Iniciar viaje (scheduled → active)
  Future<void> _onStartTrip(
    StartTripEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🚗 TripBloc: Iniciando viaje ${event.tripId}...');
    emit(const TripLoading());

    try {
      await _tripsService.startTrip(event.tripId);

      print('🚗 TripBloc: Viaje iniciado exitosamente');
      emit(TripStarted(tripId: event.tripId));
    } catch (e) {
      print('🚗 TripBloc: Error al iniciar viaje → $e');
      emit(TripError(error: e.toString()));
    }
  }

  /// Completar/finalizar viaje (active → completed)
  Future<void> _onCompleteTrip(
    CompleteTripEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🚗 TripBloc: Finalizando viaje ${event.tripId}...');
    emit(const TripLoading());

    try {
      await _tripsService.completeTrip(event.tripId);

      print('🚗 TripBloc: Viaje finalizado exitosamente');
      emit(TripCompleted(tripId: event.tripId));
    } catch (e) {
      print('🚗 TripBloc: Error al finalizar viaje → $e');
      emit(TripError(error: e.toString()));
    }
  }

  /// Actualizar estado del pasajero (picked_up, no_show, dropped_off)
  Future<void> _onUpdatePassengerStatus(
    UpdatePassengerStatusEvent event,
    Emitter<TripState> emit,
  ) async {
    print('🚗 TripBloc: Actualizando estado pasajero ${event.passengerId} → ${event.newStatus}...');

    try {
      await _tripsService.updatePassengerStatus(
        event.tripId,
        event.passengerId,
        event.newStatus,
      );

      print('🚗 TripBloc: Estado actualizado exitosamente');
      emit(PassengerStatusUpdated(
        tripId: event.tripId,
        passengerId: event.passengerId,
        newStatus: event.newStatus,
      ));
    } catch (e) {
      print('🚗 TripBloc: Error al actualizar estado → $e');
      emit(TripError(error: e.toString()));
    }
  }
}
