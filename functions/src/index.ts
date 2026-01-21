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

    // 5. Crear/actualizar documento de usuario en Firestore
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
      rating: 5.0,
      totalTrips: 0,
      profilePhotoUrl: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // 6. Si es conductor/ambos y tiene vehículo, crear vehículo
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
    };
  } catch (error: any) {
    console.error('Error en checkRegistrationStatus:', error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError('internal', 'Error al verificar estado');
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
