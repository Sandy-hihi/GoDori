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
  TossCatalogItem? _item(String? id) {
    if (id == null) return null;
    for (final i in _catalog) {
      if (i.id == id) return i;
    }
    return null;
  }

  void _autoMatch() {
    var n = 0;
    setState(() {
      for (final m in _menus) {
        if (_current(m.id) != null) continue;
        final same = _catalog.where((i) => i.title.trim() == m.name.trim()).toList();
        if (same.length == 1) {
          _edit[m.id] = same.first.id;
          n++;
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n == 0 ? '이름이 똑같은 포스 상품을 더 찾지 못했어요.' : '$n개 연결했어요. 확인하고 저장을 눌러 주세요.'),
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

  // 연결한 포스 상품과 다른 점 (가격, 옵션 이름)
  String? _mismatch(_Menu m, TossCatalogItem item) {
    final notes = <String>[];
    if (item.price != null && item.price != m.price) notes.add('가격 다름(포스 ${item.price}원)');
    final posChoices = {for (final o in item.options) ...o.choices};
    final missing = m.options.where((o) => !posChoices.contains(o.name)).map((o) => o.name).toList();
    if (missing.isNotEmpty) notes.add('포스에 없는 옵션: ${missing.join(', ')} → 이 메뉴는 이름만 보냄');
    if (item.soldOut) notes.add('포스에서 품절');
    return notes.isEmpty ? null : notes.join(' · ');
  }

  Widget _menuRow(_Menu m) {
    final cur = _current(m.id);
    final item = _item(cur);
    final changed = _edit.containsKey(m.id) && _edit[m.id] != _saved[m.id];
    final warn = item == null ? null : _mismatch(m, item);
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
                value: item != null ? cur : null,
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
          '옵션은 포스 옵션과 이름이 같아야 같이 들어가요.',
      action: Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: _catalog.isEmpty || _saving ? null : _autoMatch,
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: const Text('이름이 같은 것 자동 연결'),
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
                      if (ready) _failedCard(),
                    ],
                  ),
                ),
    );
  }
}
