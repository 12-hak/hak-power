package com.voltx.s2200

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class FridgeWatchReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, ACTION_ALARM -> FridgeWatchService.onAlarm(ctx)
        }
    }

    companion object {
        const val ACTION_ALARM = "com.voltx.s2200.FRIDGE_ALARM"
    }
}
