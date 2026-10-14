import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_menu_manage_screen.dart';
import 'package:boardpad/services/admin_session.dart';

/// 관리자 웹 로그인 화면
/// 비밀번호는 Firestore settings/adminPin 문서에서 읽어옵니다.
///   - 'webPassword' 필드가 있으면 그 값을 사용
///   - 없으면 태블릿 관리자 PIN('pin' 필드)과 같은 값을 사용
/// 코드에는 비밀번호를 두지 않습니다. (공개 저장소 노출 방지)
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

  Future<String?> _fetchPassword() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('adminPin').get();
      final data = doc.data();
      final web = data?['webPassword']?.toString();
      if (web != null && web.isNotEmpty) return web;
      final pin = data?['pin']?.toString();
      if (pin != null && pin.isNotEmpty) return pin;
    } catch (e) {
      debugPrint('Admin password fetch error: $e');
    }
    return null;
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

    final correct = await _fetchPassword();
    if (!mounted) return;

    if (correct == null) {
      setState(() {
        _isChecking = false;
        _errorText = '비밀번호 설정을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
      return;
    }

    if (input == correct) {
      AdminSession.password = input; // BGG 조회 서버에 보낼 때 사용 (앱 메모리에만 보관)
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const AdminMenuManageScreen(),
          transitionDuration: Duration.zero,
        ),
      );
    } else {
      _passwordController.clear();
      setState(() {
        _isChecking = false;
        _errorText = '비밀번호가 올바르지 않습니다.';
      });
    }
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
              ClipOval(
                child: Image.asset('assets/images/logo.jpg', width: 72, height: 72, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              const Text('보드패드 관리자', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
