// functions/src/index.ts
// Cloud Functions para UniRide - PRODUCCIÓN
// Verificación por link nativo de Firebase (sin SendGrid, sin OTP)

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// Inicializar Firebase Admin
admin.initializeApp();

const db = admin.firestore();

// ============================================================================
// COMPLETAR REGISTRO (Guarda datos del perfil del usuario ya verificado)
// ============================================================================

/**
 * Completar registro - Guarda datos del perfil en Firestore
 * Se llama SOLO cuando el usuario completó todos los pasos
 * El usuario ya debe existir en Auth y tener email verificado
 */
export const completeRegistration = functions.https.onCall(async (data, context) => {
  try {
    // 1. Verificar autenticación
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesión');
    }

    const userId = context.auth.uid;
    const userEmail = context.auth.token.email;

    // 2. Verificar que el email esté verificado
    if (!context.auth.token.email_verified) {
      throw new functions.https.HttpsError('failed-precondition', 'El correo no ha sido verificado');
    }

    const {
      firstName,
      lastName,
      phoneNumber,
      career,
      semester,
      role,
      vehicle,
    } = data;

    // 3. Validar datos requeridos
    if (!firstName || !lastName || !phoneNumber || !career || !semester || !role) {
      throw new functions.https.HttpsError('invalid-argument', 'Faltan datos obligatorios');
    }

    if (!['pasajero', 'conductor', 'ambos'].includes(role)) {
      throw new functions.https.HttpsError('invalid-argument', 'Rol inválido');
    }

    // 4. Verificar si ya existe el perfil (evitar duplicados)
    const existingUser = await db.collection('users').doc(userId).get();
    if (existingUser.exists && existingUser.data()?.isProfileComplete) {
      throw new functions.https.HttpsError('already-exists', 'El perfil ya está completo');
    }

    // 5. Determinar si tiene vehículo
    const hasVehicle = (role === 'conductor' || role === 'ambos') && vehicle != null;

    // 6. Crear/actualizar documento de usuario en Firestore
    await db.collection('users').doc(userId).set({
      userId,
      email: userEmail,
      firstName,
      lastName,
      phoneNumber,
      career,
      semester,
      role,
      isVerified: true,
      isProfileComplete: true,
      hasVehicle,
      rating: 5.0,
      totalTrips: 0,
      profilePhotoUrl: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // 7. Si es conductor/ambos y tiene vehículo, crear vehículo
    if ((role === 'conductor' || role === 'ambos') && vehicle) {
      await db.collection('vehicles').add({
        ownerId: userId,
        brand: vehicle.brand,
        model: vehicle.model,
        year: vehicle.year,
        color: vehicle.color,
        plate: vehicle.plate.toUpperCase(),
        capacity: vehicle.capacity || 4,
        hasAirConditioning: vehicle.hasAirConditioning || false,
        photoUrl: vehicle.photoUrl || null,
        licensePhotoUrl: vehicle.licensePhotoUrl || null,
        isVerified: false, // Admin verificará después
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    console.log(`Registro completado: ${userId} (${userEmail})`);

    return {
      success: true,
      userId,
      message: 'Registro completado exitosamente',
    };
  } catch (error: any) {
    console.error('Error en completeRegistration:', error);

    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError('internal', error.message || 'Error al completar registro');
  }
});

// ============================================================================
// VERIFICAR ESTADO DE REGISTRO
// ============================================================================

/**
 * Verificar si el usuario tiene perfil completo
 */
export const checkRegistrationStatus = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesión');
    }

    const userId = context.auth.uid;
    const userDoc = await db.collection('users').doc(userId).get();

    return {
      exists: userDoc.exists,
      isProfileComplete: userDoc.data()?.isProfileComplete || false,
      role: userDoc.data()?.role || null,
      hasVehicle: userDoc.data()?.hasVehicle || false,
    };
  } catch (error: any) {
    console.error('Error en checkRegistrationStatus:', error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError('internal', 'Error al verificar estado');
  }
});

// ============================================================================
// REGISTRAR VEHÍCULO (Post-login para conductores)
// ============================================================================

/**
 * Registrar vehículo - Para usuarios que ya completaron registro sin vehículo
 * Actualiza hasVehicle a true y crea el documento del vehículo
 */
export const registerVehicle = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesión');
    }

    const userId = context.auth.uid;

    // Verificar que el usuario existe y es conductor/ambos
    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Usuario no encontrado');
    }

    const userData = userDoc.data();
    if (userData?.role !== 'conductor' && userData?.role !== 'ambos') {
      throw new functions.https.HttpsError('failed-precondition', 'Solo conductores pueden registrar vehículos');
    }

    if (userData?.hasVehicle) {
      throw new functions.https.HttpsError('already-exists', 'Ya tienes un vehículo registrado');
    }

    const { vehicle } = data;

    if (!vehicle || !vehicle.plate) {
      throw new functions.https.HttpsError('invalid-argument', 'Datos del vehículo incompletos');
    }

    // Crear documento del vehículo
    await db.collection('vehicles').add({
      ownerId: userId,
      brand: vehicle.brand,
      model: vehicle.model,
      year: vehicle.year,
      color: vehicle.color,
      plate: vehicle.plate.toUpperCase(),
      vinChasis: vehicle.vinChasis || null,
      claseVehiculo: vehicle.claseVehiculo || null,
      pasajeros: vehicle.pasajeros || 4,
      photoUrl: vehicle.photoUrl || null,
      licensePhotoUrl: vehicle.licensePhotoUrl || null,
      registrationPhotoUrl: vehicle.registrationPhotoUrl || null,
      licenseNumber: vehicle.licenseNumber || null,
      licenseHolderName: vehicle.licenseHolderName || null,
      licenseCategory: vehicle.licenseCategory || null,
      licenseExpiration: vehicle.licenseExpiration || null,
      vehicleOwnership: vehicle.vehicleOwnership || null,
      driverRelation: vehicle.driverRelation || null,
      isVerified: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Actualizar usuario con hasVehicle = true
    await db.collection('users').doc(userId).update({
      hasVehicle: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`Vehículo registrado para usuario: ${userId}`);

    return {
      success: true,
      message: 'Vehículo registrado exitosamente',
    };
  } catch (error: any) {
    console.error('Error en registerVehicle:', error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError('internal', error.message || 'Error al registrar vehículo');
  }
});

// ============================================================================
// TRIGGERS DE FIRESTORE
// ============================================================================

export const onUserCreated = functions.firestore
  .document('users/{userId}')
  .onCreate(async (snapshot, context) => {
    const userData = snapshot.data();
    console.log(`Usuario creado: ${context.params.userId}`, {
      email: userData.email,
      role: userData.role,
    });
    return null;
  });

export const onUserUpdated = functions.firestore
  .document('users/{userId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (!before.isProfileComplete && after.isProfileComplete) {
      console.log(`Perfil completado: ${context.params.userId}`);
    }
    return null;
  });

