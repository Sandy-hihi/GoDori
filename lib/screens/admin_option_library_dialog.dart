import 'package:flutter/material.dart';

import 'package:boardpad/services/option_library.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/translate_sync.dart';
import 'package:boardpad/widgets/admin_colors.dart';

/// 관리자 웹 메뉴 관리 [옵션 관리] 창 (106차)
///   왼쪽: 옵션 그룹 목록(↑↓ = 손님 패드에 나오는 순서) · 새 그룹 · 지금 메뉴 옵션 가져오기
///   오른쪽: 고른 그룹 편집 — 이름·필수·최대 고르기 개수·선택지(값·품절·순서)·붙일 곳(카테고리·개별 메뉴)·뺀 메뉴·적용 메뉴 미리보기
///   저장하면 settings/optionLibrary 를 쓰고 붙는 메뉴들의 optionGroups 복사본을 다시 채움 → 자동 번역
class OptionLibraryDialog extends StatefulWidget {
  const OptionLibraryDialog({super.key});

  static Future<void> open(BuildContext context) =>
      showDialog(context: context, barrierDismissible: false, builder: (_) => const OptionLibraryDialog());

  @override
  State<OptionLibraryDialog> createState() => _OptionLibraryDialogState();
}

class _MenuBrief {
  final String id;
  final String name;
  final String category;
  final List<Map<String, dynamic>> ownGroups; // 메뉴 전용 옵션(libraryId 없음)
  const _MenuBrief(this.id, this.name, this.category, this.ownGroups);
}

