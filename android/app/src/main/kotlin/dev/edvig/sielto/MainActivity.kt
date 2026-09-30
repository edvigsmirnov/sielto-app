package dev.edvig.sielto

import android.os.Bundle
import android.view.View
import android.view.ViewTreeObserver
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel

// A FragmentActivity for local_auth's biometric prompt.
class MainActivity : FlutterFragmentActivity(), FlutterUiDisplayListener {
    private var flutterDrawn = false

    // Holds the system splash until Flutter has drawn its first frame, which
    // repeats the splash, so the handoff is invisible instead of fading to a
    // bare background first.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Secure until Dart reads the setting, so the first recents
        // thumbnail is blank too.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val content = findViewById<View>(android.R.id.content)
        content.viewTreeObserver.addOnPreDrawListener(
            object : ViewTreeObserver.OnPreDrawListener {
                override fun onPreDraw(): Boolean {
                    if (!flutterDrawn) return false
                    content.viewTreeObserver.removeOnPreDrawListener(this)
                    return true
                }
            },
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sielto/window")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    if (call.arguments as Boolean) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onFlutterUiDisplayed() {
        flutterDrawn = true
        findViewById<View>(android.R.id.content).invalidate()
    }

    override fun onFlutterUiNoLongerDisplayed() {}
}