// ============================================================================
// HELPER: Enviar FCM y limpiar token inválido
// ============================================================================

async function sendFCM(
  userId: string,
  fcmToken: string,
  notification: { title: string; body: string },
  data: Record<string, string>,
): Promise<void> {
  try {
    await admin.messaging().send({
      token: fcmToken,
      notification,
      data,
      android: {
        priority: 'high',
        notification: {
          channelId: data.type === 'new_chat_message'
            ? 'uniride_chat_v2'
            : 'uniride_trips',
          sound: 'default',
        },
      },
    });
    console.log(`🔔 FCM enviado a ${userId} (${data.type})`);
  } catch (error: any) {
    if (
      error.code === 'messaging/registration-token-not-registered' ||
      error.code === 'messaging/invalid-registration-token'
    ) {
      console.log(`🔔 Token inválido para ${userId} — limpiando`);
      await db.collection('users').doc(userId).update({ fcmToken: null });
    } else {
      console.error(`🔔 Error FCM para ${userId}:`, error);
    }
  }
}

/** Obtener fcmToken de un usuario. Retorna null si no tiene. */
async function getUserToken(userId: string): Promise<string | null> {
  const userDoc = await db.collection('users').doc(userId).get();
  if (!userDoc.exists) return null;
  return userDoc.data()?.fcmToken || null;
}

/** Obtener nombre completo del usuario */
async function getUserName(userId: string): Promise<string> {
  const userDoc = await db.collection('users').doc(userId).get();
  if (!userDoc.exists) return 'Usuario';
  const data = userDoc.data();
  return `${data?.firstName || ''} ${data?.lastName || ''}`.trim() || 'Usuario';
}

// ============================================================================
// HELPER: Haversine — distancia entre dos coordenadas en km
// ============================================================================

function haversineDistance(
  lat1: number, lon1: number,
  lat2: number, lon2: number,
): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) *
    Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ============================================================================
