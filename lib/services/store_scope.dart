import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// 지금 로그인한 매장 (47차 — 매장별 데이터)
///
/// 모든 매장 데이터는 Firestore stores/{매장ID}/… 아래에 있음
///   StoreScope.col('games')        → stores/{매장}/games
///   StoreScope.col('settings').doc('homeLayout') → stores/{매장}/settings/homeLayout
///   StoreScope.storage.child('menu_images/…')    → Storage stores/{매장}/menu_images/…
/// 로그인(AdminSession)할 때와 앱이 켜질 때 저장된 로그인을 불러올 때 매장이 정해짐.
class StoreScope {
  static String? _id;
  static String _name = '';

  /// 매장 아이디 (로그인 아이디). 로그인 전에 부르면 오류
  static String get id {
    final v = _id;
    if (v == null) throw StateError('매장 로그인 전에 매장 데이터를 읽으려 했어요.');
    return v;
  }

  static bool get isSet => _id != null;

  /// 매장 이름 (stores/{매장}.name, 없으면 빈 글자)
  static String get name => _name;

  static void set(String id, {String? name}) {
    _id = id;
    if (name != null) _name = name;
  }

  static void clear() {
    _id = null;
    _name = '';
  }

  static DocumentReference<Map<String, dynamic>> get doc =>
      FirebaseFirestore.instance.collection('stores').doc(id);

  static CollectionReference<Map<String, dynamic>> col(String name) => doc.collection(name);

  /// Storage에서 이 매장 폴더
  static Reference get storage => FirebaseStorage.instance.ref().child('stores/$id');
}
