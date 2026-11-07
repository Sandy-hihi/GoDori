import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:boardpad/l10n/guest_language.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/admin_session.dart';
import 'widgets/order_ready_overlay.dart';
import 'widgets/pad_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GuestLanguage.instance.load();
  runApp(const GodoriApp());
}

class GodoriApp extends StatelessWidget {
  const GodoriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GuestLanguage.instance,
      builder: (context, _) => MaterialApp(
      locale: Locale(GuestLanguage.instance.code),
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh'), Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      title: '고도리',
      theme: ThemeData(
        fontFamily: 'Pretendard',
        scaffoldBackgroundColor: const Color(0xFF00B37E),
        // 손님 패드 기본 강조색(진행 표시·스위치·커서 등)을 메인 화면 주황으로
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE2711D)),
        // 화면 전환은 모두 애니메이션 없이 바로 (왼쪽 메뉴로 이동할 때와 같게).
        // 로그인 → 홈, 일행과 함께 → 게임 목록 등 MaterialPageRoute로 여는 화면에 모두 적용
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
      // 카운터 수령 매장: 주문한 음식이 준비되면 어느 화면에서든 알림 (58차)
      builder: (context, child) =>
          GuestLocaleScope(child: OrderReadyOverlay(child: child ?? const SizedBox.shrink())),
      home: const StartupScreen(),
    ));
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
  ) => child;
}

/// 앱이 켜질 때: 저장된 로그인이 있고 '자동 로그인'이 켜져 있으면 바로 그 방 홈(또는 관리자 대시보드),
/// 아니면 로그인 화면 (47차)
class StartupScreen extends StatefulWidget {
  final Future<PadSession?> Function() restoreSession;
  const StartupScreen({super.key, this.restoreSession = AdminSession.restore});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  String? _restoreError;
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    setState(() => _restoreError = null);
    PadSession? session;
    try {
      session = await widget.restoreSession();
    } on AdminLoginException catch (e) {
      if (mounted) setState(() => _restoreError = e.message);
      return;
    }
    final prefs = await AdminSession.loadPrefs();
    if (!mounted) return;
    Widget next;
    if (session != null && prefs.autoLogin && !session.isAdmin) {
      next = DashboardScreen(roomNumber: session.room);
    } else if (session != null && prefs.autoLogin && session.isAdmin) {
      next = const LoginScreen(openAdmin: true);
    } else {
      // 자동 로그인을 끈 채 남아 있던 로그인은 정리 (다음 사람이 비밀번호 없이 들어가지 않게)
      if (session != null) await AdminSession.signOut();
      next = const LoginScreen();
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        settings: next is DashboardScreen
            ? const RouteSettings(name: PadShell.homeRouteName)
            : null,
        builder: (_) => next,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _restoreError;
    return Scaffold(
      backgroundColor: const Color(0xFF1E2B3C),
      body: Center(
        child: error == null
            ? const CircularProgressIndicator(color: Colors.white)
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _decide,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
