import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:boardpad/services/stock_service.dart';
import 'package:boardpad/services/store_features.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/widgets/admin_busy_dialog.dart';
import 'package:boardpad/widgets/admin_colors.dart';
import 'package:boardpad/widgets/admin_dialog_width.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';

/// 관리자 웹 '재고관리' (148차) — 재고관리를 신청한 매장(features.stock, 운영자가 켬)만 사이드바에 보임
///  - [조사 결과]: 직원이 휴대폰 재고 앱에서 센 숫자 (진행 중인 조사는 실시간), 직전 조사와 차이, 적정 재고보다 적으면 '부족'
///  - [재고 항목]: 재고 앱에 나올 항목 만들기·고치기·순서·숨기기, '한꺼번에 추가'
/// 데이터·계산은 lib/services/stock_service.dart, 재고 앱은 lib/stock/stock_app.dart (main_stock.dart)
class AdminStockScreen extends StatefulWidget {
  const AdminStockScreen({super.key});

  @override
  State<AdminStockScreen> createState() => _AdminStockScreenState();
}

class _AdminStockScreenState extends State<AdminStockScreen> {
  static const _red = Color(0xFFD64545);
  static const _orange = Color(0xFFE67E22);
  static const _green = Color(0xFF2E9D5B);
  static const _units = ['개', '박스', '병', '캔', '봉', '팩', 'kg', 'L'];

  // 구독은 한 번만 (100차 규칙)
  final List<StreamSubscription> _subs = [];
  bool? _stockOn; // null = 아직 모름
  bool _started = false;
  List<StockItem>? _items;
  List<StockCount>? _counts;
  String? _error;
  int _tab = 0; // 0 조사 결과, 1 재고 항목
  String? _selectedId; // 고른 조사 (없으면 가장 최근)
  String _filter = 'all'; // all | low | empty

  @override
  void initState() {
    super.initState();
    _subs.add(StoreFeaturesService.watch().listen((f) {
      if (!mounted) return;
      setState(() => _stockOn = f.stock);
      if (f.stock) _startData();
    }));
  }

