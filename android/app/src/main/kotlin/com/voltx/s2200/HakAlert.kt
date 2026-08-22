package com.voltx.s2200

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

object HakAlert {
    private val handler = Handler(Looper.getMainLooper())

    fun buzz(ctx: Context) {
        vibrate(ctx, longArrayOf(0, 220, 80, 280, 80, 220))
        playAlarm(ctx)
    }

    private fun playAlarm(ctx: Context) {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            mp.setDataSource(ctx, uri)
            mp.setVolume(1f, 1f)
            mp.setOnCompletionListener { it.release() }
            mp.prepare()
            mp.start()
            handler.postDelayed({
                try {
                    mp.stop()
                    mp.release()
                } catch (_: Exception) {
                }
            }, 1200)
        } catch (_: Exception) {
            try {
                ToneGenerator(AudioManager.STREAM_ALARM, 100).startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 900)
            } catch (_: Exception) {
            }
        }
    }

    private fun vibrate(ctx: Context, pattern: LongArray) {
        val vibrator = if (Build.VERSION.SDK_INT >= 31) {
            ctx.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            ctx.getSystemService(Vibrator::class.java)
        }
        if (Build.VERSION.SDK_INT >= 26) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }
}
