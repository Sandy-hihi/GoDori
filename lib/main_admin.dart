import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // 파이어베이스 설정 파일
import 'screens/admin_web_login_screen.dart';

void main() async {
  // 플러터 엔진이 초기화될 때까지 기다림 (비동기 작업 시 필수)
  WidgetsFlutterBinding.ensureInitialized();
  
  // 💡 파이어베이스 초기화 (이게 없으면 웹에서 JavaScriptObject 에러가 납니다!)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 운영자 페이지는 49차부터 따로: lib/main_ops.dart → https://godori-ops.web.app (관리자 웹 빌드에는 안 들어감)
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '고도리 관리자 웹',
    // 앱에 넣어 둔 한글 글꼴(Pretendard) — 없으면 브라우저가 한글 글꼴을 늦게 받아 와서
    // 처음 잰 폭보다 글자가 넓어져 칩·버튼 글자가 잘림 (53차: 메뉴 카테고리 '전체'가 '전'으로 보이던 문제)
    theme: ThemeData(fontFamily: 'Pretendard'),
    home: const AdminWebLoginScreen(), // 로그인 후 메뉴 관리 화면으로 이동
  ));
}