import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:boardpad/services/store_scope.dart';

/// 번역 고침표 (120차) — 관리자 웹 '번역 관리'에서 사장님이 직접 고친 번역
///
/// 저장: stores/{매장}/settings/translationOverrides = { items: [{ src: 원문, en?, zh?, ja? }], updatedAt }
/// - 서버 자동 번역(functions/src/translate.js makeFixed)이 고정 번역표(GLOSSARY)처럼 씀:
///   같은 원문이 쓰인 모든 곳(메뉴 이름·옵션·카테고리·공지·이벤트)에 들어가고, 비운 언어는 자동 번역 그대로
/// - 고친 뒤 TranslateSync.kick() → 서버가 각 문서의 translations에 넣음(손님 패드는 그걸 읽음)
/// - 고침을 지우면 다음 번역 때 자동 번역으로 되돌아감
/// - 원문 비교는 띄어쓰기 무시, '뗴'는 '떼' (서버 glossKey와 같게)
/// - 쓰기는 관리자만(firestore.rules settings 쓰기 목록 'translationOverrides')
class TranslationOverrides {
  static const langs = ['en', 'zh', 'ja'];
  static const maxItems = 1000; // 서버 MAX_OVERRIDES와 같게

  static DocumentReference<Map<String, dynamic>> get _doc =>
      StoreScope.col('settings').doc('translationOverrides');

  static String keyOf(String s) => s.trim().replaceAll(RegExp(r'\s+'), '').replaceAll('뗴', '떼');

  /// 원문 키 → { src, en?, zh?, ja? }
  static Map<String, Map<String, String>> parse(Map<String, dynamic>? data) {
    final out = <String, Map<String, String>>{};
    final items = data?['items'];
    if (items is! List) return out;
    for (final it in items) {
      if (it is! Map) continue;
      final src = (it['src'] ?? '').toString().trim();
      if (keyOf(src).isEmpty) continue;
      final m = <String, String>{'src': src};
      for (final c in langs) {
        final v = (it[c] ?? '').toString().trim();
        if (v.isNotEmpty) m[c] = v;
      }
      if (m.length > 1) out[keyOf(src)] = m;
    }
    return out;
  }

  static Future<Map<String, Map<String, String>>> load() async => parse((await _doc.get()).data());

  /// 한 원문의 고침 저장. values의 빈 언어는 저장 안 함(자동 번역). 모두 비면 그 고침을 지움
  static Future<void> save(String src, Map<String, String> values) async {
    final key = keyOf(src);
    if (key.isEmpty) return;
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_doc);
      final items = parse(snap.data());
      final m = <String, String>{'src': src.trim()};
      for (final c in langs) {
        final v = (values[c] ?? '').trim();
        if (v.isNotEmpty) m[c] = v;
      }
      if (m.length > 1) {
        items[key] = m;
      } else {
        items.remove(key);
      }
      if (items.length > maxItems) throw StateError('고친 번역은 $maxItems개까지예요. 안 쓰는 고침을 지워 주세요.');
      tx.set(_doc, {'items': items.values.toList(), 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  static Future<void> remove(String src) => save(src, const {});
}
