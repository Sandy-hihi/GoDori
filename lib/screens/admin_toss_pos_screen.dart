import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/toss_pos_service.dart';

const _navy = Color(0xFF1E2B3C);
const _toss = Color(0xFF3182F6);
const _red = Color(0xFFD64545);

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
              DropdownButton<String?>(
                isExpanded: true,
                value: item?.id,
                hint: Text(missingItem ? '연결한 상품이 포스에 없어요 — 다시 골라 주세요' : '연결 안 함 (이름·가격만 보냄)',
                    style: TextStyle(color: missingItem ? _red : Colors.black45)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('연결 안 함 (이름·가격만 보냄)')),
                  for (final i in _catalog)
                    DropdownMenuItem<String?>(
                      value: i.id,
                      child: Text('${i.title}${i.price == null ? '' : ' · ${i.price}원'}${i.category.isEmpty ? '' : '  (${i.category})'}${i.soldOut ? '  [품절]' : ''}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _catalog.isEmpty ? null : (v) => setState(() => _edit[m.id] = v),
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

  Widget _menuCard() {
    final linkedCount = _menus.where((m) => _item(_current(m.id)) != null).length;
    return _card(
      title: '메뉴 연결  ($linkedCount / ${_menus.length})',
      subtitle: '고도리 메뉴마다 같은 포스 상품을 골라 주세요. 연결하면 포스 매출에 그 상품으로 잡혀요. '
          '옵션은 포스 옵션과 이름이 같아야 같이 들어가요(띄어쓰기·아이스/ICE는 같게 봐요). '
          '포스에서 한 상품에 묶인 메뉴(예: 에이드 › 자몽에이드)는 상품을 고른 뒤 아래에서 옵션을 골라 두세요.',
      action: Wrap(spacing: 8, children: [
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
        for (final m in _menus) _menuRow(m),
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
                      if (ready) _setCard(),
                      if (ready) _failedCard(),
                    ],
                  ),
                ),
    );
  }
}
