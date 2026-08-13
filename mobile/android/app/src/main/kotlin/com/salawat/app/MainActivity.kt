package com.salawat.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.salawat.app/background_taps"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Hands over taps buffered by the notification/widget and
                    // clears them in one synchronized step. Dart folds the
                    // result into CounterController.
                    "drain" -> result.success(SalawatBuffer.drain(this))

                    // Dart is the source of truth for the count; push it down
                    // after every drain and tap so both surfaces render the
                    // real number rather than their own running total.
                    "setDisplay" -> {
                        val value = call.argument<Int>("value") ?: 0
                        SalawatBuffer.setDisplay(this, value)
                        QuickTapNotification.refreshIfEnabled(this)
                        SalawatWidgetProvider.renderAll(this)
                        result.success(null)
                    }

                    // One switch for the whole feature. Which surfaces show up
                    // is decided by the overlay permission, not by a second
                    // preference — see SalawatBuffer.quickTapEnabled.
                    "setQuickTapEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        SalawatBuffer.setQuickTapEnabled(this, enabled)
                        if (enabled) {
                            QuickTapNotification.show(this, SalawatBuffer.display(this))
                        } else {
                            OverlayService.stop(this)
                            QuickTapNotification.hide(this)
                        }
                        result.success(null)
                    }

                    "isQuickTapEnabled" ->
                        result.success(SalawatBuffer.quickTapEnabled(this))

                    "canDrawOverlays" ->
                        result.success(OverlayService.canDrawOverlays(this))

                    // Can only be granted from a system settings screen, so
                    // all we can do is take the user there. Dart re-checks
                    // canDrawOverlays when the app resumes.
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                            !Settings.canDrawOverlays(this)
                        ) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName"),
                                )
                            )
                        }
                        result.success(null)
                    }

                    // The bubble is shown only while the app is backgrounded —
                    // it would just cover the real counter otherwise. Dart
                    // drives this from its lifecycle callbacks.
                    "showOverlay" -> {
                        if (SalawatBuffer.quickTapEnabled(this)) OverlayService.start(this)
                        result.success(null)
                    }

                    "hideOverlay" -> {
                        OverlayService.stop(this)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