// NOTIFICACIÓN 1: Solicitud de viaje aceptada → notificar al pasajero
// ============================================================================

/**
 * Trigger: ride_requests/{requestId} onUpdate
 * Condición: status cambió a 'accepted'
 * Acción: Notificar al pasajero que su solicitud fue aceptada
 */
export const onRideRequestAccepted = functions.firestore
  .document('ride_requests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Solo disparar cuando status cambia a 'accepted'
    if (before.status === 'accepted' || after.status !== 'accepted') {
      return null;
    }

    const passengerId: string = after.passengerId;
    const tripId: string = after.tripId || '';
    const requestId: string = context.params.requestId;

    console.log(`🔔 Solicitud aceptada: ${requestId} → pasajero ${passengerId}`);

    const token = await getUserToken(passengerId);
    if (!token) {
      console.log(`🔔 Pasajero ${passengerId} sin FCM token`);
      return null;
    }

    await sendFCM(passengerId, token, {
      title: '¡Conductor encontrado!',
      body: 'Tu solicitud de viaje fue aceptada',
    }, {
      type: 'request_accepted',
      tripId,
      requestId,
    });

    return null;
  });

// ============================================================================
// NOTIFICACIÓN 2: Conductor llegó al punto de recogida → notificar pasajeros
// ============================================================================

/**
 * Trigger: trips/{tripId} onUpdate
 * Condición: driverArrivedNotified cambió de false/undefined a true
 * Acción: Notificar a todos los pasajeros con status 'accepted'
 *
 * Usamos un flag booleano en lugar de detectar waitingStartedAt null→non-null
 * porque FieldValue.serverTimestamp() puede causar invocaciones dobles
 * donde el before ya tiene un timestamp pendiente (no null).
 */
export const onDriverArrived = functions.firestore
  .document('trips/{tripId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Solo disparar cuando driverArrivedNotified cambia a true
    const wasFlaggedBefore = before.driverArrivedNotified === true;
    const isFlaggedAfter = after.driverArrivedNotified === true;

    if (wasFlaggedBefore || !isFlaggedAfter) {
      return null;
    }

    const tripId: string = context.params.tripId;
    const passengers: any[] = after.passengers || [];

    console.log(`🔔 Conductor llegó: trip ${tripId}`);

    // Notificar a todos los pasajeros con status 'accepted'
    const promises: Promise<void>[] = [];
    for (const p of passengers) {
      if (p.status === 'accepted' && p.userId) {
        promises.push(
          (async () => {
            const token = await getUserToken(p.userId);
            if (token) {
              await sendFCM(p.userId, token, {
                title: 'Tu conductor llegó',
                body: 'Está esperando en el punto de recogida',
              }, {
                type: 'driver_arrived',
                tripId,
              });
            }
          })(),
        );
      }
    }

    await Promise.all(promises);
    return null;
  });

// ============================================================================
// NOTIFICACIÓN 3: Viaje cancelado → notificar pasajeros activos
// ============================================================================

/**
 * Trigger: trips/{tripId} onUpdate
 * Condición: status cambió a 'cancelled'
 * Acción: Notificar a pasajeros con status 'accepted' o 'picked_up'
 */
export const onTripCancelled = functions.firestore
  .document('trips/{tripId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Solo disparar cuando status cambia a 'cancelled'
    if (before.status === 'cancelled' || after.status !== 'cancelled') {
      return null;
    }

    const tripId: string = context.params.tripId;
    const passengers: any[] = after.passengers || [];

    console.log(`🔔 Viaje cancelado: trip ${tripId}`);

    const promises: Promise<void>[] = [];
    for (const p of passengers) {
      if ((p.status === 'accepted' || p.status === 'picked_up') && p.userId) {
        promises.push(
          (async () => {
            const token = await getUserToken(p.userId);
            if (token) {
              await sendFCM(p.userId, token, {
                title: 'Viaje cancelado',
                body: 'El conductor canceló el viaje',
              }, {
                type: 'trip_cancelled',
                tripId,
              });
            }
          })(),
        );
      }
    }

    await Promise.all(promises);
    return null;
  });

// ============================================================================
// NOTIFICACIÓN 4: Nueva solicitud de viaje → notificar conductores cercanos
// ============================================================================

/**
 * Trigger: ride_requests/{requestId} onCreate
 * Condición: status == 'searching'
 * Acción: Buscar trips activos con destino similar (haversine < 5km)
 *         y notificar a cada conductor
 */
