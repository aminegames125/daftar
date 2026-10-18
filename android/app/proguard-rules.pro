# R8 rules for release builds. Flutter adds its own rules automatically.
# ML Kit text recognition ships optional script recognizers (Chinese, Japanese,
# Korean, Devanagari) that Daftar does not bundle; silence R8 about them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