  void _startData() {
    if (_started) return;
    _started = true;
    void fail(Object e) {
      if (mounted) setState(() => _error = '불러오지 못했어요: $e');
    }

    _subs.add(StockService.watchItems().listen((v) {
      if (mounted) setState(() => _items = v);
    }, onError: fail));
    _subs.add(StockService.watchCounts(limit: 60).listen((v) {
      if (mounted) setState(() => _counts = v);
    }, onError: fail));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Row(
        children: [
          AdminSidebar(currentScreen: 'stock', onNavigate: (s) => AdminSidebar.go(context, s)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(narrow ? 16.0 : 32.0),
              child: _body(narrow),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(bool narrow) {
    if (_stockOn == null) return const Center(child: CircularProgressIndicator());
    if (_stockOn == false) return _notApplied();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('재고관리', style: TextStyle(fontSize: narrow ? 24 : 32, fontWeight: FontWeight.bold)),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.receipt_long_outlined), label: Text('조사 결과')),
                ButtonSegment(value: 1, icon: Icon(Icons.inventory_2_outlined), label: Text('재고 항목')),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(selectedBackgroundColor: kAdminAccent, selectedForegroundColor: Colors.white),
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: _red)))
              : (_items == null || _counts == null)
                  ? const Center(child: CircularProgressIndicator())
                  : _tab == 0
                      ? _resultsTab(narrow)
                      : _itemsTab(narrow),
        ),
      ],
    );
  }

  Widget _notApplied() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inventory_2_outlined, size: 48, color: kAdminAccent),
                SizedBox(height: 12),
                Text('재고관리는 신청한 매장만 쓸 수 있어요', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('직원이 휴대폰으로 창고를 돌며 재고 숫자를 입력하고, 여기서 바로 확인하는 기능이에요.\n고도리 운영자에게 신청해 주세요.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, height: 1.5)),
              ]),
            ),
          ),
        ),
      );

  // ───────────────────────── 조사 결과 ─────────────────────────

  Widget _resultsTab(bool narrow) {
    final counts = _counts!;
    if (counts.isEmpty) {
      return _emptyCard(
        Icons.receipt_long_outlined,
        '아직 재고 조사 기록이 없어요',
        (_items ?? []).isEmpty
            ? '먼저 [재고 항목]에서 셀 항목을 만들고, 직원 휴대폰 재고 앱에서 [재고 조사 시작]을 눌러 주세요.'
            : '직원 휴대폰 재고 앱에서 [재고 조사 시작]을 누르면 여기에 바로 보여요.',
        action: (_items ?? []).isEmpty ? TextButton(onPressed: () => setState(() => _tab = 1), child: const Text('재고 항목 만들기')) : null,
      );
    }
    final selected = counts.firstWhere((c) => c.id == _selectedId, orElse: () => counts.first);
    final detail = _countDetail(selected, previousDoneCount(counts, selected), narrow);
    if (narrow || MediaQuery.sizeOf(context).width < 1100) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          key: ValueKey(selected.id),
          initialValue: selected.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '조사 고르기', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white),
          items: [
            for (final c in counts)
              DropdownMenuItem(value: c.id, child: Text('${c.title}${c.isOpen ? ' · 진행 중' : ''}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _selectedId = v),
        ),
        const SizedBox(height: 12),
        Expanded(child: detail),
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: 300,
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final c in counts) _countTile(c, c.id == selected.id),
            ],
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(child: detail),
    ]);
  }

  Widget _countTile(StockCount c, bool selected) {
    final total = c.isOpen ? (_items ?? []).where((e) => e.active).length : (c.itemCount > 0 ? c.itemCount : c.counts.length);
    return ListTile(
      selected: selected,
      selectedTileColor: kAdminAccentSoft,
      selectedColor: kAdminAccent,
      title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([
        stockTime(c.startedAt),
        if (c.counter.isNotEmpty) c.counter,
        '${c.counts.length}/$total개',
      ].where((e) => e.isNotEmpty).join(' · ')),
      trailing: c.isOpen ? _chip('진행 중', _orange) : null,
      onTap: () => setState(() => _selectedId = c.id),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      );

  Widget _countDetail(StockCount c, StockCount? prev, bool narrow) {
    final live = {for (final it in _items!) it.id: it};
    // 보여 줄 항목: 진행 중이면 지금 쓰는 항목 전부, 끝났으면 그때 저장한 항목(+ 숫자가 있는 항목)
    final rows = <({String id, String name, String unit, String category, num? min})>[];
    final seen = <String>{};
    void add(String id) {
      if (!seen.add(id)) return;
      final snap = c.items[id];
      final it = live[id];
      rows.add((
        id: id,
        name: c.nameOf(id, live),
        unit: c.unitOf(id, live),
        category: ((snap?['category'] ?? it?.category ?? '').toString().trim().isEmpty ? '기타' : (snap?['category'] ?? it?.category).toString()),
        min: snap?['minQty'] is num ? snap!['minQty'] as num : it?.minQty,
      ));
    }

    if (c.isOpen || c.items.isEmpty) {
      for (final it in _items!) {
        if (it.active || c.counts.containsKey(it.id)) add(it.id);
      }
    } else {
      for (final it in _items!) {
        if (c.items.containsKey(it.id)) add(it.id);
      }
      for (final id in c.items.keys) {
        add(id);
      }
    }
    for (final id in c.counts.keys) {
      add(id);
    }
    final lowCount = rows.where((r) => stockLow(c.counts[r.id], r.min)).length;
    final emptyCount = rows.where((r) => !c.counts.containsKey(r.id)).length;
    final shown = rows.where((r) {
      if (_filter == 'low') return stockLow(c.counts[r.id], r.min);
      if (_filter == 'empty') return !c.counts.containsKey(r.id);
      return true;
    }).toList();
    final groups = <String, List<({String id, String name, String unit, String category, num? min})>>{};
    for (final r in shown) {
      groups.putIfAbsent(r.category, () => []).add(r);
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: EdgeInsets.all(narrow ? 14 : 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(c.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            c.isOpen ? _chip('진행 중 · 실시간', _orange) : _chip('완료', _green),
            if (c.pending) _chip('저장 중', Colors.black45),
          ]),
          const SizedBox(height: 6),
          Text(
            [
              if (c.counter.isNotEmpty) '센 사람 ${c.counter}${c.startedBy == 'owner' ? '(사장님)' : ''}',
              if (c.startedAt != null) '시작 ${stockTime(c.startedAt)}',
              if (c.finishedAt != null) '끝 ${stockTime(c.finishedAt)}',
              '입력 ${rows.length - emptyCount}/${rows.length}개',
              if (prev != null) '비교: ${prev.title}',
            ].join('  ·  '),
            style: const TextStyle(color: Colors.black54),
          ),
          if (c.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('메모: ${c.note}', style: const TextStyle(color: Colors.black87)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(label: Text('전체 ${rows.length}'), selected: _filter == 'all', onSelected: (_) => setState(() => _filter = 'all')),
            ChoiceChip(
              label: Text('부족 $lowCount'),
              selected: _filter == 'low',
              labelStyle: TextStyle(color: lowCount > 0 ? _red : null, fontWeight: FontWeight.w600),
              onSelected: (_) => setState(() => _filter = 'low'),
            ),
            ChoiceChip(label: Text('안 센 것 $emptyCount'), selected: _filter == 'empty', onSelected: (_) => setState(() => _filter = 'empty')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('엑셀용 복사'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: stockCountTable(c, _items!, previous: prev)));
                _toast('복사했어요. 엑셀·구글 시트에 붙여넣기(Ctrl+V) 하세요.');
              },
            ),
            if (!c.isOpen)
              TextButton.icon(
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('다시 열기'),
                onPressed: () => showBusyConfirm(
                  context,
                  title: '조사를 다시 열까요?',
                  message: '직원 재고 앱에서 이 조사의 숫자를 다시 고칠 수 있게 돼요. 다 고친 뒤 앱에서 [조사 끝내기]를 다시 눌러 주세요.',
                  confirmLabel: '다시 열기',
                  danger: false,
                  action: () => StockService.reopen(c.id),
                ),
              ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18, color: _red),
              label: const Text('지우기', style: TextStyle(color: _red)),
              onPressed: () async {
                final ok = await showBusyConfirm(
                  context,
                  title: '이 조사 기록을 지울까요?',
                  message: '${c.title}의 숫자 ${c.counts.length}개가 모두 지워지고 되돌릴 수 없어요.',
                  action: () => StockService.deleteCount(c.id),
                );
                if (ok && mounted) setState(() => _selectedId = null);
              },
            ),
          ]),
          const Divider(height: 24),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(_filter == 'low' ? '적정 재고보다 적은 항목이 없어요.' : _filter == 'empty' ? '모두 셌어요.' : '항목이 없어요.',
                        style: const TextStyle(color: Colors.black45)))
                : ListView(children: [
                    if (!narrow) _resultHeader(),
                    for (final g in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                        child: Text(g.key, style: const TextStyle(fontWeight: FontWeight.bold, color: kAdminAccent)),
                      ),
                      for (final r in g.value) _resultRow(r.name, r.unit, c.counts[r.id], prev?.counts[r.id], r.min, narrow),
                    ],
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _resultHeader() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: DefaultTextStyle(
          style: TextStyle(color: Colors.black45, fontSize: 12, fontWeight: FontWeight.w600),
          child: Row(children: [
            Expanded(child: Text('항목')),
            SizedBox(width: 110, child: Text('수량', textAlign: TextAlign.right)),
            SizedBox(width: 80, child: Text('직전', textAlign: TextAlign.right)),
            SizedBox(width: 80, child: Text('차이', textAlign: TextAlign.right)),
            SizedBox(width: 90, child: Text('적정 재고', textAlign: TextAlign.right)),
          ]),
        ),
      );

  Widget _resultRow(String name, String unit, num? value, num? before, num? min, bool narrow) {
    final low = stockLow(value, min);
    final diff = stockDiffText(value, before);
    final valueText = value == null ? '안 셈' : '${stockNum(value)} $unit';
    final valueStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: value == null ? Colors.black38 : low ? _red : Colors.black87,
    );
    Color diffColor() => diff == null || diff == '0' ? Colors.black45 : diff.startsWith('+') ? _green : _red;
    if (narrow) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: low ? _red.withValues(alpha: 0.06) : null,
          border: const Border(bottom: BorderSide(color: Color(0xFFEDEFF2))),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                [
                  if (before != null) '직전 ${stockNum(before)}',
                  if (min != null) '적정 ${stockNum(min)}',
                  if (low) '부족',
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: low ? _red : Colors.black45),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(valueText, style: valueStyle),
            if (diff != null) Text(diff, style: TextStyle(fontSize: 12, color: diffColor(), fontWeight: FontWeight.w600)),
          ]),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: low ? _red.withValues(alpha: 0.06) : null,
        border: const Border(bottom: BorderSide(color: Color(0xFFEDEFF2))),
      ),
      child: Row(children: [
        Expanded(
          child: Row(children: [
            Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            if (low) ...[const SizedBox(width: 8), _chip('부족', _red)],
          ]),
        ),
        SizedBox(width: 110, child: Text(valueText, textAlign: TextAlign.right, style: valueStyle)),
        SizedBox(width: 80, child: Text(before == null ? '-' : stockNum(before), textAlign: TextAlign.right, style: const TextStyle(color: Colors.black54))),
        SizedBox(
          width: 80,
          child: Text(diff ?? '-', textAlign: TextAlign.right, style: TextStyle(color: diffColor(), fontWeight: FontWeight.w600)),
        ),
        SizedBox(width: 90, child: Text(min == null ? '-' : stockNum(min), textAlign: TextAlign.right, style: const TextStyle(color: Colors.black54))),
      ]),
    );
  }

  Widget _emptyCard(IconData icon, String title, String message, {Widget? action}) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 44, color: kAdminAccent),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, height: 1.5)),
                if (action != null) ...[const SizedBox(height: 12), action],
              ]),
            ),
          ),
        ),
      );

  // ───────────────────────── 재고 항목 ─────────────────────────

  Widget _itemsTab(bool narrow) {
    final items = _items!;
    final groups = groupStockItems(items);
    return ListView(children: [
      _appInfoCard(),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: kAdminAccent, foregroundColor: Colors.white),
          icon: const Icon(Icons.add),
          label: const Text('항목 추가'),
          onPressed: () => _editItem(null),
        ),
        OutlinedButton.icon(icon: const Icon(Icons.playlist_add), label: const Text('한꺼번에 추가'), onPressed: _bulkAdd),
      ]),
      const SizedBox(height: 12),
      if (items.isEmpty)
        _emptyCard(Icons.inventory_2_outlined, '재고 항목이 없어요', '[항목 추가] 또는 [한꺼번에 추가]로 직원이 셀 항목(콜라, 컵, 휴지…)을 만들어 주세요.')
      else
        for (final g in groups)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('${g.key}  ${g.value.length}개', style: const TextStyle(fontWeight: FontWeight.bold, color: kAdminAccent)),
                ),
                for (var i = 0; i < g.value.length; i++) _itemRow(g.value, i, narrow),
              ]),
            ),
          ),
    ]);
  }

  Widget _appInfoCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kAdminAccentSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: kAdminAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '직원 휴대폰 재고 앱 로그인: 매장 아이디 ${StoreScope.isSet ? StoreScope.id : ''} + 패드 비밀번호\n'
              '사장님은 관리자 웹 비밀번호로 로그인하면 앱에서도 결과를 볼 수 있어요.\n'
              '여기서 항목을 바꾸면 앱에 바로 반영돼요. 숨긴 항목은 앱에 안 나와요.',
              style: const TextStyle(height: 1.6),
            ),
          ),
        ]),
      );

  Widget _itemRow(List<StockItem> list, int i, bool narrow) {
    final it = list[i];
    return ListTile(
        dense: narrow,
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: '위로',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: i == 0 ? null : () => _swap(list[i - 1], it),
          ),
          IconButton(
            tooltip: '아래로',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed: i == list.length - 1 ? null : () => _swap(it, list[i + 1]),
          ),
        ]),
        title: Row(children: [
          Flexible(child: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          if (!it.active) ...[const SizedBox(width: 8), _chip('숨김 · 앱에 안 나옴', Colors.black54)],
        ]),
        subtitle: Text([
          '단위 ${it.unit}',
          if (it.minQty != null) '적정 재고 ${stockNum(it.minQty)}',
          if (it.memo.isNotEmpty) it.memo,
        ].join(' · ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: '고치기', icon: const Icon(Icons.edit_outlined), onPressed: () => _editItem(it)),
          IconButton(
            tooltip: '지우기',
            icon: const Icon(Icons.delete_outline, color: _red),
            onPressed: () => showBusyConfirm(
              context,
              title: '\'${it.name}\'을(를) 지울까요?',
              message: '재고 앱 목록에서 빠져요. 지난 조사 기록의 숫자는 그대로 남아요. (잠깐 빼 두려면 지우지 말고 [고치기] → \'앱에 보이기\'를 끄세요)',
              action: () => StockService.deleteItem(it.id),
            ),
          ),
        ]),
    );
  }

  Future<void> _swap(StockItem a, StockItem b) async {
    try {
      await StockService.swapOrder(a, b);
    } catch (e) {
      _toast('순서를 바꾸지 못했어요: $e');
    }
  }

  Future<void> _editItem(StockItem? it) async {
    final name = TextEditingController(text: it?.name ?? '');
    final category = TextEditingController(text: it?.category ?? '');
    final unit = TextEditingController(text: it?.unit ?? '개');
    final min = TextEditingController(text: it?.minQty == null ? '' : '${it!.minQty}');
    final memo = TextEditingController(text: it?.memo ?? '');
    var active = it?.active ?? true;
    var busy = false;
    String? error;
    final categories = {for (final e in _items ?? const <StockItem>[]) if (e.category.isNotEmpty) e.category}.toList();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> save() async {
          final n = name.text.trim();
          final m = parseStockInput(min.text);
          if (n.isEmpty) { setD(() => error = '이름을 써 주세요.'); return; }
          if (n.length > 60) { setD(() => error = '이름은 60자까지예요.'); return; }
          if (!m.ok) { setD(() => error = '적정 재고는 0 이상 숫자로 써 주세요. (소수점 둘째 자리까지)'); return; }
          if (unit.text.trim().length > 10) { setD(() => error = '단위는 10자까지예요.'); return; }
          setD(() {
            busy = true;
            error = null;
          });
          try {
            await StockService.saveItem(
              id: it?.id,
              name: n,
              category: category.text,
              unit: unit.text,
              minQty: m.value,
              active: active,
              memo: memo.text,
            );
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            setD(() {
              busy = false;
              error = '저장하지 못했어요: $e';
            });
          }
        }

        return PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: Text(it == null ? '재고 항목 추가' : '재고 항목 고치기', style: const TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: adminDialogWidth(ctx, 460),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: name,
                    readOnly: busy,
                    decoration: const InputDecoration(labelText: '이름 *', hintText: '예: 콜라 355ml', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: category,
                    readOnly: busy,
                    decoration: const InputDecoration(labelText: '카테고리 (창고 위치·종류)', hintText: '예: 음료 냉장고', border: OutlineInputBorder()),
                  ),
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final c in categories)
                        ActionChip(label: Text(c), onPressed: busy ? null : () => setD(() => category.text = c)),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: unit,
                    readOnly: busy,
                    decoration: const InputDecoration(labelText: '단위', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final u in _units) ActionChip(label: Text(u), onPressed: busy ? null : () => setD(() => unit.text = u)),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: min,
                    readOnly: busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '적정 재고 (선택)',
                      helperText: '센 숫자가 이보다 적으면 \'부족\'으로 빨갛게 보여요.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: memo,
                    readOnly: busy,
                    decoration: const InputDecoration(labelText: '메모 (선택)', hintText: '예: 창고 왼쪽 선반 2칸', border: OutlineInputBorder()),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    activeTrackColor: kAdminAccent,
                    title: const Text('재고 앱에 보이기'),
                    subtitle: const Text('끄면 앱 목록에서 빠져요 (지우지 않고 잠깐 빼 둘 때)'),
                    onChanged: busy ? null : (v) => setD(() => active = v),
                  ),
                  if (error != null) Text(error!, style: const TextStyle(color: _red, fontSize: 13)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('취소')),
              ElevatedButton(
                onPressed: busy ? null : save,
                style: busyButtonStyle(kAdminAccent),
                child: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _bulkAdd() async {
    final text = TextEditingController();
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final rows = parseStockBulk(text.text);
        Future<void> run() async {
          if (rows.isEmpty) { setD(() => error = '추가할 항목이 없어요.'); return; }
          setD(() {
            busy = true;
            error = null;
          });
          try {
            final n = await StockService.addMany(rows, _items ?? const []);
            if (ctx.mounted) Navigator.pop(ctx);
            _toast(n == rows.length ? '$n개를 추가했어요.' : '$n개를 추가했어요. (이미 있는 ${rows.length - n}개는 건너뜀)');
          } catch (e) {
            setD(() {
              busy = false;
              error = '추가하지 못했어요: $e';
            });
          }
        }

        return PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: const Text('재고 항목 한꺼번에 추가', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: adminDialogWidth(ctx, 560),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                  '한 줄에 하나씩: 이름 | 단위 | 적정 재고 (단위·적정 재고는 빼도 돼요)\n'
                  '\'# 카테고리\' 줄 아래 항목은 그 카테고리로 들어가요. \'//\'로 시작하면 메모.',
                  style: TextStyle(color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: text,
                  readOnly: busy,
                  minLines: 10,
                  maxLines: 16,
                  onChanged: (_) => setD(() {}),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '# 음료 냉장고\n콜라 | 캔 | 24\n사이다 | 캔 | 24\n\n# 소모품\n종이컵 | 줄 | 5\n물티슈 | 팩',
                  ),
                ),
                const SizedBox(height: 8),
                Text('읽은 항목 ${rows.length}개', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (error != null) Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(error!, style: const TextStyle(color: _red, fontSize: 13)),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('취소')),
              ElevatedButton(
                onPressed: busy || rows.isEmpty ? null : run,
                style: busyButtonStyle(kAdminAccent),
                child: Text('${rows.length}개 추가', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }),
    );
  }
}
