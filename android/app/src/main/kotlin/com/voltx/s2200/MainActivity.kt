package com.voltx.s2200

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hak/sound")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "buzz" -> {
                        HakAlert.buzz(this)
                        result.success(null)
                    }
                    "tick" -> {
                        try {
                            android.media.ToneGenerator(android.media.AudioManager.STREAM_MUSIC, 40)
                                .startTone(android.media.ToneGenerator.TONE_PROP_BEEP, 80)
                        } catch (_: Exception) {
                        }
                        result.success(null)
                    }
                    "keepOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        handler.post {
                            if (on) {
                                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    "watchFridge" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        val heard = (call.argument<Number>("heard")?.toLong()) ?: System.currentTimeMillis()
                        if (on) {
                            askNotify()
                            askBattery()
                            FridgeWatchService.start(this, heard)
                        } else {
                            FridgeWatchService.stop(this)
                        }
                        result.success(null)
                    }
                    "fridgeHeard" -> {
                        val at = (call.argument<Number>("at")?.toLong()) ?: System.currentTimeMillis()
                        FridgeWatchService.heard(this, at)
                        result.success(null)
                    }
                    "muteFridge" -> {
                        val on = call.argument<Boolean>("on") ?: true
                        if (on) FridgeWatchService.mute(this) else FridgeWatchService.unmute(this)
                        result.success(null)
                    }
                    "fridgeMuted" -> result.success(FridgeWatchService.muted)
                    "exitApp" -> {
                        FridgeWatchService.stop(this)
                        handler.post {
                            finishAffinity()
                            kotlin.system.exitProcess(0)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun askNotify() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 44)
        }
    }

    private fun askBattery() {
        if (Build.VERSION.SDK_INT < 23) return
        val prefs = getSharedPreferences("hak", MODE_PRIVATE)
        if (prefs.getBoolean("bat-asked", false)) return
        val pm = getSystemService(PowerManager::class.java) ?: return
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        prefs.edit().putBoolean("bat-asked", true).apply()
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
        }
    }
}
