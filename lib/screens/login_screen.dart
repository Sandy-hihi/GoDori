import 'package:flutter/material.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E2B3C),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.casino, size: 80, color: Color(0xFF00B37E)),
            const SizedBox(height: 24),
            const Text('이용하실 방 번호를 선택해주세요', style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            SizedBox(
              width: 600,
              child: Wrap(
                spacing: 16, runSpacing: 16, alignment: WrapAlignment.center,
                children: List.generate(11, (index) {
                  final roomNum = index + 1;
                  return ElevatedButton(
                    onPressed: () {
                      // 선택한 방 번호를 메인 화면으로 전달하며 화면 교체
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => DashboardScreen(roomNumber: roomNum)),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      backgroundColor: const Color(0xFF00B37E),
                    ),
                    child: Text('$roomNum번 방', style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}