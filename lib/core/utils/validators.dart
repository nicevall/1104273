// lib/core/utils/validators.dart
// Validadores para formularios

import '../constants/app_strings.dart';

class Validators {
  // Constructor privado
  Validators._();

  // Caracteres especiales permitidos
  static const String allowedSpecialChars = '@#\$%&*!?-_';

  // Validar email con dominio @uide.edu.ec
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return AppStrings.validationRequired;
    }

    // Validación CRÍTICA: Solo dominio @uide.edu.ec
    if (!value.endsWith(AppStrings.emailDomain)) {
      return AppStrings.emailDomainError;
    }

    // Validar formato completo
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@uide\.edu\.ec$');
    if (!emailRegex.hasMatch(value)) {
      return AppStrings.validationEmailInvalid;
    }

    return null;
  }

  // Validar contraseña
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppStrings.validationRequired;
    }

    // 1. Longitud mínima
    if (value.length < 8) {
      return 'Debe tener al menos 8 caracteres';
    }

    // 2. Al menos una minúscula
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Debe contener al menos una minúscula';
    }

    // 3. Al menos una mayúscula
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Debe contener al menos una mayúscula';
    }

    // 4. Al menos un número
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Debe contener al menos un número';
    }

    // 5. Al menos un caracter especial permitido
    if (!RegExp(r'[@#$%&*!?\-_]').hasMatch(value)) {
      return 'Debe contener al menos un caracter especial (@#\$%&*!?-_)';
    }

    // 6. Verificar que NO contenga caracteres especiales no permitidos
    // Permitir: letras, números y caracteres especiales permitidos
    if (!RegExp(r'^[a-zA-Z0-9@#$%&*!?\-_]+$').hasMatch(value)) {
      return 'Solo se permiten: letras, números y @#\$%&*!?-_';
    }

    return null;
  }

  // Verificar si la contraseña tiene caracteres especiales no permitidos
  static bool hasInvalidSpecialChars(String password) {
    // Si NO cumple con el patrón permitido, tiene caracteres inválidos
    return !RegExp(r'^[a-zA-Z0-9@#$%&*!?\-_]*$').hasMatch(password);
  }

  // Obtener lista de caracteres no permitidos en la contraseña
  static List<String> getInvalidChars(String password) {
    final List<String> invalidChars = [];
    final validPattern = RegExp(r'[a-zA-Z0-9@#$%&*!?\-_]');

    for (int i = 0; i < password.length; i++) {
      final char = password[i];
      if (!validPattern.hasMatch(char) && !invalidChars.contains(char)) {
        invalidChars.add(char);
      }
    }

    return invalidChars;
  }

  // Validar confirmación de contraseña
  static String? validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return AppStrings.validationRequired;
    }

    if (value != password) {
      return AppStrings.validationPasswordMismatch;
    }

    return null;
  }

  // Validar nombre completo
  static String? validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return AppStrings.validationRequired;
    }

    if (value.trim().length < 3) {
      return AppStrings.validationNameShort;
    }

    // Solo letras y espacios
    if (!RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$').hasMatch(value)) {
      return 'Solo se permiten letras';
    }

    return null;
  }

  // Validar teléfono (10 dígitos)
  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return AppStrings.validationRequired;
    }

    // Remover espacios, guiones y el prefijo +593
    final cleanPhone = value.replaceAll(RegExp(r'[\s\-+]'), '');

    // Validar que tenga 10 dígitos después de remover el 593
    String phoneDigits = cleanPhone;
    if (cleanPhone.startsWith('593')) {
      phoneDigits = cleanPhone.substring(3);
    }

    if (!RegExp(r'^[0-9]{10}$').hasMatch(phoneDigits)) {
      return AppStrings.validationPhoneInvalid;
    }

    return null;
  }

  // Validar código OTP (6 dígitos)
  static String? validateOTP(String? value) {
    if (value == null || value.isEmpty) {
      return AppStrings.validationRequired;
    }

    if (!RegExp(r'^[0-9]{6}$').hasMatch(value)) {
      return 'Código inválido (6 dígitos)';
    }

    return null;
  }

  // Validar placa de vehículo (AAA-1234)
  static String? validatePlate(String? value) {
    if (value == null || value.isEmpty) {
      return AppStrings.validationRequired;
    }

    if (!RegExp(r'^[A-Z]{3}-[0-9]{4}$').hasMatch(value.toUpperCase())) {
      return 'Formato inválido (AAA-1234)';
    }

    return null;
  }

  // Validar año de vehículo
  static String? validateYear(String? value) {
    if (value == null || value.isEmpty) {
      return AppStrings.validationRequired;
    }

    final year = int.tryParse(value);
    if (year == null) {
      return 'Año inválido';
    }

    final currentYear = DateTime.now().year;
    if (year < 1990 || year > currentYear + 1) {
      return 'Año debe estar entre 1990 y $currentYear';
    }

    return null;
  }

  // Validar campo requerido genérico
  static String? validateRequired(String? value, [String? fieldName]) {
    if (value == null || value.trim().isEmpty) {
      return fieldName != null
          ? '$fieldName es obligatorio'
          : AppStrings.validationRequired;
    }
    return null;
  }

  // Alias para compatibilidad
  static String? validateName(String? value) => validateFullName(value);

  static String? validatePasswordConfirmation(String? value, String password) =>
      validateConfirmPassword(value, password);

  // Calcular fuerza de contraseña
  static PasswordStrength calculatePasswordStrength(String password) {
    if (password.isEmpty) {
      return PasswordStrength.weak;
    }

    int strength = 0;

    // Requisitos básicos (obligatorios)
    final hasMinLength = password.length >= 8;
    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecialChar = RegExp(r'[@#$%&*!?\-_]').hasMatch(password);
    final hasInvalidChars = hasInvalidSpecialChars(password);

    // Si tiene caracteres inválidos, es débil automáticamente
    if (hasInvalidChars) {
      return PasswordStrength.weak;
    }

    // Contar requisitos cumplidos (5 básicos)
    if (hasMinLength) strength++;
    if (hasLowercase) strength++;
    if (hasUppercase) strength++;
    if (hasNumber) strength++;
    if (hasSpecialChar) strength++;

    // Puntos extras por longitud
    if (password.length >= 12) strength++;

    // Clasificación:
    // Débil: 0-3 requisitos
    // Media: 4-5 requisitos
    // Fuerte: 6 requisitos (todos + longitud extra)
    if (strength <= 3) {
      return PasswordStrength.weak;
    } else if (strength <= 5) {
      return PasswordStrength.medium;
    } else {
      return PasswordStrength.strong;
    }
  }
}

// Enum para fuerza de contraseña
enum PasswordStrength {
  weak,
  medium,
  strong,
}
