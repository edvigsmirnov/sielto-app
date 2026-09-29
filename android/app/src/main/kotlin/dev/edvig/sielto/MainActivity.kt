package dev.edvig.sielto

import android.os.Bundle
import android.view.View
import android.view.ViewTreeObserver
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var flutterDrawn = false

    // Holds the system splash until Flutter has drawn its first frame, which
    // repeats the splash, so the handoff is invisible instead of fading to a
    // bare background first.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        flutterDrawn = true
        findViewById<View>(android.R.id.content).invalidate()
    }
}
