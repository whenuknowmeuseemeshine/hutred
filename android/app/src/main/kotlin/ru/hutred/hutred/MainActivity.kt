package ru.hutred.hutred

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// AudioServiceActivity — чтобы музыка управлялась из шторки и экрана блокировки.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Виджеты на рабочем столе: папка с данными и «перерисуй».
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hutred/widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dir" -> result.success(File(filesDir, "widget").apply { mkdirs() }.absolutePath)
                    "refresh" -> {
                        HutredWidget.refreshAll(applicationContext)
                        result.success(null)
                    }
                    "ready" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }
}
