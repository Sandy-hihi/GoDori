package kr.godori.pad

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // 142차: 관리자 웹 '매장 설정 > 태블릿 자동 실행' 값을 태블릿에 저장 (lib/services/pad_device_service.dart)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DeviceSettings.CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAutoLaunch" -> {
                    DeviceSettings.setAutoLaunch(this, call.argument<Boolean>("on") == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}

/** 142차: 태블릿에 저장하는 고도리 설정 — BootReceiver.kt가 켜질 때 읽음 */
object DeviceSettings {
    const val CHANNEL = "kr.godori.pad/device"
    private const val PREFS = "godori_device"
    private const val KEY_AUTO_LAUNCH = "autoLaunch"

    fun autoLaunch(context: android.content.Context): Boolean =
        context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE).getBoolean(KEY_AUTO_LAUNCH, false)

    fun setAutoLaunch(context: android.content.Context, on: Boolean) {
        context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_AUTO_LAUNCH, on).apply()
        // 켜면 고도리를 '기본 홈 앱'으로 고를 수 있게(HomeAlias), 끄면 홈 앱 후보에서 빠짐
        // (이미 기본 홈 앱이었으면 태블릿이 원래 홈 앱으로 돌아감)
        context.packageManager.setComponentEnabledSetting(
            ComponentName(context, "kr.godori.pad.HomeAlias"),
            if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
