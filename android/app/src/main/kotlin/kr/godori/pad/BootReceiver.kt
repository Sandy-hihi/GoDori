package kr.godori.pad

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 141차: 태블릿이 켜지면 고도리를 자동으로 띄움. (142차: 관리자 웹에서 켠 매장만)
 *
 * 매장 운영 방식(사용자 결정 B): 태블릿 자체의 '예약 전원 켜기/끄기'로 마감 때 꺼지고 오픈 때 켜짐
 * → 켜질 때 이 리시버가 고도리를 실행. (일반 앱은 태블릿 전원을 끄거나 켤 수 없음)
 *
 * 안드로이드 10 이상은 백그라운드에서 화면을 띄우는 걸 막으므로 태블릿마다 한 번 아래 중 하나를 해 둠:
 *  - 설정 > 앱 > 고도리 > '다른 앱 위에 표시' 허용 (SYSTEM_ALERT_WINDOW — 이걸 켜면 여기서 띄우는 게 허용됨)
 *  - 또는 고도리를 '기본 홈 앱'으로 (켜지면 시스템이 홈 앱으로 바로 띄움 — 이 리시버 없이도 됨)
 * 안드로이드 9 이하는 따로 설정 없이 됨.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) return
        // 142차: 관리자 웹 '매장 설정 > 태블릿 자동 실행'을 켠 매장만 (기본 꺼짐 — 패드가 로그인해 있을 때 받아 저장해 둔 값)
        if (!DeviceSettings.autoLaunch(context)) return
        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        }
        try {
            context.startActivity(launch)
        } catch (e: Exception) {
            // 권한이 없어 막혀도 앱이 죽지 않게 — 그땐 직원이 아이콘을 눌러 켬
            Log.w("GodoriBoot", "자동 실행 실패: $e")
        }
    }
}
