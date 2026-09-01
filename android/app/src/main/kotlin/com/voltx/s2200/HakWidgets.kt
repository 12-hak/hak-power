package com.voltx.s2200

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import java.io.File

abstract class HakImageWidget : AppWidgetProvider() {
    abstract val key: String

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val file = File(context.filesDir, "$key.png")
        val bmp = if (file.exists()) BitmapFactory.decodeFile(file.absolutePath) else null
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(
            context,
            key.hashCode(),
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.hak_widget)
            if (bmp != null) {
                views.setImageViewBitmap(R.id.widget_image, bmp)
                views.setViewVisibility(R.id.widget_image, View.VISIBLE)
                views.setViewVisibility(R.id.widget_empty, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_image, View.GONE)
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            }
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            manager.updateAppWidget(id, views)
        }
    }

    companion object {
        fun save(context: Context, key: String, png: ByteArray) {
            File(context.filesDir, "$key.png").writeBytes(png)
            val cls = when (key) {
                "hak_voltx" -> HakVoltxWidget::class.java
                "hak_fridge" -> HakFridgeWidget::class.java
                "hak_juntek" -> HakJuntekWidget::class.java
                else -> HakDashWidget::class.java
            }
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isEmpty()) return
            val intent = Intent(context, cls).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            context.sendBroadcast(intent)
        }
    }
}

class HakVoltxWidget : HakImageWidget() {
    override val key = "hak_voltx"
}

class HakFridgeWidget : HakImageWidget() {
    override val key = "hak_fridge"
}

class HakJuntekWidget : HakImageWidget() {
    override val key = "hak_juntek"
}

class HakDashWidget : HakImageWidget() {
    override val key = "hak_dash"
}
