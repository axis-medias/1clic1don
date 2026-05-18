package fr.u1clic1don.clic_1_don

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import androidx.core.view.WindowCompat

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // ✅ IMPORTANT : Appeler WindowCompat AVANT super.onCreate()
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }
}