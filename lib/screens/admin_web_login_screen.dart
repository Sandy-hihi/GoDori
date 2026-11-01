import 'package:flutter/material.dart';
import 'package:boardpad/widgets/store_brand.dart';
import 'admin_menu_manage_screen.dart';
import 'package:boardpad/services/admin_session.dart';

/// 관리자 웹 로그인 화면
/// 비밀번호 확인은 서버 함수(/api/auth/login)가 합니다. 앱은 비밀번호를 읽을 수 없어요.
///   - Firestore settings/adminPin 의 'webPassword' 필드가 있으면 그 값
///   - 없으면 태블릿 관리자 PIN('pin' 필드)과 같은 값
/// 로그인하면 Firebase 관리자 토큰이 브라우저에 남아서, 새로고침해도 다시 로그인하지 않아도 돼요.
/// (로그아웃은 왼쪽 메뉴 맨 아래)
class AdminWebLoginScreen extends StatefulWidget {
  const AdminWebLoginScreen({super.key});

  @override
  State<AdminWebLoginScreen> createState() => _AdminWebLoginScreenState();
}

class _AdminWebLoginScreenState extends State<AdminWebLoginScreen> {
  final _passwordController = TextEditingController();
  bool _isChecking = false;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _skipIfLoggedIn();
  }

  // 이미 관리자로 로그인돼 있으면 바로 관리 화면으로
  Future<void> _skipIfLoggedIn() async {
    if (await AdminSession.isAdmin() && mounted) _goToAdmin();
  }

  void _goToAdmin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AdminMenuManageScreen(),
        transitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _login() async {
    if (_isChecking) return;
    final input = _passwordController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorText = '비밀번호를 입력하세요.');
      return;
    }
    setState(() {
      _isChecking = true;
      _errorText = null;
    });

    try {
      await AdminSession.login(kind: 'web', password: input);
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
              StoreLogo(size: 72),
              const SizedBox(height: 16),
              const Text('고도리 관리자', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('관리자 비밀번호를 입력하세요', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                autofocus: true,
                obscureText: true,
                enabled: !_isChecking,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isChecking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('로그인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
