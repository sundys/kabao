package com.sundys.kabao

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity is required by local_auth to show the system
// biometric prompt (BiometricPrompt API).
class MainActivity : FlutterFragmentActivity() {
    private val timezoneChannel = "com.sundys.kabao/device_timezone"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            timezoneChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "getTimeZoneName") {
                result.success(java.util.TimeZone.getDefault().id)
            } else {
                result.notImplemented()
            }
        }
    }
}
