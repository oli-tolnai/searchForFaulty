package hu.consoledealfinder.flutter_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.provider.Settings

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hu.consoledealfinder/settings")
            .setMethodCallHandler { call, result ->
                if (call.method != "openAppSettings") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                startActivity(intent)
                result.success(null)
            }
    }
}
