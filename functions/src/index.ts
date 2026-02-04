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
