# Keep Google ML Kit APIs from being stripped/obfuscated by R8
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Keep Google Play Services and dynamic loading APIs
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Ignore missing ML Kit text recognizer language classes since we only use Latin/English script
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
