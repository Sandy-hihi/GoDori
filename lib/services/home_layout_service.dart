import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/models/home_layout.dart';

/// 홈 화면 배치 읽기·저장 (Firestore settings/homeLayout)
class HomeLayoutService {
  static DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('settings').doc('homeLayout');

  /// 손님 패드: 사장님이 저장하면 바로 바뀜. 문서가 없거나 잘못됐으면 기본 배치
  static Stream<HomeLayout> watch() => _doc
      .snapshots()
      .map((snap) => HomeLayout.fromMap(snap.data()) ?? HomeLayout.defaults())
      .handleError((_) {});

  /// 관리자 편집 화면: 한 번 읽기
  static Future<HomeLayout> load() async {
    try {
      final snap = await _doc.get();
      return HomeLayout.fromMap(snap.data()) ?? HomeLayout.defaults();
    } catch (_) {
      return HomeLayout.defaults();
    }
  }

  static Future<void> save(HomeLayout layout) {
    return _doc.set({...layout.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
  }
}
