# LifeMode keep rules (only used if release minify is re-enabled).
-keep class com.tanveer.lifemode.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class * extends androidx.work.ListenableWorker { public <init>(android.content.Context, androidx.work.WorkerParameters); }
-keep class androidx.work.** { *; }
-keep class com.google.android.gms.location.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.**
