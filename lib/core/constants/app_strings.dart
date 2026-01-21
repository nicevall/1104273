// lib/core/constants/app_strings.dart
// Strings y textos de la aplicación

class AppStrings {
  // Constructor privado
  AppStrings._();

  // General
  static const String appName = 'UniRide';
  static const String appTagline = 'Tu viaje, tu comunidad';
  static const String appVersion = 'v1.0.0';

  // Validación de email
  static const String emailDomain = '@uide.edu.ec';
  static const String emailDomainError = 'Solo se permiten correos @uide.edu.ec';

  // Onboarding
  static const String onboardingTitle1 = 'Ahorra Dinero';
  static const String onboardingDesc1 = 'Divide los gastos de viaje. Llega a la U pagando menos.';

  static const String onboardingTitle2 = 'Solo estudiantes verificados';
  static const String onboardingDesc2 = 'Tu seguridad es primero. Solo miembros de tu universidad.';

  static const String onboardingTitle3 = 'Viaja seguro';
  static const String onboardingDesc3 = 'Sistema de calificaciones y perfiles verificados para tu tranquilidad.';

  // Botones
  static const String buttonLogin = 'INICIAR SESIÓN';
  static const String buttonRegister = 'REGISTRARSE';
  static const String buttonContinue = 'Siguiente';
  static const String buttonBack = 'Atrás';
  static const String buttonValidate = 'Validar';
  static const String buttonCorrect = 'Corregir';
  static const String buttonFinish = 'Finalizar';
  static const String buttonRetry = 'Reintentar';
  static const String buttonExit = 'Salir';
  static const String buttonStart = 'Comenzar';
  static const String buttonUnderstood = 'Entendido, Continuar';

  // Login
  static const String loginTitle = 'Iniciar Sesión';
  static const String loginRememberMe = 'Recordarme';
  static const String loginForgotPassword = '¿Olvidaste tu contraseña?';
  static const String loginNoAccount = '¿No tienes cuenta?';
  static const String loginRegisterLink = 'Regístrate';

  // Registro
  static const String registerStep1Title = 'Empecemos con lo básico';
  static const String registerStep1Subtitle = 'Completa tus datos para unirte a la comunidad UIDE';

  static const String registerStep2Title = 'Verifica tu correo';
  static const String registerStep2Subtitle = 'Enviamos un código de 6 dígitos a:';
  static const String registerStep2NoCode = '¿No recibiste el código?';
  static const String registerStep2Resend = 'Reenviar código OTP';

  static const String registerStep3Title = 'Información Adicional';
  static const String registerStep3Subtitle = 'Ayúdanos a conocerte mejor';

  static const String registerStep4Title = 'Selecciona tu rol';
  static const String registerStep4Subtitle = 'Elige cómo vas a usar la aplicación para ofrecerte la mejor experiencia.';

  static const String registerStep5Title = 'Importante: Selección de Rol';
  static const String registerStep5Message = 'No podrás cambiar tu rol una vez asignado.\n\nSi necesitas realizar cambios en el futuro, deberás contactar con soporte técnico.';
  static const String registerStep5SelectedRole = 'Rol seleccionado:';

  // Roles
  static const String rolePassenger = 'Pasajero';
  static const String rolePassengerDesc = 'Solo quiero encontrar viajes';
  static const String roleDriver = 'Conductor';
  static const String roleDriverDesc = 'Tengo auto y quiero llevar';
  static const String roleBoth = 'Ambos';
  static const String roleBothDesc = 'Quiero conducir y viajar';

  // Vehículo
  static const String vehicleTitle = 'Registro de Vehículo';
  static const String vehicleSubtitle = 'Solo para conductores';
  static const String vehiclePhotoTitle = 'Foto del Vehículo';
  static const String vehicleLicenseTitle = 'Foto de Licencia';
  static const String vehicleUploadPhoto = 'Subir foto';
  static const String vehicleAirConditioning = 'Aire Acondicionado';

  // Estados de registro
  static const String registrationSuccessTitle = '¡Tu registro ha sido exitoso!';
  static const String registrationSuccessSubtitle = 'Bienvenido a UniRide';
  static const String registrationErrorTitle = 'No se pudo completar el registro';
  static const String registrationNetworkTitle = 'Problemas con la red';
  static const String registrationNetworkMessage = 'Verifica tu conexión a internet\ne intenta nuevamente';

  // Placeholders
  static const String placeholderEmail = 'tu.correo@uide.edu.ec';
  static const String placeholderPassword = '••••••••';
  static const String placeholderFullName = 'Nombre Completo';
  static const String placeholderPhone = '+593 999-999-999';
  static const String placeholderCareer = 'Selecciona tu carrera';
  static const String placeholderSemester = '¿En qué ciclo estás?';
  static const String placeholderBrand = 'Seleccionar marca';
  static const String placeholderModel = 'e.g. Corolla';
  static const String placeholderYear = 'YYYY';
  static const String placeholderColor = 'e.g. Plateado';
  static const String placeholderPlate = 'AAA-XXXX';

  // Validaciones
  static const String validationRequired = 'Este campo es obligatorio';
  static const String validationEmailInvalid = 'Correo inválido';
  static const String validationEmailDomain = 'Usa tu correo institucional (.edu)';
  static const String validationPasswordShort = 'Mínimo 8 caracteres';
  static const String validationPasswordWeak = 'Debe contener mayúscula y número';
  static const String validationPasswordMismatch = 'Las contraseñas no coinciden';
  static const String validationPhoneInvalid = 'Número de teléfono inválido (10 dígitos)';
  static const String validationNameShort = 'Mínimo 3 caracteres';

  // Mensajes de error
  static const String errorGeneric = 'Ocurrió un error. Intenta nuevamente.';
  static const String errorNetwork = 'Sin conexión a internet';
  static const String errorInvalidCredentials = 'Correo o contraseña incorrectos';
  static const String errorEmailAlreadyExists = 'El correo ya está registrado';
  static const String errorInvalidOTP = 'Código incorrecto';
  static const String errorOTPExpired = 'Código expirado. Solicita uno nuevo.';

  // Progreso
  static const String progressStep = 'Paso';
  static const String progressOf = 'de';

  // Permisos
  static const String permissionCameraTitle = 'Permiso de Cámara';
  static const String permissionCameraMessage = 'Necesitamos acceso a tu cámara para tomar fotos del vehículo y licencia.';
  static const String permissionGalleryTitle = 'Permiso de Galería';
  static const String permissionGalleryMessage = 'Necesitamos acceso a tu galería para seleccionar fotos.';
  static const String permissionDenied = 'Permiso denegado';
  static const String permissionSettings = 'Ir a Configuración';

  // Carreras
  static const List<String> careers = [
    'Ingeniería en Sistemas',
    'Ingeniería Industrial',
    'Administración de Empresas',
    'Arquitectura',
    'Diseño Gráfico',
    'Psicología',
    'Derecho',
    'Medicina',
    'Odontología',
    'Otra',
  ];

  // Semestres
  static const List<String> semesters = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '10'
  ];
}
