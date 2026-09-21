import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // 파이어베이스 설정 파일
import 'screens/admin_menu_manage_screen.dart';

void main() async {
  // 플러터 엔진이 초기화될 때까지 기다림 (비동기 작업 시 필수)
  WidgetsFlutterBinding.ensureInitialized();
  
  // 💡 파이어베이스 초기화 (이게 없으면 웹에서 JavaScriptObject 에러가 납니다!)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '보드패드 관리자 웹',
    home: AdminMenuManageScreen(),
  ));
}