
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { ImageAnnotatorClient } from '@google-cloud/vision';

// Inicializar cliente de Vision API
const client = new ImageAnnotatorClient();

/**
 * Analizar documento con Google Cloud Vision API
 * Recibe: 
 * - image: base64 string o gcs uri
 * - type: 'license' | 'registration'
 */
export const analyzeDocument = functions.https.onCall(async (data, context) => {
    try {
        // 1. Verificar autenticación
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'Debes iniciar sesión');
        }

        const { image, type } = data;

        if (!image || !type) {
            throw new functions.https.HttpsError('invalid-argument', 'Falta imagen o tipo de documento');
        }

        // 2. Configurar request para Vision API
        const request = {
            image: {
                content: image.startsWith('gs://') ? undefined : image,
                source: image.startsWith('gs://') ? { imageUri: image } : undefined,
            },
            features: [
                { type: 'TEXT_DETECTION' },
                { type: 'LABEL_DETECTION' }, // Para verificar si es un documento/auto
            ],
        };

        // 3. Llamar a Vision API
        const [result] = await client.annotateImage(request as any);
        const fullText = result.fullTextAnnotation?.text || '';
        const labels = result.labelAnnotations || [];

        // 4. Procesar según tipo de documento
        if (type === 'license') {
            return _processLicense(fullText, labels);
        } else if (type === 'registration') {
            return _processRegistration(fullText, labels);
        } else {
            throw new functions.https.HttpsError('invalid-argument', 'Tipo de documento no soportado');
        }

    } catch (error: any) {
        console.error('Error en analyzeDocument:', error);
        throw new functions.https.HttpsError('internal', error.message || 'Error al analizar documento');
    }
});

// Procesamiento de Licencia
function _processLicense(text: string, labels: any[]) {
    // Normalizar texto
    const normalizedText = text.toUpperCase();

    // Extraer datos usando Regex (Lógica migrada de Flutter)
    const licenseNumber = _extractRegex(normalizedText, /\b\d{10}\b/);
    const category = _extractRegex(normalizedText, /CATEGOR[IÍ]A\s*[:\-]?\s*([A-E][1-2]?)/);
    const expirationDate = _extractRegex(normalizedText, /(?:VENCIMIENTO|CADUCIDAD)\s*[:\-]?\s*(\d{1,2}[\-/]\d{1,2}[\-/]\d{4})/);
    const bloodType = _extractRegex(normalizedText, /\b(AB?|O)\s*RH?\s*([+-])/);

    // Nombres y Apellidos (Simple aproximación)
    const namePattern = /(?:NOMBRES|NAME)\s*[:\-]?\s*([A-Z\s]+)/;
    const lastNamePattern = /(?:APELLIDOS|FAMILY NAME)\s*[:\-]?\s*([A-Z\s]+)/;

    const names = _extractRegex(normalizedText, namePattern);
    const lastNames = _extractRegex(normalizedText, lastNamePattern);

    // Validaciones
    const isExpired = _checkExpiration(expirationDate);
    const hasCategoryB = category?.includes('B') || false;

    return {
        type: 'license',
        rawText: text,
        data: {
            licenseNumber,
            category,
            expirationDate,
            bloodType,
            names: names?.trim(),
            lastNames: lastNames?.trim(),
        },
        validation: {
            isExpired,
            hasCategoryB,
            isValid: !isExpired && hasCategoryB && !!licenseNumber,
        }
    };
}

// Procesamiento de Matrícula
function _processRegistration(text: string, labels: any[]) {
    const normalizedText = text.toUpperCase();

    const plate = _extractRegex(normalizedText, /\b([A-Z]{3})[\s\-]?(\d{3,4})\b/);
    const year = _extractRegex(normalizedText, /A[ÑN]O\s*[:\-]?\s*(19\d{2}|20[0-2]\d)/);
    const vin = _extractRegex(normalizedText, /(?:VIN|CHASIS)\s*[:\-]?\s*([A-Z0-9]{17})\b/);

    // Marcas comunes
    const brands = ['CHEVROLET', 'TOYOTA', 'NISSAN', 'HYUNDAI', 'KIA', 'MAZDA', 'FORD', 'RENAULT'];
    let brand = null;
    for (const b of brands) {
        if (normalizedText.includes(b)) {
            brand = b;
            break;
        }
    }

    return {
        type: 'registration',
        rawText: text,
        data: {
            plate,
            year,
            vin,
            brand,
        },
        validation: {
            isValid: !!plate && !!brand,
        }
    };
}

// Helper para extraer regex
function _extractRegex(text: string, regex: RegExp): string | null {
    const match = text.match(regex);
    if (match && match.length > 0) {
        // Retornar el grupo de captura si existe, sino toda la coincidencia
        return match[1] || match[0];
    }
    return null;
}

// Helper para fecha de expiración
function _checkExpiration(dateStr: string | null): boolean {
    if (!dateStr) return true; // Si no hay fecha, asumir inválido/expirado
    try {
        // Asumiendo formato DD/MM/YYYY o DD-MM-YYYY
        const parts = dateStr.replace(/\//g, '-').split('-');
        if (parts.length !== 3) return true;

        const day = parseInt(parts[0]);
        const month = parseInt(parts[1]) - 1; // Meses en JS son 0-11
        const year = parseInt(parts[2]);

        const expDate = new Date(year, month, day);
        const now = new Date();

        return now > expDate;
    } catch (e) {
        return true;
    }
}
