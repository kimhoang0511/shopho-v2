# Flutter Callkit Incoming
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
-keep class * extends com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver { *; }
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * extends android.app.Service { *; }
-keep class * extends android.app.Activity { *; }

# LiveKit WebRTC
-keep class io.livekit.** { *; }
-keep class org.webrtc.** { *; }

# Flutter plugins
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# MethodChannel reflection
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Gson / JSON serialization (used by callkit)
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class sun.misc.Unsafe { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Play Core (split install — not always included)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Retrofit / OkHttp (used by backend API calls)
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