export const onNewRideRequest = functions.firestore
  .document('ride_requests/{requestId}')
  .onCreate(async (snapshot, context) => {
    const data = snapshot.data();

    if (data.status !== 'searching') {
      return null;
    }

    const requestId: string = context.params.requestId;
    const passengerId: string = data.passengerId;
    const destLat: number = data.destLat;
    const destLng: number = data.destLng;

    console.log(`🔔 Nueva solicitud: ${requestId} de pasajero ${passengerId}`);

    // Obtener nombre del pasajero
    const passengerName = await getUserName(passengerId);

    // Buscar viajes activos o in_progress
    const activeTrips = await db.collection('trips')
      .where('status', 'in', ['active', 'in_progress'])
      .get();

    const promises: Promise<void>[] = [];
    for (const tripDoc of activeTrips.docs) {
      const trip = tripDoc.data();
      const tripDest = trip.destination;

      if (!tripDest || !tripDest.latitude || !tripDest.longitude) continue;

      // Verificar distancia entre destinos (< 5km)
      const dist = haversineDistance(
        destLat, destLng,
        tripDest.latitude, tripDest.longitude,
      );

      if (dist > 5) continue;

      // Verificar que hay asientos disponibles
      const passengers: any[] = trip.passengers || [];
      const activePassengers = passengers.filter(
        (p: any) => p.status === 'accepted' || p.status === 'picked_up',
      );
      const maxCapacity = trip.maxPassengers || 4;
      if (activePassengers.length >= maxCapacity) continue;

      // No notificar al propio pasajero si es conductor de otro viaje
      const driverId: string = trip.driverId;
      if (driverId === passengerId) continue;

      promises.push(
        (async () => {
          const token = await getUserToken(driverId);
          if (token) {
            await sendFCM(driverId, token, {
              title: 'Nueva solicitud',
              body: `${passengerName} quiere unirse a tu viaje`,
            }, {
              type: 'new_ride_request',
              tripId: tripDoc.id,
              requestId,
            });
          }
        })(),
      );
    }

    await Promise.all(promises);
    return null;
  });

// ============================================================================
// NOTIFICACIÓN 5: Nuevo mensaje de chat → notificar al rol opuesto
// ============================================================================

/**
 * Trigger: chats/{chatId}/messages/{messageId} onCreate
 * chatId formato: "{tripId}__{passengerId}"
 * Acción: Si senderRole='conductor' → notificar pasajero
 *         Si senderRole='pasajero' → notificar conductor (obtener driverId del trip)
 */
export const onNewChatMessage = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data();
    const chatId: string = context.params.chatId;
    const senderRole: string = message.senderRole || '';
    const senderId: string = message.senderId || '';
    const text: string = message.text || '';

    console.log(`🔔 Chat trigger: chatId=${chatId}, senderRole=${senderRole}, senderId=${senderId}`);

    // Parsear chatId: "tripId__passengerId"
    const parts = chatId.split('__');
    if (parts.length !== 2) {
      console.error(`🔔 chatId inválido: ${chatId}`);
      return null;
    }

    const tripId = parts[0];
    const passengerId = parts[1];

    // Obtener nombre del remitente
    const senderName = await getUserName(senderId);

    // Determinar destinatario
    let recipientId: string;

    if (senderRole === 'conductor') {
      // Conductor envía → notificar al pasajero
      recipientId = passengerId;
      console.log(`🔔 Conductor→Pasajero: recipientId=${recipientId}`);
    } else {
      // Pasajero envía → obtener driverId del trip
      const tripDoc = await db.collection('trips').doc(tripId).get();
      if (!tripDoc.exists) {
        console.log(`🔔 Trip ${tripId} no encontrado para chat`);
        return null;
      }
      recipientId = tripDoc.data()?.driverId;
      console.log(`🔔 Pasajero→Conductor: driverId=${recipientId} (trip ${tripId})`);
    }

    if (!recipientId) {
      console.log('🔔 No se pudo determinar destinatario del chat');
      return null;
    }

    const token = await getUserToken(recipientId);
    if (!token) {
      console.log(`🔔 Destinatario ${recipientId} sin FCM token`);
      return null;
    }

    // Truncar texto a 100 chars para la notificación
    const truncatedText = text.length > 100
      ? text.substring(0, 97) + '...'
      : text;

    await sendFCM(recipientId, token, {
      title: `Mensaje de ${senderName}`,
      body: truncatedText,
    }, {
      type: 'new_chat_message',
      tripId,
      senderId,
      senderRole,
    });

    return null;
  });
