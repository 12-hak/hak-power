package com.voltx.s2200

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

class FridgeWatchService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var wake: PowerManager.WakeLock? = null
    private var alarming = false

    private val tick = object : Runnable {
        override fun run() {
            val now = System.currentTimeMillis()
            val stale = now - lastHeard >= STALE_MS
            if (stale && !muted && watching) {
                if (!alarming) {
                    alarming = true
                    notifyAlarm()
                }
                HakAlert.buzz(this@FridgeWatchService)
                handler.postDelayed(this, 4000)
            } else {
                if (alarming && (!stale || muted)) {
                    alarming = false
                    notifyWatching()
                }
                handler.postDelayed(this, 15000)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        load(this)
        ensureChannel()
        val pm = getSystemService(PowerManager::class.java)
        wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "hak:fridge").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            cancelAlarm(this)
            if (Build.VERSION.SDK_INT >= 24) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_MUTE) {
            muted = true
            alarming = false
            cancelAlarm(this)
            persist(this)
        }
        val heard = intent?.getLongExtra(EXTRA_HEARD, 0L) ?: 0L
        if (heard > 0) lastHeard = heard
        persist(this)
        if (intent?.action == ACTION_HEARD) {
            muted = false
            persist(this)
        }
        watching = true
        startAsForeground()
        refreshNotif()
        handler.removeCallbacks(tick)
        handler.post(tick)
        schedule(this)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        try {
            if (wake?.isHeld == true) wake?.release()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun startAsForeground() {
        val notif = currentNotif()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun refreshNotif() {
        nm().notify(NOTIF_ID, currentNotif())
    }

    private fun notifyWatching() = refreshNotif()

    private fun notifyAlarm() = refreshNotif()

    private fun currentNotif(): Notification {
        return when {
            muted -> baseNotif("FRIDGE OFFLINE — MUTED", "Alerts silenced from Hak Power", false)
            alarming -> baseNotif("FRIDGE OFFLINE", "Tap to open · Mute in notification", true)
            else -> baseNotif("Watching Brass Monkey", "0.1.4 · alarm if unseen 5 min", false)
        }
    }

    private fun baseNotif(title: String, text: String, alarm: Boolean): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val mute = PendingIntent.getService(
            this,
            1,
            Intent(this, FridgeWatchService::class.java).setAction(ACTION_MUTE),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val channel = if (alarm && !muted) CHANNEL_ALARM else CHANNEL_QUIET
        val b = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        b.setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        if (!muted) {
            b.addAction(android.R.drawable.ic_lock_silent_mode, "Mute", mute)
        }
        if (Build.VERSION.SDK_INT >= 26 && !alarm) {
            b.setSilent(true)
        }
        if (Build.VERSION.SDK_INT >= 21) {
            b.setCategory(if (alarm && !muted) Notification.CATEGORY_ALARM else Notification.CATEGORY_SERVICE)
            b.setVisibility(Notification.VISIBILITY_PUBLIC)
        }
        return b.build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val alarm = NotificationChannel(CHANNEL_ALARM, "Fridge alarm", NotificationManager.IMPORTANCE_HIGH)
        alarm.setDescription("Sounds when Brass Monkey is unseen")
        alarm.enableVibration(true)
        val quiet = NotificationChannel(CHANNEL_QUIET, "Fridge watch", NotificationManager.IMPORTANCE_LOW)
        quiet.setDescription("Watching / muted — no sound")
        quiet.enableVibration(false)
        quiet.setSound(null, null)
        nm().createNotificationChannel(alarm)
        nm().createNotificationChannel(quiet)
    }

    private fun nm() = getSystemService(NotificationManager::class.java)

    companion object {
        const val CHANNEL_ALARM = "hak-fridge-alarm"
        const val CHANNEL_QUIET = "hak-fridge-quiet"
        const val NOTIF_ID = 2201
        const val ACTION_MUTE = "hak.fridge.MUTE"
        const val ACTION_STOP = "hak.fridge.STOP"
        const val ACTION_HEARD = "hak.fridge.HEARD"
        const val EXTRA_HEARD = "heard"
        const val STALE_MS = 5 * 60 * 1000L
        @Volatile var lastHeard = 0L
        @Volatile var watching = false
        @Volatile var muted = false

        fun start(ctx: Context, heard: Long) {
            if (heard > 0) lastHeard = heard
            else if (!watching) lastHeard = System.currentTimeMillis()
            watching = true
            persist(ctx)
            schedule(ctx)
            val i = Intent(ctx, FridgeWatchService::class.java).putExtra(EXTRA_HEARD, lastHeard)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun heard(ctx: Context, at: Long) {
            lastHeard = at
            muted = false
            persist(ctx)
            if (!watching) return
            schedule(ctx)
        }

        fun mute(ctx: Context) {
            muted = true
            persist(ctx)
            cancelAlarm(ctx)
            if (!watching) return
            ctx.startService(Intent(ctx, FridgeWatchService::class.java).setAction(ACTION_MUTE))
        }

        fun unmute(ctx: Context) {
            muted = false
            persist(ctx)
            if (!watching) return
            schedule(ctx)
            ctx.startService(Intent(ctx, FridgeWatchService::class.java).setAction(ACTION_HEARD).putExtra(EXTRA_HEARD, lastHeard))
        }

        fun stop(ctx: Context) {
            watching = false
            muted = false
            persist(ctx)
            cancelAlarm(ctx)
            ctx.stopService(Intent(ctx, FridgeWatchService::class.java))
        }

        fun onAlarm(ctx: Context) {
            load(ctx)
            if (!watching || muted) return
            val now = System.currentTimeMillis()
            if (now - lastHeard < STALE_MS) {
                schedule(ctx)
                return
            }
            start(ctx, lastHeard)
            scheduleAt(ctx, now + 4000L)
            HakAlert.buzz(ctx)
        }

        fun schedule(ctx: Context) {
            if (!watching || muted || lastHeard <= 0) {
                cancelAlarm(ctx)
                return
            }
            val due = lastHeard + STALE_MS
            val now = System.currentTimeMillis()
            if (due <= now) {
                scheduleAt(ctx, now + 4000L)
            } else {
                scheduleAt(ctx, due)
            }
        }

        private fun scheduleAt(ctx: Context, whenAt: Long) {
            val am = ctx.getSystemService(AlarmManager::class.java)
            val show = PendingIntent.getActivity(
                ctx,
                0,
                Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            am.setAlarmClock(AlarmManager.AlarmClockInfo(whenAt, show), alarmPi(ctx))
        }

        fun cancelAlarm(ctx: Context) {
            ctx.getSystemService(AlarmManager::class.java).cancel(alarmPi(ctx))
        }

        private fun alarmPi(ctx: Context): PendingIntent {
            val i = Intent(ctx, FridgeWatchReceiver::class.java).setAction(FridgeWatchReceiver.ACTION_ALARM)
            return PendingIntent.getBroadcast(ctx, 2202, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        fun persist(ctx: Context) {
            ctx.getSharedPreferences("hak", Context.MODE_PRIVATE).edit()
                .putLong("fridge-heard", lastHeard)
                .putBoolean("fridge-watch", watching)
                .putBoolean("fridge-muted", muted)
                .apply()
        }

        fun load(ctx: Context) {
            val p = ctx.getSharedPreferences("hak", Context.MODE_PRIVATE)
            val v = p.getLong("fridge-heard", 0L)
            if (v > 0) lastHeard = v
            watching = p.getBoolean("fridge-watch", watching)
            muted = p.getBoolean("fridge-muted", muted)
        }
    }
}
