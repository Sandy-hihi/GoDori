import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'ops/ops_app.dart';

/// 운영자 페이지 (49차부터 따로 빌드·따로 사이트) — https://godori-ops.web.app
/// 빌드: flutter build web --release -t lib/main_ops.dart --output build/ops  ("BoardPad 배포.bat" 1번이 같이 함)
/// 실행(개발): "BoardPad 실행.bat" 5번
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const OpsApp());
}
