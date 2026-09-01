package com.chronos.workbench

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 防沉迷「屏幕时间」原生通道(app/screen_time):
 * - hasPermission:检测「使用情况访问」特殊权限(AppOps,无法代点,只能引导用户去系统设置)。
 * - openPermissionSettings:跳系统的「使用情况访问权限」页。
 * - queryUsage:按时间段查询各 app 前台停留秒数(UsageStatsManager 事件流配对
 *   前台进入/退出;仍在前的 app 按查询窗口末端截断)。
 * - installedApps:列出有桌面图标的 app(包名 + 显示名),供用户分类。
 *
 * 不做常驻后台监控:数据系统一直在记,打开时查一次即可(省电、纯本地)。
 */
object ScreenTimePlugin {
    private const val channelName = "app/screen_time"

    fun register(activity: MainActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "hasPermission" -> result.success(hasUsagePermission(activity))
                        "openPermissionSettings" -> {
                            activity.startActivity(
                                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        }
                        "queryUsage" -> {
                            val begin = call.argument<Number>("begin")?.toLong()
                            val end = call.argument<Number>("end")?.toLong()
                            if (begin == null || end == null || end <= begin) {
                                result.error("bad_args", "begin/end missing or invalid", null)
                            } else {
                                result.success(queryUsage(activity, begin, end))
                            }
                        }
                        "installedApps" -> result.success(installedApps(activity))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("screen_time_error", e.message, null)
                }
            }
    }

    // 「使用情况访问」是否已授予:API 29+ 用 unsafeCheckOpNoThrow,旧版用 checkOpNoThrow。
    private fun hasUsagePermission(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_PACKAGE_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_PACKAGE_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    // 事件类型常量:前台进入(1)/退到后台(2)。新旧 API 同值,这里按版本取对应名字。
    private val resumeType: Int
        get() = if (Build.VERSION.SDK_INT >= 29)
            UsageEvents.Event.ACTIVITY_RESUMED
        else
            @Suppress("DEPRECATION")
            UsageEvents.Event.MOVE_TO_FOREGROUND

    private val pauseType: Int
        get() = if (Build.VERSION.SDK_INT >= 29)
            UsageEvents.Event.ACTIVITY_PAUSED
        else
            @Suppress("DEPRECATION")
            UsageEvents.Event.MOVE_TO_BACKGROUND

    /**
     * 查询 [beginMs, endMs) 内各 app 的前台秒数。
     * 做法:遍历事件流,「进入前台」记起点;「退到后台」结算一段;
     * 同一包名连续两次「进入」先结算上一段(重叠保护);
     * 结束时仍在前的按 endMs 截断(今天的查询传 now,即当前时刻)。
     * 返回 [{package, seconds}],只保留 >=1s 的。
     */
    private fun queryUsage(context: Context, beginMs: Long, endMs: Long): List<Map<String, Any>> {
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usm.queryEvents(beginMs, endMs)
        val event = UsageEvents.Event()
        val startAt = HashMap<String, Long>()
        val totals = HashMap<String, Long>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            val ts = event.timeStamp
            when (event.eventType) {
                resumeType -> {
                    startAt[pkg]?.let { s ->
                        totals[pkg] = (totals[pkg] ?: 0L) + (ts - s).coerceAtLeast(0L)
                    }
                    startAt[pkg] = ts
                }
                pauseType -> {
                    startAt.remove(pkg)?.let { s ->
                        totals[pkg] = (totals[pkg] ?: 0L) + (ts - s).coerceAtLeast(0L)
                    }
                }
            }
        }
        for ((pkg, s) in startAt) {
            totals[pkg] = (totals[pkg] ?: 0L) + (endMs - s).coerceAtLeast(0L)
        }
        return totals.entries
            .filter { it.value >= 1000L }
            .map { mapOf("package" to it.key, "seconds" to (it.value / 1000L)) }
    }

    // 有桌面图标的 app 清单(包名 + 显示名),按名称排序,供分类页展示。
    private fun installedApps(context: Context): List<Map<String, String>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val infos = pm.queryIntentActivities(intent, 0)
        return infos.mapNotNull { ri ->
            val pkg = ri.activityInfo?.packageName ?: return@mapNotNull null
            val label = try {
                ri.loadLabel(pm).toString()
            } catch (_: Exception) {
                pkg
            }
            mapOf("package" to pkg, "label" to label)
        }.sortedBy { it["label"] ?: "" }
    }
}
