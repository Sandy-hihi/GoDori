import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/toss_pos_service.dart';
import 'admin_pos_import_dialog.dart';

const _navy = Color(0xFF1E2B3C);
const _toss = Color(0xFF3182F6);
const _red = Color(0xFFD64545);

// ── 105차: 메뉴 연결 찾기 도우미 ──
const _cho = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];

// 한글 글자를 초성으로 (예: '카페 라떼' → 'ㅋㅍ ㄹㄸ')
String _initials(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xAC00 && r <= 0xD7A3) {
      b.write(_cho[(r - 0xAC00) ~/ 588]);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

// 찾기: 띄어쓰기·대소문자 무시, 초성만 치면 초성으로 (예: 'ㅊㅋㄹㄸ' → 초코 라떼)
bool _matches(String text, String query) {
  final q = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (q.isEmpty) return true;
  final t = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (t.contains(q)) return true;
  final onlyCho = q.runes.every((r) => r >= 0x3131 && r <= 0x314E);
  return onlyCho && _initials(t).contains(q);
}

// 이름이 얼마나 비슷한지 0~1 (두 글자씩 묶어 겹치는 비율)
double _similar(String a, String b) {
  a = tossNormName(a);
  b = tossNormName(b);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  if (a.length < 2 || b.length < 2) return a.contains(b) || b.contains(a) ? 0.5 : 0;
  List<String> pairs(String s) => [for (var i = 0; i + 1 < s.length; i++) s.substring(i, i + 2)];
  final x = pairs(a);
  final y = pairs(b);
  final total = x.length + y.length;
  var hit = 0;
  for (final g in x) {
    final k = y.indexOf(g);
    if (k >= 0) {
      hit++;
      y.removeAt(k);
    }
  }
  return 2 * hit / total;
}

String _itemLabel(TossCatalogItem i) =>
    '${i.title}${i.price == null ? '' : ' · ${i.price}원'}${i.category.isEmpty ? '' : '  (${i.category})'}${i.soldOut ? '  [품절]' : ''}';

typedef _Suggestion = ({String value, TossCatalogItem item, String? note});

/// 관리자 웹: 토스 POS 연동 (64차) — '매장 설정 → 기능 사용 → 토스 POS 연동 설정'에서 들어옴
///   ① 연결 상태(운영자가 연결: 가짜 포스(개발용) 또는 실제 포스)
///   ② 메뉴 연결: 고도리 메뉴 ↔ 포스 상품. 연결한 메뉴는 포스 상품으로 들어가고(옵션은 이름이 같아야 함),
///      연결 안 한 메뉴는 이름·가격만 '임의 상품'으로 들어감
///   ③ 포스로 못 보낸 주문 → 다시 보내기
///   ④ 세트 구성품(103차): 포스 세트 상품 → 구성품. 포스 플러그인이 세트가 든 포스 주문에 구성품을 0원 줄로 덧붙여
///      토스가 구성품 재고를 줄이게 함(토스는 세트 상품 재고만 줄이고, 토스 API로는 재고를 직접 못 바꿈)
class AdminTossPosScreen extends StatefulWidget {
  const AdminTossPosScreen({super.key});

  @override
  State<AdminTossPosScreen> createState() => _AdminTossPosScreenState();
}

class _Menu {
  final String id;
  final String name;
  final String category;
  final int price;
  final List<({String group, String name})> options;
  const _Menu(this.id, this.name, this.category, this.price, this.options);
}

class _AdminTossPosScreenState extends State<AdminTossPosScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _status = const {};
  List<_Menu> _menus = const [];
  List<TossCatalogItem> _catalog = const [];
  String? _catalogError;
  Map<String, String> _saved = {}; // 서버에 저장된 연결표
  Map<String, String?> _edit = {}; // 화면에서 바꾸는 중
  bool _saving = false;
  final Set<String> _retrying = {};
  Map<String, List<TossSetPart>> _setsSaved = {}; // 103차 서버에 저장된 세트 구성표
  Map<String, List<TossSetPart>> _sets = {}; // 화면에서 바꾸는 중
  bool _savingSets = false;
  // 105차: 메뉴 연결 목록 — 고도리 카테고리 순서, 상태 칩, 찾기, 접기
  List<String> _categoryOrder = const [];
  String _filter = 'unlinked'; // unlinked · warn · linked · all
  String _query = '';
  final _queryCtrl = TextEditingController();
  final Set<String> _collapsed = {};
  final Set<String> _touched = {}; // 이번에 바꾼 메뉴는 칩과 상관없이 계속 보여 줌(골랐다고 바로 사라지지 않게)

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _catalogError = null;
    });
    try {
      final status = await TossPosService.status();
      final snap = await StoreScope.col('menus').get();
      var order = const <String>[];
      try {
        final cat = await StoreScope.col('settings').doc('categories').get();
        order = [for (final c in (cat.data()?['list'] as List? ?? const [])) '$c'];
      } catch (_) {}
      final menus = [
        for (final d in snap.docs)
          _Menu(
            d.id,
            '${d.data()['name'] ?? '이름 없음'}',
            '${d.data()['category'] ?? ''}',
            int.tryParse('${d.data()['price'] ?? 0}') ?? 0,
            [
              for (final g in (d.data()['optionGroups'] as List? ?? const []))
                for (final o in ((g as Map)['options'] as List? ?? const []))
                  (group: '${g['groupName'] ?? ''}', name: '${(o as Map)['name'] ?? ''}'),
            ],
          ),
      ]..sort((a, b) => '${a.category} ${a.name}'.compareTo('${b.category} ${b.name}'));
      List<TossCatalogItem> catalog = const [];
      String? catalogError;
      if (status['linked'] == true && status['enabled'] == true) {
        try {
          catalog = await TossPosService.catalog();
        } on TossPosException catch (e) {
          catalogError = e.message;
        }
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _menus = menus;
        _catalog = catalog;
        _catalogError = catalogError;
        _saved = {for (final e in ((status['menuMap'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
        _edit = {};
        _setsSaved = TossSetPart.mapFrom(status['setMap']);
        _sets = _copySets(_setsSaved);
        _categoryOrder = order;
        _touched.clear();
        if (_filter == 'unlinked' && _menus.every((m) => _saved[m.id] != null)) _filter = 'all';
        _loading = false;
      });
    } on TossPosException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '불러오지 못했어요. ($e)';
          _loading = false;
        });
      }
    }
  }

  String? _current(String menuId) => _edit.containsKey(menuId) ? _edit[menuId] : _saved[menuId];
  bool get _dirty => _edit.entries.any((e) => e.value != _saved[e.key]);
  TossCatalogItem? _item(String? value) {
    final id = TossMenuLink.parse(value)?.itemId;
    if (id == null) return null;
    for (final i in _catalog) {
      if (i.id == id) return i;
    }
    return null;
  }

  // 99차: 포스 필수 옵션 중 고도리 메뉴 옵션으로 채워지지 않는 것 (예: 포스 '에이드'의 [에이드: 레모네이드·자몽…])
  //   → 메뉴 연결에서 하나를 미리 골라 둬야 포스 상품으로 들어감
  List<TossCatalogOption> _fixable(_Menu m, TossCatalogItem item) => [
        for (final o in item.options)
          if (o.required && !o.choices.any((c) => m.options.any((mo) => tossNormName(mo.name) == tossNormName(c.title)))) o,
      ];

  // 이름으로 짝 찾기: ① 포스 상품 이름이 같음 ② 포스 상품의 필수 옵션 하나와 같음
  //   예: 고도리 '자몽 에이드' → 포스 '에이드' + [에이드: 자몽에이드],  '딸기 요거트 스무디' → '스무디' + [딸기 요거트]
  String? _guess(_Menu m) {
    final name = tossNormName(m.name);
    if (name.isEmpty) return null;
    // 고를 게 하나뿐인 필수 옵션(예: 에이드 [Only Ice: ICE])은 같이 골라 둠
    String withSingles(TossCatalogItem item, Map<String, String> fixed) {
      final all = {...fixed};
      for (final o in _fixable(m, item)) {
        if (!all.containsKey(o.id) && o.choices.length == 1 && o.choices.first.id.isNotEmpty) all[o.id] = o.choices.first.id;
      }
      return TossMenuLink(item.id, all).encode();
    }

    final same = _catalog.where((i) => tossNormName(i.title) == name).toList();
    if (same.length == 1) return withSingles(same.first, const {});
    if (same.length > 1) return null;
    final hits = <String>[];
    for (final i in _catalog) {
      final t = tossNormName(i.title);
      for (final o in i.options.where((o) => o.required)) {
        for (final c in o.choices) {
          final ct = tossNormName(c.title);
          if (ct.isEmpty || c.id.isEmpty) continue;
          if (name == ct || name == '$ct$t' || name == '$t$ct') hits.add(withSingles(i, {o.id: c.id}));
        }
      }
    }
    return hits.length == 1 ? hits.first : null;
  }

  void _autoMatch() {
    var n = 0;
    setState(() {
      for (final m in _menus) {
        if (_current(m.id) != null) continue;
        final g = _guess(m);
        if (g != null) {
          _edit[m.id] = g;
          _touched.add(m.id);
          n++;
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n == 0 ? '이름이 비슷한 포스 상품을 더 찾지 못했어요.' : '$n개 연결했어요. 확인하고 저장을 눌러 주세요.'),
    ));
  }

  Future<void> _save() async {
    final changes = {for (final e in _edit.entries) if (e.value != _saved[e.key]) e.key: e.value};
    if (changes.isEmpty) return;
    setState(() => _saving = true);
    try {
      final map = await TossPosService.saveMenuMap(changes);
      if (!mounted) return;
      setState(() {
        _saved = map;
        _edit = {};
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('메뉴 연결을 저장했어요. 다음 주문부터 반영돼요.')));
    } on TossPosException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── 세트 구성품 (103차) ──
  Map<String, List<TossSetPart>> _copySets(Map<String, List<TossSetPart>> m) => {for (final e in m.entries) e.key: [...e.value]};
  String _setsKey(Map<String, List<TossSetPart>> m) =>
      jsonEncode({for (final e in m.entries) e.key: [for (final p in e.value) p.toJson()]});
  bool get _setsDirty => _setsKey(_sets) != _setsKey(_setsSaved);
  TossCatalogItem? _byId(String id) {
    for (final i in _catalog) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<void> _saveSets() async {
    // 상품을 안 고른 구성품 줄은 빼고 보냄(구성품이 하나도 없는 세트는 서버가 뺌)
    final clean = {
      for (final e in _sets.entries) e.key: [for (final p in e.value) if (p.entry.isNotEmpty) p],
    };
    setState(() => _savingSets = true);
    try {
      final saved = await TossPosService.saveSetMap(clean);
      if (!mounted) return;
      setState(() {
        _setsSaved = saved;
        _sets = _copySets(saved);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('세트 구성품을 저장했어요. 포스 플러그인이 1분 안에 받아 가요.'),
      ));
    } on TossPosException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _savingSets = false);
    }
  }

  void _putPart(String setId, int i, TossSetPart p) => setState(() {
        final l = [...?_sets[setId]];
        l[i] = p;
        _sets[setId] = l;
      });

  Widget _partOptionPicker(TossCatalogItem item, TossMenuLink link, TossCatalogOption o, ValueChanged<String> onEntry) {
    final cur = link.fixed[o.id];
    final valid = o.choices.any((c) => c.id == cur);
    return Row(children: [
      Text('${o.title}: ', style: const TextStyle(fontSize: 13, color: Colors.black54)),
      const SizedBox(width: 6),
      Expanded(
        child: DropdownButton<String?>(
          isExpanded: true,
          isDense: true,
          value: valid ? cur : null,
          hint: const Text('포스 필수 옵션 — 하나 골라 주세요', style: TextStyle(fontSize: 13, color: Colors.orange)),
          items: [
            for (final c in o.choices.where((c) => c.id.isNotEmpty))
              DropdownMenuItem<String?>(value: c.id, child: Text(c.title, style: const TextStyle(fontSize: 13))),
          ],
          onChanged: _savingSets
              ? null
              : (v) {
                  final fixed = {...link.fixed};
                  if (v == null) {
                    fixed.remove(o.id);
                  } else {
                    fixed[o.id] = v;
                  }
                  onEntry(TossMenuLink(item.id, fixed).encode());
                },
        ),
      ),
    ]);
  }

  // 구성품 조건: 항상 / 세트 상품의 포스 옵션 선택을 골랐을 때만 (예: [떡볶이] 로제 → 로제 떡볶이)
  Widget _whenPicker(String setId, int i, TossSetPart part) {
    final setItem = _byId(setId);
    final choices = <(String, String)>[
      if (setItem != null)
        for (final o in setItem.options)
          for (final c in o.choices)
            if (o.id.isNotEmpty && c.id.isNotEmpty) ('${o.id}=${c.id}', '[${o.title}] ${c.title}'),
    ];
    final valid = part.when.isEmpty || choices.any((c) => c.$1 == part.when);
    return Row(children: [
      const Text('조건: ', style: TextStyle(fontSize: 13, color: Colors.black54)),
      const SizedBox(width: 6),
      Expanded(
        child: DropdownButton<String>(
          isExpanded: true,
          isDense: true,
          value: valid ? part.when : null,
          hint: const Text('고른 옵션이 포스에 없어요 — 다시 골라 주세요', style: TextStyle(fontSize: 13, color: _red)),
          items: [
            const DropdownMenuItem<String>(value: '', child: Text('항상 (세트를 팔면 언제나)', style: TextStyle(fontSize: 13))),
            for (final c in choices)
              DropdownMenuItem<String>(value: c.$1, child: Text('${c.$2} 을(를) 골랐을 때만', style: const TextStyle(fontSize: 13))),
          ],
          onChanged: _savingSets || choices.isEmpty ? null : (v) => _putPart(setId, i, part.copyWith(when: v ?? '')),
        ),
      ),
    ]);
  }

  Widget _partRow(String setId, int i) {
    final part = _sets[setId]![i];
    final link = TossMenuLink.parse(part.entry);
    final item = link == null ? null : _byId(link.itemId);
    final gone = part.entry.isNotEmpty && item == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 12, right: 8),
          child: Icon(Icons.subdirectory_arrow_right, size: 18, color: Colors.black26),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButton<String?>(
              isExpanded: true,
              value: item?.id,
              hint: Text(gone ? '고른 상품이 포스에 없어요 — 다시 골라 주세요' : '구성품 고르기 (예: 떡볶이)',
                  style: TextStyle(color: gone ? _red : Colors.black45)),
              items: [
                for (final c in _catalog)
                  if (c.id != setId)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text('${c.title}${c.category.isEmpty ? '' : '  (${c.category})'}', overflow: TextOverflow.ellipsis),
                    ),
              ],
              onChanged: _savingSets ? null : (v) => _putPart(setId, i, part.copyWith(entry: v ?? '')),
            ),
            if (item != null && link != null)
              for (final o in item.options.where((o) => o.required))
                _partOptionPicker(item, link, o, (entry) => _putPart(setId, i, part.copyWith(entry: entry))),
            _whenPicker(setId, i, part),
          ]),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '하나 줄이기',
          onPressed: _savingSets || part.qty <= 1 ? null : () => _putPart(setId, i, part.copyWith(qty: part.qty - 1)),
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(width: 36, child: Text('${part.qty}개', textAlign: TextAlign.center)),
        ),
        IconButton(
          tooltip: '하나 늘리기',
          onPressed: _savingSets || part.qty >= 20 ? null : () => _putPart(setId, i, part.copyWith(qty: part.qty + 1)),
          icon: const Icon(Icons.add_circle_outline, size: 20),
        ),
        IconButton(
          tooltip: '이 구성품 빼기',
          onPressed: _savingSets
              ? null
              : () => setState(() {
                    _sets[setId] = [...?_sets[setId]]..removeAt(i);
                  }),
          icon: const Icon(Icons.close, size: 20, color: Colors.black45),
        ),
      ]),
    );
  }

  Widget _setBlock(String setId) {
    final item = _byId(setId);
    final parts = _sets[setId] ?? const <TossSetPart>[];
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE6E8EB)), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.inventory_2_outlined, size: 18, color: _navy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item == null ? '포스에 없는 세트 상품이에요 ($setId) — 지워 주세요' : '${item.title}${item.price == null ? '' : ' · ${item.price}원'}',
              style: TextStyle(fontWeight: FontWeight.bold, color: item == null ? _red : Colors.black87),
            ),
          ),
          TextButton.icon(
            onPressed: _savingSets ? null : () => setState(() => _sets.remove(setId)),
            style: TextButton.styleFrom(foregroundColor: _red),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('세트 지우기'),
          ),
        ]),
        if (parts.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 26, top: 4),
            child: Text('구성품이 없으면 저장할 때 빠져요.', style: TextStyle(color: Colors.black45, fontSize: 13)),
          ),
        for (var i = 0; i < parts.length; i++) _partRow(setId, i),
        TextButton.icon(
          onPressed: _savingSets || parts.length >= 20 ? null : () => setState(() => _sets[setId] = [...parts, const TossSetPart('', 1)]),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('구성품 추가'),
        ),
      ]),
    );
  }

  Widget _setCard() {
    final candidates = [for (final i in _catalog) if (!_sets.containsKey(i.id)) i];
    return _card(
      title: '세트 구성품 (재고 차감)  (${_sets.length})',
      subtitle: '토스 포스는 세트를 팔면 세트 상품 재고만 줄이고 구성품 재고는 그대로예요. '
          '세트마다 구성품을 정해 두면, 세트가 든 포스 주문(패드 주문·포스에서 직접 누른 주문 모두)에 '
          '포스 플러그인이 구성품을 0원으로 같이 넣어서 구성품 재고가 줄어요. 매출 금액은 그대로예요.\n'
          '• 토스에서 세트 상품의 재고 관리는 꺼 두세요.  • 결제 전에 세트를 빼면 0원 구성품 줄도 포스에서 같이 빼 주세요.\n'
          '• 고른 맛에 따라 다른 재고를 빼려면(예: 로제 떡볶이·매콤 떡볶이) 토스에 맛별 상품을 따로 만들고, 구성품마다 \'조건\'에서 그 옵션을 골라 주세요.',
      action: FilledButton.icon(
        onPressed: !_setsDirty || _savingSets ? null : _saveSets,
        style: FilledButton.styleFrom(backgroundColor: _navy, disabledBackgroundColor: _navy.withValues(alpha: 0.35), disabledForegroundColor: Colors.white70),
        icon: const Icon(Icons.save_outlined, size: 18),
        label: const Text('저장'),
      ),
      children: [
        if (_status['mode'] != 'live')
          const Text('실제 토스 포스에 고도리 포스 플러그인이 설치·승인돼 있어야 동작해요. (지금은 가짜 포스에 연결돼 있어요)',
              style: TextStyle(color: Colors.orange)),
        if (_catalog.isEmpty)
          const Text('포스 상품을 불러와야 세트를 정할 수 있어요.', style: TextStyle(color: Colors.black45))
        else ...[
          for (final id in _sets.keys.toList()) _setBlock(id),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.add_box_outlined, size: 20, color: _navy),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: null,
                hint: const Text('세트 추가 — 포스의 세트 상품을 고르세요 (예: 떡볶이 닭껍질 세트)'),
                items: [
                  for (final c in candidates)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text('${c.title}${c.category.isEmpty ? '' : '  (${c.category})'}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _savingSets || candidates.isEmpty
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _sets[v] = [const TossSetPart('', 1)]);
                      },
              ),
            ),
          ]),
        ],
      ],
    );
  }

  Future<void> _retry(String orderId) async {
    setState(() => _retrying.add(orderId));
    try {
      final r = await TossPosService.sendOrder(orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['state'] == 'sent' ? '포스로 보냈어요.' : '다시 실패했어요: ${r['error'] ?? ''}'),
      ));
      await _load();
    } on TossPosException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _retrying.remove(orderId));
    }
  }

  Widget _card({required String title, String? subtitle, Widget? action, required List<Widget> children}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 960),
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            ?action,
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: Colors.black54, height: 1.5)),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _statusCard() {
    final enabled = _status['enabled'] == true;
    final linked = _status['linked'] == true;
    final fake = _status['mode'] == 'fake';
    final (IconData icon, Color color, String text) = !enabled
        ? (Icons.block, Colors.black45, '이 매장은 토스 POS 연동을 쓰지 않아요. 쓰려면 고도리 운영자에게 요청해 주세요.')
        : !linked
            ? (Icons.link_off, Colors.orange, '아직 포스와 연결되지 않았어요. 운영자가 연결하면 여기에 표시돼요.')
            : fake
                ? (Icons.science_outlined, _toss, '가짜 포스(개발용)에 연결돼 있어요. 주문은 실제 포스가 아니라 시험용 가짜 포스로 가요.')
                : (Icons.point_of_sale, const Color(0xFF27AE60), '토스 POS에 연결돼 있어요: ${_status['merchantName'] ?? ''}');
    return _card(title: '연결 상태', children: [
      Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
      ]),
      if (enabled && linked) ...[
        const SizedBox(height: 12),
        const Text(
          '손님이 패드에서 주문하면 바로 포스에 주문이 들어가요(결제는 지금처럼 카운터 포스에서). '
          '포스의 품절은 고도리와 따로라서, 포스에서만 품절이면 그 주문은 포스로 못 가고 아래 \'보내지 못한 주문\'에 남아요.',
          style: TextStyle(color: Colors.black54, height: 1.5),
        ),
      ],
    ]);
  }

  // 연결한 포스 상품과 다른 점 (가격, 옵션 이름, 안 고른 필수 옵션)
  String? _mismatch(_Menu m, TossCatalogItem item, TossMenuLink link) {
    final notes = <String>[];
    var fixedPrice = 0;
    for (final o in item.options) {
      for (final c in o.choices) {
        if (link.fixed[o.id] == c.id) fixedPrice += c.price;
      }
    }
    if (item.price != null && item.price! + fixedPrice != m.price) notes.add('가격 다름(포스 ${item.price! + fixedPrice}원)');
    final posChoices = {
      for (final o in item.options)
        if (!link.fixed.containsKey(o.id)) ...o.choices.map((c) => tossNormName(c.title)),
    };
    final missing = m.options.where((o) => !posChoices.contains(tossNormName(o.name))).map((o) => o.name).toList();
    if (missing.isNotEmpty) notes.add('포스에 없는 옵션: ${missing.join(', ')} → 이 옵션을 고르면 이름만 보냄');
    final unpicked = _fixable(m, item).where((o) => !link.fixed.containsKey(o.id)).map((o) => o.title).toList();
    if (unpicked.isNotEmpty) notes.add('포스 필수 옵션을 골라 주세요: ${unpicked.join(', ')} (안 고르면 이름만 보냄)');
    if (item.soldOut) notes.add('포스에서 품절');
    return notes.isEmpty ? null : notes.join(' · ');
  }

  // 필수 옵션 미리 고르기 (99차)
  Widget _fixedPicker(_Menu m, TossCatalogItem item, TossMenuLink link, TossCatalogOption o) {
    final cur = link.fixed[o.id];
    final valid = o.choices.any((c) => c.id == cur);
    return Row(children: [
      Text('${o.title}: ', style: const TextStyle(fontSize: 13, color: Colors.black54)),
      const SizedBox(width: 6),
      Expanded(
        child: DropdownButton<String?>(
          isExpanded: true,
          isDense: true,
          value: valid ? cur : null,
          hint: const Text('하나 골라 주세요', style: TextStyle(fontSize: 13, color: _red)),
          items: [
            for (final c in o.choices.where((c) => c.id.isNotEmpty))
              DropdownMenuItem<String?>(
                value: c.id,
                child: Text('${c.title}${c.price == 0 ? '' : ' (+${c.price}원)'}', style: const TextStyle(fontSize: 13)),
              ),
          ],
          onChanged: (v) => setState(() {
            final fixed = {...link.fixed};
            if (v == null) {
              fixed.remove(o.id);
            } else {
              fixed[o.id] = v;
            }
            _edit[m.id] = TossMenuLink(item.id, fixed).encode();
          }),
        ),
      ),
    ]);
  }

  Widget _menuRow(_Menu m) {
    final cur = _current(m.id);
    final item = _item(cur);
    final link = TossMenuLink.parse(cur);
    final changed = _edit.containsKey(m.id) && _edit[m.id] != _saved[m.id];
    final warn = item == null || link == null ? null : _mismatch(m, item, link);
    final missingItem = cur != null && item == null && _catalog.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 280,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: TextStyle(fontWeight: FontWeight.bold, color: changed ? _toss : Colors.black87)),
              Text('${m.category.isEmpty ? '카테고리 없음' : m.category} · ${m.price}원', style: const TextStyle(color: Colors.black45, fontSize: 13)),
            ]),
          ),
          const Icon(Icons.arrow_forward, size: 18, color: Colors.black26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 105차: 드롭다운 대신 누르면 포스 상품 고르기 창(찾기·추천·카테고리별)
              InkWell(
                onTap: _catalog.isEmpty ? null : () => _openPicker(m),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    suffixIcon: Icon(Icons.search, size: 20),
                    suffixIconConstraints: BoxConstraints(minWidth: 28, minHeight: 20),
                  ),
                  child: item != null
                      ? Text(_itemLabel(item), overflow: TextOverflow.ellipsis)
                      : Text(missingItem ? '연결한 상품이 포스에 없어요 — 다시 골라 주세요' : '연결 안 함 (이름·가격만 보냄)',
                          overflow: TextOverflow.ellipsis, style: TextStyle(color: missingItem ? _red : Colors.black45)),
                ),
              ),
              if (item != null && link != null)
                for (final o in item.options.where((o) => o.required && (link.fixed.containsKey(o.id) || _fixable(m, item).contains(o))))
                  _fixedPicker(m, item, link, o),
              if (warn != null) Text(warn, style: const TextStyle(color: Colors.orange, fontSize: 12)),
            ]),
          ),
        ],
      ),
    );
  }

  // 105차: 메뉴 한 줄의 상태 — unlinked(연결 안 함) · warn(가격 다름·옵션·품절·없는 상품) · linked(문제 없음)
  String _stateOf(_Menu m) {
    final cur = _current(m.id);
    if (cur == null) return 'unlinked';
    final item = _item(cur);
    final link = TossMenuLink.parse(cur);
    if (item == null || link == null) return _catalog.isEmpty ? 'linked' : 'warn';
    return _mismatch(m, item, link) == null ? 'linked' : 'warn';
  }

  // 105차: 추천 — 자동 연결과 같은 짝(옵션까지) 먼저, 그다음 이름이 비슷한 포스 상품(필수 옵션 이름도 봄)
  List<_Suggestion> _suggest(_Menu m) {
    final out = <_Suggestion>[];
    final g = _guess(m);
    final gi = _item(g);
    final gl = TossMenuLink.parse(g);
    if (g != null && gi != null && gl != null) {
      final picks = [
        for (final o in gi.options)
          for (final c in o.choices)
            if (gl.fixed[o.id] == c.id) c.title,
      ];
      out.add((value: g, item: gi, note: picks.isEmpty ? null : '옵션 ${picks.join(', ')} 같이 골라 둠'));
    }
    final scored = <(double, TossCatalogItem)>[];
    for (final i in _catalog) {
      if (i.id == gi?.id) continue;
      var s = _similar(m.name, i.title);
      for (final o in i.options.where((o) => o.required)) {
        for (final c in o.choices) {
          s = math.max(s, _similar(m.name, c.title) * 0.9);
        }
      }
      if (s >= 0.4) scored.add((s, i));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    for (final s in scored.take(4 - out.length)) {
      out.add((value: s.$2.id, item: s.$2, note: null));
    }
    return out;
  }

  Future<void> _openPicker(_Menu m) async {
    final cur = _current(m.id);
    final curItem = _item(cur)?.id;
    final usedBy = <String, List<String>>{};
    for (final o in _menus) {
      if (o.id == m.id) continue;
      final id = _item(_current(o.id))?.id;
      if (id != null) (usedBy[id] ??= []).add(o.name);
    }
    final picked = await showDialog<({String? value})>(
      context: context,
      builder: (_) => _PosItemPicker(
        menuName: m.name,
        menuPrice: m.price,
        catalog: _catalog,
        currentId: curItem,
        suggestions: _suggest(m),
        usedBy: usedBy,
      ),
    );
    if (picked == null || !mounted) return;
    var v = picked.value;
    if (v != null && v == curItem) v = cur; // 같은 상품을 다시 고르면 미리 골라 둔 옵션은 그대로
    setState(() {
      _edit[m.id] = v;
      _touched.add(m.id);
    });
  }

  // 105차: 위에 찾기·상태 칩, 아래에 고도리 카테고리별 묶음(누르면 접기·펴기, 연결 n/m)
  List<Widget> _menuList() {
    final states = {for (final m in _menus) m.id: _stateOf(m)};
    int count(String s) => s == 'all' ? _menus.length : states.values.where((v) => v == s).length;
    final searching = _query.trim().isNotEmpty;
    bool visible(_Menu m) =>
        (_filter == 'all' || states[m.id] == _filter || _touched.contains(m.id)) &&
        (!searching || _matches(m.name, _query) || _matches(m.category, _query));
    // 카테고리 순서 = 메뉴 관리 [카테고리 관리] 순서, 거기 없는 건 뒤에 가나다순(카테고리 없음은 맨 끝)
    final cats = [for (final c in _categoryOrder) if (_menus.any((m) => m.category == c)) c];
    final rest = {for (final m in _menus) if (!cats.contains(m.category)) m.category}.toList()
      ..sort((a, b) => a.isEmpty ? 1 : (b.isEmpty ? -1 : a.compareTo(b)));
    cats.addAll(rest);

    Widget chip(String key, String label) {
      final on = _filter == key;
      return ChoiceChip(
        label: Text('$label ${count(key)}'),
        selected: on,
        showCheckmark: false,
        selectedColor: _navy,
        labelStyle: TextStyle(color: on ? Colors.white : _navy, fontWeight: on ? FontWeight.bold : FontWeight.normal),
        onSelected: (_) => setState(() {
          _filter = key;
          _touched.clear();
        }),
      );
    }

    final out = <Widget>[
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _queryCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: '메뉴 찾기 (초성도 돼요: ㅊㅋㄹㄸ)',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _queryCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 4),
        chip('unlinked', '미연결'),
        chip('warn', '확인 필요'),
        chip('linked', '연결 완료'),
        chip('all', '전체'),
      ]),
      const SizedBox(height: 4),
    ];
    var shown = 0;
    for (final c in cats) {
      final all = _menus.where((m) => m.category == c).toList();
      final rows = all.where(visible).toList();
      if (rows.isEmpty) continue;
      shown += rows.length;
      final done = all.where((m) => states[m.id] != 'unlinked').length;
      final open = searching || !_collapsed.contains(c);
      out.add(InkWell(
        onTap: searching
            ? null
            : () => setState(() {
                  if (!_collapsed.remove(c)) _collapsed.add(c);
                }),
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFF4F6F8), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(open ? Icons.expand_more : Icons.chevron_right, size: 20, color: _navy),
            const SizedBox(width: 6),
            Text(c.isEmpty ? '카테고리 없음' : c, style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
            const SizedBox(width: 10),
            Text('연결 $done / ${all.length}',
                style: TextStyle(fontSize: 13, color: done == all.length ? const Color(0xFF27AE60) : Colors.black45)),
            const Spacer(),
            if (rows.length != all.length) Text('${rows.length}개 보임', style: const TextStyle(fontSize: 12, color: Colors.black38)),
          ]),
        ),
      ));
      if (open) out.addAll(rows.map(_menuRow));
    }
    if (_menus.isNotEmpty && shown == 0) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          searching
              ? '찾는 메뉴가 없어요.'
              : _filter == 'unlinked'
                  ? '연결 안 한 메뉴가 없어요 👍'
                  : _filter == 'warn'
                      ? '확인할 메뉴가 없어요 👍'
                      : '해당하는 메뉴가 없어요.',
          style: const TextStyle(color: Colors.black45),
        ),
      ));
    }
    return out;
  }

  // 113차: 포스 메뉴 가져오기 (저장 안 한 연결이 있으면 먼저 저장 — 버튼이 흐려짐)
  Future<void> _importFromPos() async {
    final linked = <String>{
      for (final v in _saved.values)
        if (TossMenuLink.parse(v)?.itemId != null) TossMenuLink.parse(v)!.itemId,
    };
    final n = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PosImportDialog(
        catalog: _catalog,
        linkedItemIds: linked,
        existingNames: {for (final m in _menus) PosImportDialog.nameKey(m.name)},
      ),
    );
    if (n == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('포스 메뉴 $n개를 가져와 연결했어요. 사진은 메뉴 관리에서 넣어 주세요.')));
    await _load();
  }

  Widget _menuCard() {
    final linkedCount = _menus.where((m) => _item(_current(m.id)) != null).length;
    return _card(
      title: '메뉴 연결  ($linkedCount / ${_menus.length})',
      subtitle: '고도리 메뉴마다 같은 포스 상품을 골라 주세요. 연결하면 포스 매출에 그 상품으로 잡혀요. '
          '옵션은 포스 옵션과 이름이 같아야 같이 들어가요(띄어쓰기·아이스/ICE는 같게 봐요). '
          '포스에서 한 상품에 묶인 메뉴(예: 에이드 › 자몽에이드)는 상품을 고른 뒤 아래에서 옵션을 골라 두세요.',
      action: Wrap(spacing: 8, children: [
        // 113차: 아직 연결 안 된 포스 상품을 고도리 메뉴로 만들고 바로 연결
        OutlinedButton.icon(
          onPressed: _catalog.isEmpty || _saving || _dirty ? null : _importFromPos,
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('포스 메뉴 가져오기'),
        ),
        OutlinedButton.icon(
          onPressed: _catalog.isEmpty || _saving ? null : _autoMatch,
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: const Text('이름이 비슷한 것 자동 연결'),
        ),
        FilledButton.icon(
          onPressed: !_dirty || _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: _navy),
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined, size: 18),
          label: const Text('저장'),
        ),
      ]),
      children: [
        if (_catalogError != null)
          Text('포스 상품을 불러오지 못했어요: $_catalogError', style: const TextStyle(color: _red))
        else if (_catalog.isEmpty)
          const Text('포스에 상품이 없거나 아직 연결 전이에요.', style: TextStyle(color: Colors.black45)),
        if (_menus.isEmpty) const Text('고도리 메뉴가 없어요.', style: TextStyle(color: Colors.black45)),
        ..._menuList(),
      ],
    );
  }

  // 113차: 포스 상품과 연결 안 된 메뉴를 받을 포스 상품 — 고르면 그 메뉴 줄이 이 상품(값 0 권장)으로 들어가고 메모에 원래 이름·옵션·값
  bool _etcBusy = false;
  Future<void> _saveEtc(String? id) async {
    if (_etcBusy) return;
    setState(() => _etcBusy = true);
    try {
      final v = await TossPosService.saveEtcItem(id);
      if (!mounted) return;
      setState(() => _status = {..._status, 'etcItemId': v});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(v == null
            ? '연결 안 된 메뉴는 다시 포스로 넘어가지 않아요(\'포스 실패\'로 남아요).'
            : '연결 안 된 메뉴는 이제 이 상품으로 포스에 들어가요.'),
      ));
    } on TossPosException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _etcBusy = false);
    }
  }

  Widget _etcCard() {
    final cur = _status['etcItemId']?.toString();
    final items = [..._catalog]..sort((a, b) {
        final za = (a.price ?? 0) == 0, zb = (b.price ?? 0) == 0;
        if (za != zb) return za ? -1 : 1; // 0원 상품 먼저
        return a.title.compareTo(b.title);
      });
    TossCatalogItem? picked;
    for (final i in _catalog) {
      if (i.id == cur) picked = i;
    }
    final missing = cur != null && picked == null;
    const none = '고르지 않음 — 연결 안 된 메뉴는 \'포스 실패\'로 남아요';
    return _card(
      title: '연결 안 된 메뉴 받기',
      subtitle: '포스 상품과 연결하지 않은 고도리 메뉴도 포스로 넘기려면, 받아 줄 포스 상품을 하나 골라 주세요.\n'
          '토스 포스에 0원짜리 \'고도리 기타\' 상품을 만들어 고르는 걸 권해요 — 그 줄 메모에 원래 메뉴 이름·옵션·값이 적혀요.\n'
          '포스는 고른 상품 값으로 계산하니, 결제 전에 직원이 포스에서 금액을 맞춰 주세요.',
      children: [
        if (_status['mode'] != 'live')
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('진짜 포스(포스 플러그인)에 연결된 매장에서만 써요.', style: TextStyle(color: Colors.black54)),
          ),
        DropdownButton<String?>(
          isExpanded: true,
          value: picked?.id,
          hint: Text(missing ? '골라 둔 상품이 포스에 없어요 — 다시 골라 주세요' : none,
              style: TextStyle(color: missing ? _red : Colors.black54)),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text(none)),
            for (final i in items)
              DropdownMenuItem<String?>(
                value: i.id,
                child: Text('${i.title} · ${i.price == null ? '-' : '${i.price}원'}${i.category.isEmpty ? '' : ' · ${i.category}'}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _etcBusy
              ? null
              : (v) {
                  if (v != cur) _saveEtc(v);
                },
        ),
        if (picked != null && (picked.price ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('고른 상품 값(${picked.price}원)이 0원이 아니에요 — 이 값이 계산서에 더해져요. 0원 상품을 권해요.',
                style: const TextStyle(color: _red)),
          ),
      ],
    );
  }

  Widget _failedCard() {
    final failed = (_status['failed'] as List?) ?? const [];
    return _card(
      title: '포스로 보내지 못한 주문 (${failed.length})',
      subtitle: '이유를 해결한 뒤(예: 포스 품절 풀기, 메뉴 연결 고치기) 다시 보내거나, 포스에 직접 입력해 주세요.',
      children: [
        if (failed.isEmpty) const Text('없어요 👍', style: TextStyle(color: Colors.black45)),
        for (final f in failed.cast<Map>())
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 110,
                child: Text('${f['room']}  ${f['time']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(((f['items'] as List?) ?? const []).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${f['error'] ?? ''}', style: const TextStyle(color: _red, fontSize: 13)),
                ]),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _retrying.contains('${f['id']}') ? null : () => _retry('${f['id']}'),
                child: _retrying.contains('${f['id']}')
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('다시 보내기'),
              ),
            ]),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _status['enabled'] == true && _status['linked'] == true;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        title: const Text('토스 POS 연동', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _loading ? null : _load, tooltip: '새로고침', icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: const TextStyle(color: _red)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
                  ]),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _statusCard(),
                      if (ready) _menuCard(),
                      if (ready) _etcCard(), // 113차
                      if (ready) _setCard(),
                      if (ready) _failedCard(),
                    ],
                  ),
                ),
    );
  }
}

