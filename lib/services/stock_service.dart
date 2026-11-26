import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/services/store_scope.dart';

/// 재고관리 (148차) — 관리자 웹 '재고관리' 탭과 휴대폰 재고 앱(lib/stock/, main_stock.dart)이 같이 씀
///
/// Firestore (매장마다, 보안 규칙은 firestore.rules '재고관리' — 신청한 매장(features.stock)만)
///   stores/{매장}/stock_items/{id}  = { name, category, unit, order, minQty?, active, memo, createdAt, updatedAt }
///        사장님이 관리자 웹에서 만들고 고침. 재고 앱은 읽기만
///   stores/{매장}/stock_counts/{id} = { title, status 'open'|'done', counts { 항목ID: 숫자 }, items { 항목ID: {name, category, unit, minQty} },
///                                       counter(센 사람 이름), startedBy 'owner'|'staff', startedAt, updatedAt, finishedAt, note, itemCount }
///        재고 앱에서 '재고 조사 시작' → 항목마다 숫자를 넣으면 바로 counts.{항목ID}에 저장(인터넷이 끊겨도 휴대폰에 모았다가 올림)
///        → '조사 끝내기'면 status 'done' + 그때 항목 이름·단위(items)를 같이 저장(나중에 항목 이름을 바꾸거나 지워도 기록은 그대로)
class StockItem {
  final String id;
  final String name;
  final String category;
  final String unit;
  final int order;
  final num? minQty; // 적정 재고(이보다 적으면 '부족') — 없으면 표시 안 함
  final bool active; // false = 숨김(재고 앱에 안 나옴)
  final String memo;

  const StockItem({
    required this.id,
    required this.name,
    this.category = '',
    this.unit = '개',
    this.order = 0,
    this.minQty,
    this.active = true,
    this.memo = '',
  });

  factory StockItem.fromMap(String id, Map<String, dynamic> d) => StockItem(
        id: id,
        name: (d['name'] ?? '').toString(),
        category: (d['category'] ?? '').toString().trim(),
        unit: (d['unit'] ?? '').toString().trim().isEmpty ? '개' : d['unit'].toString().trim(),
        order: d['order'] is num ? (d['order'] as num).toInt() : 0,
        minQty: d['minQty'] is num ? d['minQty'] as num : null,
        active: d['active'] is bool ? d['active'] as bool : true,
        memo: (d['memo'] ?? '').toString(),
      );

  /// 조사 기록(stock_counts.items)에 남길 모양
  Map<String, dynamic> snapshot() => {
        'name': name,
        'category': category,
        'unit': unit,
        if (minQty != null) 'minQty': minQty,
      };

  String get categoryLabel => category.isEmpty ? '기타' : category;
}

class StockCount {
  final String id;
  final String title;
  final String status; // 'open' | 'done'
  final Map<String, num> counts;
  final Map<String, Map<String, dynamic>> items; // 끝낼 때 저장한 항목 이름·단위
  final String counter;
  final String startedBy;
  final String note;
  final int itemCount;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final DateTime? finishedAt;
  final bool pending; // 휴대폰에만 있고 아직 서버에 안 올라감(인터넷 끊김)

  const StockCount({
    required this.id,
    required this.title,
    required this.status,
    required this.counts,
    this.items = const {},
    this.counter = '',
    this.startedBy = '',
    this.note = '',
    this.itemCount = 0,
    this.startedAt,
    this.updatedAt,
    this.finishedAt,
    this.pending = false,
  });

  bool get isOpen => status != 'done';

  factory StockCount.fromMap(String id, Map<String, dynamic> d, {bool pending = false}) {
    DateTime? t(Object? v) => v is Timestamp ? v.toDate() : null;
    final counts = <String, num>{};
    final rawCounts = d['counts'];
    if (rawCounts is Map) {
      rawCounts.forEach((k, v) {
        if (v is num) counts[k.toString()] = v;
      });
    }
    final items = <String, Map<String, dynamic>>{};
    final rawItems = d['items'];
    if (rawItems is Map) {
      rawItems.forEach((k, v) {
        if (v is Map) items[k.toString()] = Map<String, dynamic>.from(v);
      });
    }
    return StockCount(
      id: id,
      title: (d['title'] ?? '').toString(),
      status: d['status'] == 'done' ? 'done' : 'open',
      counts: counts,
      items: items,
      counter: (d['counter'] ?? '').toString(),
      startedBy: (d['startedBy'] ?? '').toString(),
      note: (d['note'] ?? '').toString(),
      itemCount: d['itemCount'] is num ? (d['itemCount'] as num).toInt() : 0,
      startedAt: t(d['startedAt']),
      updatedAt: t(d['updatedAt']),
      finishedAt: t(d['finishedAt']),
      pending: pending,
    );
  }