class _OptionLibraryDialogState extends State<OptionLibraryDialog> {
  bool _loading = true;
  String? _error;
  bool _saving = false;
  List<OptionLibGroup> _groups = [];
  String _initial = '';
  int _sel = 0;
  List<_MenuBrief> _menus = [];
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lib = await OptionLibrary.load();
      final menuSnap = await StoreScope.col('menus').orderBy('timestamp').get();
      final catSnap = await StoreScope.col('settings').doc('categories').get();
      if (!mounted) return;
      setState(() {
        _groups = lib;
        _initial = _key();
        _menus = [
          for (final d in menuSnap.docs)
            _MenuBrief(
              d.id,
              '${d.data()['name'] ?? '이름 없음'}',
              '${d.data()['category'] ?? ''}',
              [
                for (final g in (d.data()['optionGroups'] as List? ?? const []))
                  if (g is Map && !isLibraryGroup(g)) Map<String, dynamic>.from(g),
              ],
            ),
        ];
        _categories = [for (final c in ((catSnap.data() ?? const {})['list'] as List? ?? const [])) '$c'];
        for (final m in _menus) {
          if (m.category.isNotEmpty && !_categories.contains(m.category)) _categories.add(m.category);
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '불러오지 못했어요. ($e)';
          _loading = false;
        });
      }
    }
  }

  String _key() => [for (final g in _groups) g.toJson()].toString();
  bool get _dirty => _key() != _initial;
  OptionLibGroup? get _cur => _groups.isEmpty ? null : _groups[_sel.clamp(0, _groups.length - 1).toInt()];
  _MenuBrief? _menu(String id) {
    for (final m in _menus) {
      if (m.id == id) return m;
    }
    return null;
  }

  List<_MenuBrief> _appliedMenus(OptionLibGroup g) => [for (final m in _menus) if (g.attachedTo(m.id, m.category)) m];

  String? _problem() {
    for (final g in _groups) {
      final label = g.name.trim().isEmpty ? '이름 없는 그룹' : "'${g.name.trim()}'";
      if (g.name.trim().isEmpty) return '옵션 그룹 이름을 넣어 주세요.';
      final opts = g.options.where((o) => o.name.trim().isNotEmpty).toList();
      if (opts.isEmpty) return '$label에 선택지를 하나 이상 넣어 주세요.';
      final names = opts.map((o) => o.name.trim()).toList();
      if (names.toSet().length != names.length) return '$label에 이름이 같은 선택지가 있어요.';
      if (g.maxSelect > opts.length) return '$label의 최대 고르기 개수가 선택지 수보다 많아요.';
    }
    return null;
  }

  Future<void> _save() async {
    final p = _problem();
    if (p != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(p)));
      return;
    }
    setState(() => _saving = true);
    try {
      for (final g in _groups) {
        g.options.removeWhere((o) => o.name.trim().isEmpty);
      }
      await OptionLibrary.save(_groups);
      final n = await OptionLibrary.syncMenus(groups: _groups);
      TranslateSync.kick(); // 손님 패드 자동 번역 (새 옵션 이름)
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('옵션을 저장했어요.${n > 0 ? ' 메뉴 $n개에 반영했어요.' : ''}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장하지 못했어요: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('저장하지 않고 닫을까요?'),
        content: const Text('바꾼 내용이 사라져요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('계속 고치기')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('닫기', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context);
  }

  void _move(int i, int d) => setState(() {
        final g = _groups.removeAt(i);
        _groups.insert(i + d, g);
        if (_sel == i) _sel = i + d;
      });

  void _addGroup() => setState(() {
        _groups.add(OptionLibGroup(name: '', options: [OptionLibChoice(name: '')]));
        _sel = _groups.length - 1;
      });

  Future<void> _deleteGroup(OptionLibGroup g) async {
    final n = _appliedMenus(g).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("'${g.name.trim().isEmpty ? '이름 없는 그룹' : g.name.trim()}' 그룹을 지울까요?"),
        content: Text(n == 0 ? '저장하면 지워져요.' : '저장하면 이 옵션이 들어간 메뉴 $n개에서도 빠져요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('지우기', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _groups.remove(g);
      if (_sel >= _groups.length) _sel = _groups.isEmpty ? 0 : _groups.length - 1;
    });
  }

  // ── 지금 메뉴 옵션 가져오기: 메뉴마다 따로 넣은 옵션 중 모양이 같은 것을 묶어 목록으로 ──
  Future<void> _import() async {
    final bySig = <String, ({Map<String, dynamic> sample, List<_MenuBrief> menus})>{};
    for (final m in _menus) {
      for (final g in m.ownGroups) {
        final sig = ownGroupSignature(g);
        final cur = bySig[sig];
        if (cur == null) {
          bySig[sig] = (sample: g, menus: [m]);
        } else if (!cur.menus.contains(m)) {
          cur.menus.add(m);
        }
      }
    }
    final already = {for (final g in _groups) if (g.importSig != null) g.importSig!};
    final cands = bySig.entries.where((e) => !already.contains(e.key)).toList()
      ..sort((a, b) => b.value.menus.length.compareTo(a.value.menus.length));
    if (cands.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('가져올 메뉴 전용 옵션이 없어요.')));
      return;
    }
    final picked = {for (final e in cands) if (e.value.menus.length >= 2) e.key};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('지금 메뉴 옵션 가져오기'),
          content: SizedBox(
            width: 620,
            height: 460,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                '메뉴마다 따로 넣은 옵션 중 이름·선택지·값이 같은 것을 하나로 묶었어요. 고른 것은 옵션 목록 그룹이 되고, '
                '저장하면 그 메뉴들의 옵션이 목록 옵션으로 바뀌어요(손님에게 보이는 내용은 같아요). '
                '한 카테고리 메뉴 전부에 있으면 카테고리로 붙여요.',
                style: TextStyle(color: Colors.black54, height: 1.5, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(children: [
                  for (final e in cands)
                    CheckboxListTile(
                      dense: true,
                      value: picked.contains(e.key),
                      activeColor: kAdminAccent,
                      onChanged: (v) => setD(() => v == true ? picked.add(e.key) : picked.remove(e.key)),
                      title: Text(
                        '${e.value.sample['groupName'] ?? ''}${e.value.sample['isRequired'] == true ? ' (필수)' : ''} · '
                        '${[for (final o in (e.value.sample['options'] as List? ?? const [])) if (o is Map) '${o['name']}${(int.tryParse('${o['price'] ?? 0}') ?? 0) > 0 ? ' +${o['price']}' : ''}'].join(', ')}',
                      ),
                      subtitle: Text(
                        '메뉴 ${e.value.menus.length}개: ${e.value.menus.take(6).map((m) => m.name).join(', ')}${e.value.menus.length > 6 ? ' …' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
            FilledButton(
              onPressed: picked.isEmpty ? null : () => Navigator.pop(c, true),
              style: FilledButton.styleFrom(backgroundColor: kAdminAccent),
              child: Text('${picked.length}개 가져오기'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      for (final e in cands.where((e) => picked.contains(e.key))) {
        final s = e.value.sample;
        final ids = {for (final m in e.value.menus) m.id};
        // 카테고리 메뉴 전부에 있으면 카테고리로
        final cats = <String>[];
        for (final c in {for (final m in e.value.menus) m.category}) {
          final inCat = _menus.where((m) => m.category == c).toList();
          if (c.isNotEmpty && inCat.every((m) => ids.contains(m.id))) {
            cats.add(c);
            ids.removeAll(inCat.map((m) => m.id));
          }
        }
        _groups.add(OptionLibGroup(
          name: '${s['groupName'] ?? ''}'.trim(),
          isRequired: s['isRequired'] == true,
          maxSelect: (int.tryParse('${s['maxSelect'] ?? 1}') ?? 1).clamp(1, 99).toInt(),
          options: [
            for (final o in (s['options'] as List? ?? const []))
              if (o is Map) OptionLibChoice(name: '${o['name'] ?? ''}'.trim(), price: int.tryParse('${o['price'] ?? 0}') ?? 0),
          ],
          categories: cats,
          menuIds: ids.toList(),
          importSig: e.key,
        ));
      }
      _sel = _groups.length - 1;
    });
  }

  // ── 개별 메뉴 고르기 ──
  Future<void> _pickMenus(OptionLibGroup g) async {
    final chosen = {...g.menuIds};
    var q = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          final list = _menus
              .where((m) => q.trim().isEmpty || m.name.contains(q.trim()) || m.category.contains(q.trim()))
              .toList();
          return AlertDialog(
            title: const Text('붙일 메뉴 고르기'),
            content: SizedBox(
              width: 480,
              height: 480,
              child: Column(children: [
                TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '메뉴 이름·카테고리 찾기',
                    prefixIcon: Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setD(() => q = v),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(children: [
                    for (final m in list)
                      if (g.categories.contains(m.category))
                        ListTile(
                          dense: true,
                          enabled: false,
                          leading: const Icon(Icons.check_box, color: Colors.black26),
                          title: Text(m.name),
                          subtitle: Text("카테고리 '${m.category}'로 들어가요"),
                        )
                      else
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: kAdminAccent,
                          value: chosen.contains(m.id),
                          onChanged: (v) => setD(() => v == true ? chosen.add(m.id) : chosen.remove(m.id)),
                          title: Text(m.name),
                          subtitle: Text(m.category.isEmpty ? '카테고리 없음' : m.category),
                        ),
                  ]),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(backgroundColor: kAdminAccent),
                child: Text('${chosen.length}개 고르기'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        g.menuIds = [for (final m in _menus) if (chosen.contains(m.id)) m.id];
        g.excludeMenuIds.removeWhere(chosen.contains);
      });
    }
  }

  // ── 화면 ──
  Widget _section(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          if (sub != null) Text(sub, style: const TextStyle(color: Colors.black45, fontSize: 12)),
        ]),
      );

  Widget _leftPane() {
    return Container(
      width: 270,
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE5E7EB)))),
      child: Column(children: [
        Expanded(
          child: _groups.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('아직 옵션 그룹이 없어요.\n아래에서 새로 만들거나 지금 메뉴 옵션을 가져오세요.',
                      style: TextStyle(color: Colors.black45, height: 1.5)),
                )
              : ListView.builder(
                  itemCount: _groups.length,
                  itemBuilder: (_, i) {
                    final g = _groups[i];
                    final on = i == _sel;
                    return Material(
                      color: on ? const Color(0xFFEAF0F7) : Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _sel = i),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(
                                  '${g.name.trim().isEmpty ? '(이름 없음)' : g.name.trim()}${g.isRequired ? ' *' : ''}',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: on ? kAdminAccent : Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '선택지 ${g.options.length}개 · 메뉴 ${_appliedMenus(g).length}개'
                                  '${g.options.any((o) => o.soldOut) ? ' · 품절 있음' : ''}',
                                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                                ),
                              ]),
                            ),
                            IconButton(
                              tooltip: '위로',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.arrow_upward, size: 18),
                              color: kAdminAccent,
                              onPressed: i == 0 ? null : () => _move(i, -1),
                            ),
                            IconButton(
                              tooltip: '아래로',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.arrow_downward, size: 18),
                              color: kAdminAccent,
                              onPressed: i == _groups.length - 1 ? null : () => _move(i, 1),
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : _addGroup,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('새 옵션 그룹'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _saving ? null : _import,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('지금 메뉴 옵션 가져오기'),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _choiceRow(OptionLibGroup g, int i) {
    final o = g.options[i];
    return Padding(
      key: ValueKey(o.uid),
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            initialValue: o.name,
            decoration: InputDecoration(
              isDense: true,
              hintText: '선택지 이름 (예: ICE)',
              border: const OutlineInputBorder(),
              fillColor: o.soldOut ? const Color(0xFFF3F4F6) : null,
              filled: o.soldOut,
            ),
            onChanged: (v) => setState(() => o.name = v),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: TextFormField(
            initialValue: o.price == 0 ? '' : '${o.price}',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(isDense: true, hintText: '0', suffixText: '원', border: OutlineInputBorder()),
            onChanged: (v) => setState(() => o.price = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0),
          ),
        ),
        const SizedBox(width: 8),
        Text('품절', style: TextStyle(fontSize: 13, color: o.soldOut ? Colors.red : Colors.black45)),
        Switch(
          value: o.soldOut,
          activeThumbColor: Colors.red,
          onChanged: (v) => setState(() => o.soldOut = v),
        ),
        IconButton(
          tooltip: '위로',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_upward, size: 18),
          color: kAdminAccent,
          onPressed: i == 0 ? null : () => setState(() => g.options.insert(i - 1, g.options.removeAt(i))),
        ),
        IconButton(
          tooltip: '아래로',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_downward, size: 18),
          color: kAdminAccent,
          onPressed: i == g.options.length - 1 ? null : () => setState(() => g.options.insert(i + 1, g.options.removeAt(i))),
        ),
        IconButton(
          tooltip: '지우기',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.redAccent),
          onPressed: () => setState(() {
            g.options.removeAt(i);
            if (g.maxSelect > g.options.length && g.options.isNotEmpty) g.maxSelect = g.options.length;
          }),
        ),
      ]),
    );
  }

  Widget _editor(OptionLibGroup g) {
    final applied = _appliedMenus(g);
    final maxChoices = g.options.where((o) => o.name.trim().isNotEmpty).length.clamp(1, 20).toInt();
    return ListView(
      key: ValueKey(g.id),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Row(children: [
          Expanded(
            child: TextFormField(
              initialValue: g.name,
              decoration: const InputDecoration(
                labelText: '옵션 그룹 이름 (예: 온도, 샷 추가)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => g.name = v),
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _saving ? null : () => _deleteGroup(g),
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            label: const Text('그룹 지우기', style: TextStyle(color: Colors.redAccent)),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 24, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(value: g.isRequired, activeColor: kAdminAccent, onChanged: (v) => setState(() => g.isRequired = v ?? false)),
            const Text('필수 (손님이 꼭 골라야 해요)'),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('한 번에 고를 수 있는 개수  '),
            DropdownButton<int>(
              value: g.maxSelect.clamp(1, maxChoices).toInt(),
              items: [
                for (var n = 1; n <= maxChoices; n++)
                  DropdownMenuItem(value: n, child: Text(n == 1 ? '1개 (하나만)' : '최대 $n개')),
              ],
              onChanged: (v) => setState(() => g.maxSelect = v ?? 1),
            ),
          ]),
        ]),
        _section('선택지', '품절을 켜면 손님 패드에서 흐리게 보이고 고를 수 없어요. ↑↓ 순서대로 보여요.'),
        for (var i = 0; i < g.options.length; i++) _choiceRow(g, i),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => g.options.add(OptionLibChoice(name: ''))),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('선택지 추가'),
          ),
        ),
        _section('붙일 카테고리', '고른 카테고리의 메뉴 전부에 들어가요. 나중에 그 카테고리에 추가하는 메뉴에도 들어가요.'),
        if (_categories.isEmpty) const Text('카테고리가 없어요.', style: TextStyle(color: Colors.black45)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _categories)
            FilterChip(
              label: Text(c),
              selected: g.categories.contains(c),
              showCheckmark: false,
              selectedColor: kAdminAccent,
              labelStyle: TextStyle(color: g.categories.contains(c) ? Colors.white : Colors.black87),
              onSelected: (v) => setState(() {
                if (v) {
                  g.categories.add(c);
                } else {
                  g.categories.remove(c);
                }
              }),
            ),
        ]),
        _section('개별 메뉴', '카테고리와 상관없이 이 메뉴들에도 넣어요.'),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final id in g.menuIds)
            if (_menu(id) != null)
              InputChip(
                label: Text(_menu(id)!.name),
                onDeleted: () => setState(() => g.menuIds.remove(id)),
              ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('메뉴 고르기'),
            onPressed: () => _pickMenus(g),
          ),
        ]),
        if (g.excludeMenuIds.any((id) => _menu(id) != null)) ...[
          _section('이 메뉴에서는 뺐어요', "메뉴 수정 창의 '이 메뉴에서 빼기'로 뺀 메뉴예요."),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final id in g.excludeMenuIds)
              if (_menu(id) != null)
                InputChip(
                  label: Text(_menu(id)!.name),
                  deleteIcon: const Icon(Icons.undo, size: 18),
                  deleteButtonTooltipMessage: '다시 넣기',
                  onDeleted: () => setState(() => g.excludeMenuIds.remove(id)),
                ),
          ]),
        ],
        _section('들어가는 메뉴 ${applied.length}개'),
        if (applied.isEmpty)
          const Text('아직 붙은 메뉴가 없어요. 위에서 카테고리나 메뉴를 골라 주세요.', style: TextStyle(color: Colors.orange))
        else
          Text(applied.map((m) => m.name).join(', '), style: const TextStyle(color: Colors.black54, height: 1.6)),
        if (g.importSig != null)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('가져온 그룹이에요. 저장하면 이 메뉴들에 따로 있던 같은 옵션이 이 그룹으로 바뀌어요.',
                style: TextStyle(color: kAdminAccent, fontSize: 12)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final g = _cur;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: size.width < 1080 ? size.width - 48 : 1032,
        height: size.height * 0.86,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
            child: Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('옵션 관리', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text('옵션을 한 번 만들어 두고 카테고리나 메뉴에 붙여요. 여기서 고치면 붙은 메뉴 전부에 반영돼요.',
                      style: TextStyle(color: Colors.black54, fontSize: 13)),
                ]),
              ),
              IconButton(onPressed: _saving ? null : _close, icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _leftPane(),
                        Expanded(
                          child: g == null
                              ? const Center(child: Text('왼쪽에서 그룹을 고르거나 새로 만들어 주세요.', style: TextStyle(color: Colors.black45)))
                              : _editor(g),
                        ),
                      ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Row(children: [
              Expanded(
                child: Text(_dirty ? '저장하지 않은 변경이 있어요.' : '', style: const TextStyle(color: Colors.orange, fontSize: 13)),
              ),
              TextButton(
                onPressed: _saving ? null : _close,
                child: const Text('닫기', style: TextStyle(color: Colors.grey, fontSize: 16)),
              ),
              const SizedBox(width: 8),
              // 처리 중엔 글자는 그대로, 버튼만 흐리게 (100차)
              FilledButton(
                onPressed: _saving || _loading || !_dirty ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: kAdminAccent,
                  disabledBackgroundColor: kAdminAccent.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                ),
                child: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
