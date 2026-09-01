package com.chronos.workbench

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/install")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "path is null", null)
                        } else {
                            installApk(path)
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // 后台生成前台服务启停:「掌柜正在回复…」保活进程,生成完成由 Flutter 停。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/chat_service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startChatService" -> {
                        startForegroundService(
                            Intent(this, ChatForegroundService::class.java)
                        )
                        result.success(true)
                    }
                    "stopChatService" -> {
                        stopService(Intent(this, ChatForegroundService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        // 防沉迷「屏幕时间」:读系统 UsageStats(权限检测/引导/前台时长聚合/已装 app)。
        ScreenTimePlugin.register(this, flutterEngine)
    }

    /// 用 FileProvider 生成 content URI,调起系统安装器安装 APK
    private fun installApk(path: String) {
        val file = File(path)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }
}
