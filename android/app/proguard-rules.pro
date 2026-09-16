# Flutter-specific ProGuard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter's embedding references Play Core classes (FlutterPlayStoreSplitApplication,
# PlayStoreDeferredComponentManager) that only exist when the com.google.android.play:core
# dependency is added for deferred components. This app does not use deferred components,
# so those code paths are never invoked and the missing references are safe to ignore.
-dontwarn com.google.android.play.core.**

# Supabase
-keep class io.supabase.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Sentry
-keep class io.sentry.** { *; }
