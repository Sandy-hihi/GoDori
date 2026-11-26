import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'stock/stock_app.dart';

/// 고도리 재고 앱 (148차) — 직원 휴대폰용 (안드로이드·iOS)
///   켜기:  flutter run -t lib/main_stock.dart  (크롬으로 볼 땐 -d chrome)
///   APK:   flutter build apk -t lib/main_stock.dart -P godoriApp=stock
///          → 앱 ID kr.godori.stock · 이름 '고도리 재고' (android/app/build.gradle.kts — 패드 앱 kr.godori.pad와 따로 깔림)
///   iOS:   맥(Xcode)에서 flutter build ios -t lib/main_stock.dart (번들 ID는 Xcode에서 따로 정해야 함)
/// 화면·로그인은 lib/stock/stock_app.dart, 데이터는 lib/services/stock_service.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const StockApp());
}
