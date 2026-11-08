import 'package:flutter/material.dart';
import 'package:boardpad/services/translate_sync.dart';
import 'package:boardpad/widgets/store_brand.dart';

import 'admin_menu_manage_screen.dart';

import 'package:boardpad/services/admin_session.dart';

import 'admin_signup_screen.dart';

/// 관리자 웹 로그인 화면 (47차: 매장 아이디 + 비밀번호)
/// 비밀번호 확인은 서버 함수(/api/auth/login)가 합니다. 앱은 비밀번호를 읽을 수 없어요.
///   - stores/{매장}/private/account 의 관리자 웹 비밀번호, 없으면 관리자 PIN과 같은 값
///   - 관리자 웹 '매장 설정'에서 바꿀 수 있음
/// 로그인하면 그 매장 관리자 토큰이 브라우저에 남아서, 새로고침해도 다시 로그인하지 않아도 돼요.
/// (로그아웃은 왼쪽 메뉴 맨 아래)
class AdminWebLoginScreen extends StatefulWidget {
  const AdminWebLoginScreen({super.key});

  @override
  State<AdminWebLoginScreen> createState() => _AdminWebLoginScreenState();
}

class _AdminWebLoginScreenState extends State<AdminWebLoginScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _isChecking = false;
  String? _errorText;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _skipIfLoggedIn();
    AdminSession.loadPrefs(prefix: 'web.').then((p) {
      if (!mounted || _idController.text.isNotEmpty || p.storeId.isEmpty) {
        return;
      }
      _idController.text = p.storeId;
      _passwordFocus.requestFocus();
    });
  }

  // 이미 관리자로 로그인돼 있으면 바로 관리 화면으로
  Future<void> _skipIfLoggedIn() async {
    try {
      if (await AdminSession.isAdmin() && mounted) _goToAdmin();
    } on AdminLoginException catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    }
  }

  void _goToAdmin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const AdminMenuManageScreen(),
        transitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _login() async {
    if (_isChecking) return;
    final storeId = _idController.text.trim().toLowerCase();
    final input = _passwordController.text.trim();
    if (storeId.isEmpty || input.isEmpty) {
      setState(() => _errorText = '매장 아이디와 비밀번호를 입력하세요.');
      return;
    }
    setState(() {
      _isChecking = true;
      _errorText = null;
    });

    try {
      await AdminSession.webLogin(storeId: storeId, password: input);
      TranslateSync.kick(); // 83차: 번역이 빠진 메뉴·공지·이벤트 채우기 (처음 배포 뒤 이미 있던 글도)
      await AdminSession.savePrefs(storeId: storeId, prefix: 'web.');
    } on AdminLoginException catch (e) {
      if (!mounted) return;
      _passwordController.clear();
      setState(() {
        _isChecking = false;
        _errorText = e.message;
      });
      return;
    }
    if (!mounted) return;
    _goToAdmin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E2B3C),
      body: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const StoreLogo(size: 72, padding: EdgeInsets.only(bottom: 16)),
              const Text(
                '고도리 관리자',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                '매장 아이디와 관리자 비밀번호를 입력하세요',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _idController,
                autofocus: true,
                enabled: !_isChecking,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: InputDecoration(
                  labelText: '매장 아이디',
                  prefixIcon: const Icon(Icons.storefront_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                obscureText: true,
                enabled: !_isChecking,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  errorText: _errorText,
                  errorMaxLines: 3, // 서버·Firebase 오류 문구가 잘리지 않게
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E2B3C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '로그인',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '처음이신가요?',
                    style: TextStyle(color: Colors.black54),
                  ),
                  TextButton(
                    onPressed: _isChecking
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminSignupScreen(),
                              ),
                            );
                            // 가입 신청한 아이디를 로그인 칸에 채움
                            final p = await AdminSession.loadPrefs(
                              prefix: 'web.',
                            );
                            if (mounted && p.storeId.isNotEmpty) {
                              _idController.text = p.storeId;
                            }
                          },
                    child: const Text(
                      '회원가입',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
