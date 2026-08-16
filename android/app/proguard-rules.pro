# Flutter 官方壳与插件通道:R8 下保留,避免反射/JNI 入口被裁剪。
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# 本项目原生更新安装通道(MethodChannel + FileProvider)。
-keep class com.student.student_workbench.** { *; }
-keep class androidx.core.content.FileProvider { *; }

# audioplayers / flutter_tts / share_plus / sqflite / path_provider 等
# 依赖标准反射的部分由各插件自带 consumer rules 覆盖,这里仅兜底常见告警。
-dontwarn io.flutter.embedding.**

# 保留注解与泛型签名(部分插件序列化需要)。
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
