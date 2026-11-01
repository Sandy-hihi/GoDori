import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/admin_order_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
  // PIN은 Firestore settings/adminPin 문서의 'pin' 필드에서만 가져옴
  // (공개 저장소에 노출되지 않도록 코드에는 기본 PIN을 두지 않음)
  // 문서가 없거나 읽기에 실패하면 null → 관리자 진입 불가
  Future<String?> _fetchPin() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('adminPin')
          .get();
      final pin = doc.data()?['pin']?.toString();
      if (pin != null && pin.isNotEmpty) return pin;
    } catch (_) {}
    return null;
  }

  Future<void> _showPinDialog(BuildContext context) async {
    final pinController = TextEditingController();
    bool isWrong = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
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
                  errorText: isWrong ? 'PIN이 올바르지 않습니다.' : null,
                ),
                onSubmitted: (_) async {
                  final correctPin = await _fetchPin();
                  if (correctPin != null && pinController.text == correctPin) {
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      if (context.mounted) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrderScreen()));
                      }
                    }
                  } else {
                    setDlgState(() => isWrong = true);
                    pinController.clear();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final correctPin = await _fetchPin();
                if (correctPin != null && pinController.text == correctPin) {
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    if (context.mounted) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrderScreen()));
                    }
                  }
                } else {
                  setDlgState(() => isWrong = true);
                  pinController.clear();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E2B3C),
                foregroundColor: Colors.white,
              ),
              child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
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

