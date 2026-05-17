# ML Kit Text Recognition — suppress R8 warnings for unbundled script recognizers.
# Only Latin script is bundled; the plugin references Chinese/Devanagari/Japanese/Korean
# models internally but these are never loaded at runtime.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep ML Kit classes that ARE used (Latin recognizer)
-keep class com.google.mlkit.vision.text.** { *; }