/// 105차: 포스 상품 고르기 창 — 찾기(초성도), 추천, 포스 카테고리별 묶음, 다른 메뉴에 이미 연결된 상품 표시
///   닫으면 null, 고르면 (value: 상품ID 또는 '상품ID:옵션ID=선택ID,…'), '연결 안 함'이면 (value: null)
class _PosItemPicker extends StatefulWidget {
  final String menuName;
  final int menuPrice;
  final List<TossCatalogItem> catalog;
  final String? currentId;
  final List<_Suggestion> suggestions;
  final Map<String, List<String>> usedBy;
  const _PosItemPicker({
    required this.menuName,
    required this.menuPrice,
    required this.catalog,
    required this.currentId,
    required this.suggestions,
    required this.usedBy,
  });

  @override
  State<_PosItemPicker> createState() => _PosItemPickerState();
}

class _PosItemPickerState extends State<_PosItemPicker> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _pick(String? v) => Navigator.of(context).pop((value: v));

  List<TossCatalogItem> get _hits => [
        for (final i in widget.catalog)
          if (_matches(i.title, _q) || _matches(i.category, _q)) i,
      ];

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black45)),
      );

  Widget _tile(TossCatalogItem i, {String? value, String? note}) {
    final selected = i.id == widget.currentId;
    final used = widget.usedBy[i.id];
    final sub = [
      ?note,
      if (used != null) '이미 연결: ${used.join(', ')}',
    ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      selected: selected,
      selectedColor: _toss,
      selectedTileColor: const Color(0xFFEAF2FE),
      title: Text('${i.title}${i.price == null ? '' : ' · ${i.price}원'}', style: const TextStyle(fontSize: 15)),
      subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black45)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (i.soldOut) const Text('품절', style: TextStyle(color: _red, fontSize: 12)),
        if (selected) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check, color: _toss, size: 20)),
      ]),
      onTap: () => _pick(value ?? i.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    final searching = _q.trim().isNotEmpty;
    final groups = <String, List<TossCatalogItem>>{};
    for (final i in hits) {
      (groups[i.category.isEmpty ? '분류 없음' : i.category] ??= []).add(i);
    }
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.white,
      child: SizedBox(
        width: math.min(560.0, size.width - 48),
        height: size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('포스 상품 고르기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy)),
              const SizedBox(height: 4),
              Text('고도리 메뉴: ${widget.menuName} · ${widget.menuPrice}원', style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: (v) => setState(() => _q = v),
                onSubmitted: (_) {
                  final h = _hits;
                  if (h.length == 1) _pick(h.first.id);
                },
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '포스 상품 찾기 (초성도 돼요)',
                  prefixIcon: Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              if (!searching)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  selected: widget.currentId == null,
                  selectedColor: _toss,
                  selectedTileColor: const Color(0xFFEAF2FE),
                  leading: const Icon(Icons.link_off, size: 20),
                  title: const Text('연결 안 함 (이름·가격만 보냄)', style: TextStyle(fontSize: 15)),
                  onTap: () => _pick(null),
                ),
              if (!searching && widget.suggestions.isNotEmpty) ...[
                _header('추천 — 이름이 비슷해요'),
                for (final s in widget.suggestions) _tile(s.item, value: s.value, note: s.note),
              ],
              for (final e in groups.entries) ...[
                _header('${e.key}  ${e.value.length}'),
                for (final i in e.value) _tile(i),
              ],
              if (hits.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('찾는 포스 상품이 없어요.', style: TextStyle(color: Colors.black45)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기')),
            ),
          ),
        ]),
      ),
    );
  }
}
