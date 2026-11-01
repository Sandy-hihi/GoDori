import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/admin_order_screen.dart';
import 'services/admin_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // 패드는 켜질 때 손님(익명)으로 로그인. 지난번 관리자 로그인이 남아 있으면 여기서 정리됨
  await AdminSession.ensureGuest();
  runApp(const BoardPadApp());
}

class BoardPadApp extends StatelessWidget {
  const BoardPadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '보드패드',
      theme: ThemeData(
        fontFamily: 'Pretendard',
        scaffoldBackgroundColor: const Color(0xFF00B37E),
        // 손님 패드 기본 강조색(진행 표시·스위치·커서 등)을 메인 화면 주황으로
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE2711D)),
        // 화면 전환은 모두 애니메이션 없이 바로 (왼쪽 메뉴로 이동할 때와 같게).
        // 첫 화면 → 방 선택 → 홈, 일행과 함께 → 게임 목록 등 MaterialPageRoute로 여는 화면에 모두 적용
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _NoAnimationTransitions(),
            TargetPlatform.iOS: _NoAnimationTransitions(),
            TargetPlatform.windows: _NoAnimationTransitions(),
            TargetPlatform.macOS: _NoAnimationTransitions(),
            TargetPlatform.linux: _NoAnimationTransitions(),
            TargetPlatform.fuchsia: _NoAnimationTransitions(),
          },
        ),
      ),
      home: const RoleSelectionScreen(),
    );
  }
}

/// 화면 전환 효과 없음 (새 화면이 바로 보임)
class _NoAnimationTransitions extends PageTransitionsBuilder {
  const _NoAnimationTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  // 관리자 PIN 확인은 서버 함수가 함 (PIN은 앱에서 읽을 수 없음).
  // 맞으면 관리자 토큰으로 로그인 → 주문현황에서 상태 변경·삭제 가능
  Future<void> _showPinDialog(BuildContext context) async {
    final pinController = TextEditingController();
    bool isChecking = false;
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Future<void> submit() async {
            if (isChecking) return;
            final pin = pinController.text.trim();
            if (pin.isEmpty) return;
            setDlgState(() {
              isChecking = true;
              errorText = null;
            });
            try {
              await AdminSession.login(kind: 'pad', password: pin);
            } on AdminLoginException catch (e) {
              if (!ctx.mounted) return;
              setDlgState(() {
                isChecking = false;
                errorText = e.message;
              });
              pinController.clear();
              return;
            }
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (!context.mounted) return;
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrderScreen()));
            // 관리자 화면에서 나오면 다시 손님(익명) 상태로 — 패드에 관리자 권한이 남지 않게
            await AdminSession.ensureGuest();
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.lock, color: Color(0xFF1E2B3C)),
                SizedBox(width: 8),
                Text('관리자 인증', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('관리자 PIN을 입력하세요.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                TextField(
                  controller: pinController,
                  autofocus: true,
                  obscureText: true,
                  enabled: !isChecking,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 10,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '• • • • • •',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E2B3C), width: 2),
                    ),
                    errorText: errorText,
                    errorMaxLines: 2,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isChecking ? null : () => Navigator.pop(ctx),
                child: const Text('취소', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: isChecking ? null : submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E2B3C),
                  foregroundColor: Colors.white,
                ),
                child: isChecking
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                // 손님 패드는 익명 로그인 상태로 (혹시 관리자로 남아 있으면 로그아웃)
                await AdminSession.ensureGuest();
                if (!context.mounted) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(32),
                backgroundColor: const Color(0xFF00B37E),
                foregroundColor: Colors.white,
              ),
              child: const Text('손님용 패드 켜기', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 32),
            ElevatedButton(
              onPressed: () => _showPinDialog(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(32),
                backgroundColor: const Color(0xFF1E2B3C),
                foregroundColor: Colors.white,
              ),
              child: const Text('관리자 대시보드 켜기', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

