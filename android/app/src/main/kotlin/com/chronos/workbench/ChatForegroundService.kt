package com.chronos.workbench

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/// 前台服务(Android 14, dataSync 类型):app 退后台且掌柜正在生成回复时保活进程,
/// 让 Dart 主 isolate 的 SSE 流式继续不被系统冻结;生成完成由 Flutter 侧调 stopService。
class ChatForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "chat_generating"
        const val NOTIFICATION_ID = 1001
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification("掌柜正在回复…"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "掌柜回复中",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "掌柜生成回复时的状态通知" }
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): android.app.Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("零时闲话铺")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build()
    }
}
