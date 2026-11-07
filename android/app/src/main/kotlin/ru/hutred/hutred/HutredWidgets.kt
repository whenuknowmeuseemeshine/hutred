package ru.hutred.hutred

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.net.Uri
import android.view.KeyEvent
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File

/**
 * Виджеты Hutred. Данные кладёт приложение (lib/services/widget_sync.dart)
 * в files/widget/widget.json, картинки — рядом.
 * Кнопки плеера — это медиакнопки: их ловит audio_service, даже если
 * приложение закрыто. Обложка и плейлисты открывают hutred://widget/…
 */
abstract class HutredWidget : AppWidgetProvider() {
    abstract val layout: Int
    abstract val tileCount: Int
    open val coverRadiusDp: Float = 10f

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            try {
                manager.updateAppWidget(id, build(context))
            } catch (e: Exception) {
                android.util.Log.w("HutredWidget", "update: $e")
            }
        }
    }

    private fun build(ctx: Context): RemoteViews {
        val v = RemoteViews(ctx.packageName, layout)
        val dir = File(ctx.filesDir, "widget")
        val d = try {
            JSONObject(File(dir, "widget.json").readText())
        } catch (e: Exception) {
            JSONObject()
        }
        val sharp = d.optBoolean("sharp", false)
        val bg = d.optLong("bg", 0xFF141414).toInt()
        val fg = d.optLong("fg", 0xFFF5F5F5).toInt()
        val muted = d.optLong("muted", 0xFFA3A3A3).toInt()
        val play = d.optLong("play", 0xFFF5F5F5).toInt()
        val playFg = d.optLong("playFg", 0xFF000000).toInt()
        val tile = d.optLong("tile", 0xFF262626).toInt()
        val density = ctx.resources.displayMetrics.density
        val r = if (sharp) 0f else coverRadiusDp * density

        v.setInt(R.id.bg, "setColorFilter", bg)
        v.setInt(R.id.logo, "setColorFilter", fg)
        v.setInt(R.id.play_bg, "setColorFilter", play)
        v.setInt(R.id.play_icon, "setColorFilter", playFg)
        v.setImageViewResource(R.id.play_icon, if (d.optBoolean("playing")) R.drawable.w_pause else R.drawable.w_play)
        v.setInt(R.id.prev, "setColorFilter", fg)
        v.setInt(R.id.next, "setColorFilter", fg)
        v.setInt(R.id.like, "setColorFilter", fg)
        v.setImageViewResource(R.id.like, if (d.optBoolean("favorite")) R.drawable.w_heart else R.drawable.w_heart_line)

        v.setTextViewText(R.id.title, d.optString("title", "Hutred"))
        v.setTextViewText(R.id.artist, d.optString("artist", "Нажми, чтобы включить волну"))
        v.setTextColor(R.id.title, fg)
        v.setTextColor(R.id.artist, muted)
        v.setTextColor(R.id.wave_title, fg)
        v.setTextColor(R.id.wave_sub, muted)
        v.setTextColor(R.id.recent, muted)
        v.setInt(R.id.wave_bg, "setColorFilter", tile)
        v.setInt(R.id.wave_icon, "setColorFilter", fg)
        v.setProgressBar(R.id.progress, 1000, (d.optDouble("progress", 0.0) * 1000).toInt(), false)

        val cover = image(dir, d.optString("cover", ""), r, if (tileCount == 8) 220 else 180)
        if (cover != null) {
            v.setImageViewBitmap(R.id.cover, cover)
        } else {
            v.setImageViewBitmap(R.id.cover, solid(tile, r))
        }

        // Кнопки плеера.
        v.setOnClickPendingIntent(R.id.prev, media(ctx, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
        v.setOnClickPendingIntent(R.id.next, media(ctx, KeyEvent.KEYCODE_MEDIA_NEXT))
        v.setOnClickPendingIntent(R.id.like, open(ctx, "hutred://widget/like"))
        if (this is HutredWidgetWave) {
            v.setImageViewResource(R.id.play_icon, R.drawable.w_play)
            v.setOnClickPendingIntent(R.id.play, open(ctx, "hutred://widget/open?item=wave"))
            v.setOnClickPendingIntent(R.id.root, open(ctx, "hutred://widget/open?item=wave"))
        } else {
            v.setOnClickPendingIntent(R.id.play, media(ctx, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            v.setOnClickPendingIntent(R.id.root, open(ctx, "hutred://widget/open?item=now"))
            v.setOnClickPendingIntent(R.id.cover, open(ctx, "hutred://widget/open?item=now"))
        }

        // Квадраты быстрого доступа.
        val tiles = d.optJSONArray("tiles")
        val tileR = if (sharp) 0f else 10f * density
        for (i in 0 until tileCount) {
            val ids = TILE_IDS[i]
            val t = tiles?.optJSONObject(i)
            if (t == null) {
                v.setViewVisibility(ids[0], android.view.View.INVISIBLE)
                continue
            }
            v.setViewVisibility(ids[0], android.view.View.VISIBLE)
            val kind = t.optString("kind")
            val img = image(dir, t.optString("image", ""), tileR, 112)
            v.setInt(ids[1], "setColorFilter", tileColor(kind, tile))
            if (img != null) {
                v.setImageViewBitmap(ids[2], img)
                v.setViewVisibility(ids[2], android.view.View.VISIBLE)
                v.setViewVisibility(ids[3], android.view.View.GONE)
            } else {
                v.setViewVisibility(ids[2], android.view.View.GONE)
                v.setViewVisibility(ids[3], android.view.View.VISIBLE)
                v.setImageViewResource(ids[3], when (kind) {
                    "fav" -> R.drawable.w_heart
                    "wave" -> R.drawable.w_wave
                    "downloads" -> R.drawable.w_down
                    else -> R.drawable.w_logo
                })
            }
            val item = Uri.encode(t.optString("id"))
            v.setOnClickPendingIntent(ids[0], open(ctx, "hutred://widget/open?item=$item"))
        }
        return v
    }

    private fun tileColor(kind: String, fallback: Int): Int = when (kind) {
        "fav" -> 0xFF6A4CF0.toInt()
        "wave" -> 0xFF1F8A6A.toInt()
        "downloads" -> 0xFF3A3A3A.toInt()
        else -> fallback
    }

    // Картинки маленькие: всё, что в виджете, передаётся системе одним
    // пакетом, а он не больше 1 МБ.
    private fun image(dir: File, name: String, radius: Float, maxPx: Int): Bitmap? {
        if (name.isEmpty() || name.contains('/')) return null
        val f = File(dir, name)
        if (!f.exists()) return null
        return try {
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(f.path, opts)
            var sample = 1
            while (opts.outWidth / sample > 320 || opts.outHeight / sample > 320) sample *= 2
            val raw = BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = sample })
                ?: return null
            val b = if (raw.width > maxPx || raw.height > maxPx) {
                Bitmap.createScaledBitmap(raw, maxPx, maxPx * raw.height / raw.width.coerceAtLeast(1), true)
            } else raw
            round(b, radius)
        } catch (e: Exception) {
            null
        }
    }

    private fun round(src: Bitmap, radius: Float): Bitmap {
        if (radius <= 0f) return src
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val rect = RectF(0f, 0f, src.width.toFloat(), src.height.toFloat())
        // Радиус в точках картинки (картинка на экране ~100dp).
        val rr = radius * src.width / (100f * 2.6f)
        c.drawRoundRect(rect, rr, rr, p)
        p.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        c.drawBitmap(src, 0f, 0f, p)
        return out
    }

    private fun solid(color: Int, radius: Float): Bitmap {
        val b = Bitmap.createBitmap(120, 120, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        val rr = if (radius <= 0f) 0f else 14f
        c.drawRoundRect(RectF(0f, 0f, 120f, 120f), rr, rr, p)
        return b
    }

    companion object {
        private val TILE_IDS = arrayOf(
            intArrayOf(R.id.tile0, R.id.tile0_bg, R.id.tile0_img, R.id.tile0_icon),
            intArrayOf(R.id.tile1, R.id.tile1_bg, R.id.tile1_img, R.id.tile1_icon),
            intArrayOf(R.id.tile2, R.id.tile2_bg, R.id.tile2_img, R.id.tile2_icon),
            intArrayOf(R.id.tile3, R.id.tile3_bg, R.id.tile3_img, R.id.tile3_icon),
            intArrayOf(R.id.tile4, R.id.tile4_bg, R.id.tile4_img, R.id.tile4_icon),
            intArrayOf(R.id.tile5, R.id.tile5_bg, R.id.tile5_img, R.id.tile5_icon),
            intArrayOf(R.id.tile6, R.id.tile6_bg, R.id.tile6_img, R.id.tile6_icon),
            intArrayOf(R.id.tile7, R.id.tile7_bg, R.id.tile7_img, R.id.tile7_icon),
        )

        private fun media(ctx: Context, code: Int): PendingIntent {
            val i = Intent(Intent.ACTION_MEDIA_BUTTON)
                .setComponent(ComponentName(ctx, "com.ryanheise.audioservice.MediaButtonReceiver"))
                .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, code))
            return PendingIntent.getBroadcast(
                ctx, 7000 + code, i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun open(ctx: Context, uri: String): PendingIntent {
            val i = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                .setClass(ctx, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                ctx, uri.hashCode(), i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /** Перерисовать все виджеты Hutred. */
        fun refreshAll(ctx: Context) {
            val mgr = AppWidgetManager.getInstance(ctx)
            for (cls in listOf(
                HutredWidgetSmall::class.java,
                HutredWidgetWave::class.java,
                HutredWidgetMedium::class.java,
                HutredWidgetLarge::class.java,
            )) {
                val ids = mgr.getAppWidgetIds(ComponentName(ctx, cls))
                if (ids.isEmpty()) continue
                val i = Intent(ctx, cls)
                    .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                ctx.sendBroadcast(i)
            }
        }
    }
}

class HutredWidgetSmall : HutredWidget() {
    override val layout = R.layout.widget_small
    override val tileCount = 0
}

class HutredWidgetWave : HutredWidget() {
    override val layout = R.layout.widget_wave
    override val tileCount = 0
}

class HutredWidgetMedium : HutredWidget() {
    override val layout = R.layout.widget_medium
    override val tileCount = 4
    override val coverRadiusDp = 8f
}

class HutredWidgetLarge : HutredWidget() {
    override val layout = R.layout.widget_large
    override val tileCount = 8
}
