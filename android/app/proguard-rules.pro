# Flutter ProGuard rules

# permission_handler — keep to prevent MissingPluginException in release
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# shared_preferences — keep pigeon-generated classes
-keep class dev.flutter.pigeon.shared_preferences_android.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# geolocator
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# google_mlkit_text_recognition — suppress missing optional language classes
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Play Store deferred components (not used, but referenced by Flutter engine)
-dontwarn com.google.android.play.core.**
