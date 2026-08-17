allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    // file_picker 8.0.7 自身固定 compileSdk=34,而其传递依赖
    // flutter_plugin_android_lifecycle 要求 >=36。统一把所有 Android 子模块
    // 的 compileSdk 强制抬到 36,消除 AAR 元数据校验冲突。
    // 注意:afterEvaluate 必须在 evaluationDependsOn(":app") 触发评估之前登记。
    afterEvaluate {
        val androidExtension = project.extensions.findByName("android")
        if (androidExtension is com.android.build.gradle.BaseExtension) {
            androidExtension.compileSdkVersion(36)
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
