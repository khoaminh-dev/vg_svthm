# ML Kit Text Recognition: app chỉ dùng bộ Latin; bỏ qua cảnh báo thiếu class của các bộ chữ khác
# (Chinese, Japanese, Korean, Devanagari) mà plugin tham chiếu nhưng không đóng gói.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# Nhắc uống thuốc (flutter_local_notifications): giữ lớp dùng phản chiếu khi lưu và đọc lịch báo thức.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keep class * extends com.google.gson.reflect.TypeToken
