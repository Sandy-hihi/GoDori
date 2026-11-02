import 'package:flutter/material.dart';
import 'package:boardpad/services/room_settings_service.dart';
import 'dashboard_screen.dart';
import '../widgets/pad_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 방 개수는 관리자 웹 "매장 설정"에서 정함 (settings/rooms)
  late final Stream<int> _roomCount = RoomSettingsService.watchCount();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E2B3C),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.casino, size: 80, color: Color(0xFF00B37E)),
              const SizedBox(height: 24),
              const Text('이용하실 방 번호를 선택해주세요',
                  style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              StreamBuilder<int>(
                stream: _roomCount,
                initialData: RoomSettingsService.defaultCount,
                builder: (context, snapshot) {
                  final count = snapshot.data ?? RoomSettingsService.defaultCount;
                  return SizedBox(
                    width: 600,
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: List.generate(count, (index) {
                        final roomNum = index + 1;
                        return ElevatedButton(
                          onPressed: () {
                            // 선택한 방 번호를 메인 화면으로 전달하며 화면 교체
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                settings: const RouteSettings(name: PadShell.homeRouteName),
                                builder: (context) => DashboardScreen(roomNumber: roomNum),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                            backgroundColor: const Color(0xFF00B37E),
                          ),
                          child: Text('$roomNum번 방',
                              style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                        );
                      }),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