  /// 이 기록에서 항목 이름 (끝낼 때 저장한 이름 → 없으면 지금 항목 → 없으면 '지운 항목')
  String nameOf(String itemId, Map<String, StockItem> live) =>
      (items[itemId]?['name'] ?? live[itemId]?.name ?? '지운 항목').toString();
  String unitOf(String itemId, Map<String, StockItem> live) =>
      (items[itemId]?['unit'] ?? live[itemId]?.unit ?? '').toString();
}

// ── 화면 없는 계산 (test/stock_test.dart) ──

/// 순서(order) → 이름 순으로 정렬
List<StockItem> sortStockItems(Iterable<StockItem> items) {
  final list = items.toList();
  list.sort((a, b) {
    final c = a.order.compareTo(b.order);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return list;
}

/// 카테고리별로 묶기 — 카테고리 순서는 그 카테고리의 첫 항목 순서
List<MapEntry<String, List<StockItem>>> groupStockItems(Iterable<StockItem> items) {
  final out = <String, List<StockItem>>{};
  for (final it in sortStockItems(items)) {
    out.putIfAbsent(it.categoryLabel, () => []).add(it);
  }
  return out.entries.toList();
}

/// 숫자 보기 좋게: 3.0 → '3', 2.5 → '2.5', 1234 → '1,234'
String stockNum(num? v) {
  if (v == null) return '-';
  final isInt = v == v.roundToDouble();
  final s = isInt ? v.toInt().abs().toString() : v.abs().toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = s.split('.');
  final b = StringBuffer();
  final head = parts[0];
  for (var i = 0; i < head.length; i++) {
    if (i > 0 && (head.length - i) % 3 == 0) b.write(',');
    b.write(head[i]);
  }
  if (parts.length > 1) b.write('.${parts[1]}');
  return '${v < 0 ? '-' : ''}$b';
}

/// 직전 대비 글자: +3 / -2 / 0 / 이번에 처음이면 null
String? stockDiffText(num? now, num? before) {
  if (now == null || before == null) return null;
  final d = now - before;
  if (d == 0) return '0';
  return d > 0 ? '+${stockNum(d)}' : stockNum(d);
}

/// 적정 재고보다 적은지 (적정 재고가 없거나 아직 안 셌으면 false)
bool stockLow(num? value, num? minQty) => value != null && minQty != null && value < minQty;

/// 입력 글자 → 숫자 (빈칸 null, 음수·글자·너무 큰 수는 오류로 null + ok=false)
({num? value, bool ok}) parseStockInput(String raw) {
  var s = raw.trim().replaceAll(',', '');
  if (s.isEmpty) return (value: null, ok: true);
  // '3.'처럼 점으로 끝나도 됨(키패드로 소수를 쓰는 중)
  if (!RegExp(r'^\d{1,7}(\.\d{0,2})?$').hasMatch(s)) return (value: null, ok: false);
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  final v = num.parse(s);
  return (value: v == v.roundToDouble() ? v.toInt() : v, ok: true);
}

/// 조사 제목: '11월 24일 (화) 재고 조사'
String stockCountTitle(DateTime t) {
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  return '${t.month}월 ${t.day}일 (${days[t.weekday - 1]}) 재고 조사';
}

/// '11/24 14:05'
String stockTime(DateTime? t) {
  if (t == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}';
}

/// [count] 바로 앞의 끝난 조사 (counts는 최근 것부터 정렬돼 있어야 함)
StockCount? previousDoneCount(List<StockCount> recentFirst, StockCount count) {
  final i = recentFirst.indexWhere((c) => c.id == count.id);
  for (var j = (i < 0 ? 0 : i + 1); j < recentFirst.length; j++) {
    final c = recentFirst[j];
    if (c.id != count.id && !c.isOpen) return c;
  }
  return null;
}

/// 엑셀·구글 시트에 붙여넣을 글(탭으로 칸 나눔): 카테고리 · 항목 · 단위 · 수량 · 적정 재고 · 직전 · 차이
String stockCountTable(StockCount count, List<StockItem> liveItems, {StockCount? previous}) {
  final live = {for (final it in liveItems) it.id: it};
  // 기록에 있는 항목(끝낸 때 이름) + 지금 항목 중 기록에 없는 것
  final ids = <String>[
    ...sortStockItems(liveItems).map((e) => e.id),
    ...count.items.keys.where((k) => !live.containsKey(k)),
    ...count.counts.keys.where((k) => !live.containsKey(k) && !count.items.containsKey(k)),
  ];
  final b = StringBuffer('카테고리\t항목\t단위\t수량\t적정 재고\t직전\t차이\n');
  for (final id in ids) {
    if (!count.counts.containsKey(id) && !count.items.containsKey(id) && !(live[id]?.active ?? false)) continue;
    final snap = count.items[id];
    final cat = (snap?['category'] ?? live[id]?.category ?? '').toString();
    final min = snap?['minQty'] is num ? snap!['minQty'] as num : live[id]?.minQty;
    final v = count.counts[id];
    final p = previous?.counts[id];
    b.writeln([
      cat.isEmpty ? '기타' : cat,
      count.nameOf(id, live),
      count.unitOf(id, live),
      v == null ? '' : '$v',
      min == null ? '' : '$min',
      p == null ? '' : '$p',
      stockDiffText(v, p) ?? '',
    ].join('\t'));
  }
  return b.toString();
}

/// '한꺼번에 추가' 글 읽기 (메뉴 한꺼번에 추가(99차)와 비슷하게)
///   # 음료            ← 카테고리
///   콜라 | 캔 | 24     ← 이름 | 단위(선택) | 적정 재고(선택)
///   // 메모           ← 무시
List<({String name, String category, String unit, num? minQty})> parseStockBulk(String text) {
  final out = <({String name, String category, String unit, num? minQty})>[];
  var category = '';
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('//')) continue;
    if (line.startsWith('#')) {
      category = line.substring(1).trim();
      continue;
    }
    final parts = line.split('|').map((e) => e.trim()).toList();
    final name = parts[0];
    if (name.isEmpty || name.length > 60) continue;
    final unit = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : '개';
    final min = parts.length > 2 ? parseStockInput(parts[2]).value : null;
    out.add((name: name, category: category, unit: unit.length > 10 ? unit.substring(0, 10) : unit, minQty: min));
  }
  return out;
}

class StockService {
  static CollectionReference<Map<String, dynamic>> get _items => StoreScope.col('stock_items');
  static CollectionReference<Map<String, dynamic>> get _counts => StoreScope.col('stock_counts');

  /// 재고 항목 (순서대로). [activeOnly]면 숨긴 항목 빼고
  static Stream<List<StockItem>> watchItems({bool activeOnly = false}) => _items.snapshots().map((s) {
        final list = sortStockItems(s.docs.map((d) => StockItem.fromMap(d.id, d.data())));
        return activeOnly ? list.where((e) => e.active).toList() : list;
      });

  static Future<List<StockItem>> loadItems({bool activeOnly = false}) async {
    final s = await _items.get();
    final list = sortStockItems(s.docs.map((d) => StockItem.fromMap(d.id, d.data())));
    return activeOnly ? list.where((e) => e.active).toList() : list;
  }

  /// 항목 저장 (id가 null이면 새로 — 맨 뒤 순서)
  static Future<void> saveItem({
    String? id,
    required String name,
    required String category,
    required String unit,
    num? minQty,
    bool active = true,
    String memo = '',
    int? order,
  }) async {
    final data = <String, dynamic>{
      'name': name.trim(),
      'category': category.trim(),
      'unit': unit.trim().isEmpty ? '개' : unit.trim(),
      'minQty': minQty,
      'active': active,
      'memo': memo.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (id == null) {
      data['order'] = order ?? await _nextOrder();
      data['createdAt'] = FieldValue.serverTimestamp();
      await _items.add(data);
    } else {
      if (order != null) data['order'] = order;
      await _items.doc(id).update(data);
    }
  }

  static Future<int> _nextOrder() async {
    final s = await _items.orderBy('order', descending: true).limit(1).get();
    if (s.docs.isEmpty) return 10;
    final o = s.docs.first.data()['order'];
    return (o is num ? o.toInt() : 0) + 10;
  }

  /// 한꺼번에 추가 — 같은 이름(같은 카테고리)은 건너뜀. 추가한 개수
  static Future<int> addMany(List<({String name, String category, String unit, num? minQty})> rows, List<StockItem> existing) async {
    final have = {for (final e in existing) '${e.category}\u0000${e.name}'};
    var order = await _nextOrder();
    var batch = FirebaseFirestore.instance.batch();
    var n = 0, inBatch = 0;
    for (final r in rows) {
      final key = '${r.category}\u0000${r.name}';
      if (!have.add(key)) continue;
      batch.set(_items.doc(), {
        'name': r.name,
        'category': r.category,
        'unit': r.unit,
        'minQty': r.minQty,
        'active': true,
        'memo': '',
        'order': order,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      order += 10;
      n++;
      if (++inBatch >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        inBatch = 0;
      }
    }
    if (inBatch > 0) await batch.commit();
    return n;
  }

  static Future<void> deleteItem(String id) => _items.doc(id).delete();

  /// 두 항목 순서 바꾸기 (↑↓)
  static Future<void> swapOrder(StockItem a, StockItem b) async {
    final batch = FirebaseFirestore.instance.batch();
    var oa = a.order, ob = b.order;
    if (oa == ob) ob = oa + 1;
    batch.update(_items.doc(a.id), {'order': ob, 'updatedAt': FieldValue.serverTimestamp()});
    batch.update(_items.doc(b.id), {'order': oa, 'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  /// 최근 재고 조사 (최근 것부터)
  static Stream<List<StockCount>> watchCounts({int limit = 30}) => _counts
      .orderBy('startedAt', descending: true)
      .limit(limit)
      .snapshots(includeMetadataChanges: true)
      .map((s) => [
            for (final d in s.docs) StockCount.fromMap(d.id, d.data(), pending: d.metadata.hasPendingWrites),
          ]);

  static Stream<StockCount?> watchCount(String id) => _counts
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .map((d) => d.exists ? StockCount.fromMap(d.id, d.data()!, pending: d.metadata.hasPendingWrites) : null);

  /// 재고 조사 시작 → 새 조사 ID
  static Future<String> startCount({required String counter, required bool owner, required int itemCount}) async {
    final ref = _counts.doc();
    // 인터넷이 끊겨도 휴대폰에 먼저 저장되게 기다리지 않음(set은 올라갈 때 끝남)
    unawaited(ref.set({
      'title': stockCountTitle(DateTime.now()),
      'status': 'open',
      'counts': <String, dynamic>{},
      'counter': counter.trim(),
      'startedBy': owner ? 'owner' : 'staff',
      'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'itemCount': itemCount,
    }).catchError((_) {}));
    return ref.id;
  }

  /// 한 항목 숫자 저장 (null이면 지움). 인터넷이 끊겨도 휴대폰에 모아 두었다가 연결되면 올라감
  static Future<void> setCount(String countId, String itemId, num? value) =>
      _counts.doc(countId).update({
        'counts.$itemId': value ?? FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// 조사 끝내기 — 그때 항목 이름·단위를 같이 저장
  static Future<void> finish(String countId, List<StockItem> items, {String note = ''}) =>
      _counts.doc(countId).update({
        'status': 'done',
        'finishedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'items': {for (final it in items) it.id: it.snapshot()},
        'itemCount': items.length,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      });

  /// (사장님) 끝난 조사를 다시 열기 — 직원이 숫자를 고칠 수 있게
  static Future<void> reopen(String countId) => _counts.doc(countId).update({
        'status': 'open',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// (사장님) 조사 지우기
  static Future<void> deleteCount(String countId) => _counts.doc(countId).delete();
}
