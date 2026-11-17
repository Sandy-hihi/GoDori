import 'package:flutter/material.dart';
import 'package:boardpad/services/sold_out_schedule.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/widgets/admin_busy_dialog.dart';
import 'package:boardpad/widgets/admin_colors.dart';
import 'package:boardpad/widgets/admin_dialog_width.dart';

/// 메뉴 관리 [자동 품절] 창 (112차) — 정해 둔 시간에 손님 패드에서 메뉴를 품절로 보여 줌
/// 저장 모양·계산은 lib/services/sold_out_schedule.dart
class SoldOutScheduleDialog extends StatefulWidget {
  const SoldOutScheduleDialog({super.key});

  static Future<void> open(BuildContext context) =>
      showDialog(context: context, builder: (_) => const SoldOutScheduleDialog());

  @override
  State<SoldOutScheduleDialog> createState() => _SoldOutScheduleDialogState();
}

class _MenuLite {
  final String id;
  final String name;
  final String category;
  const _MenuLite(this.id, this.name, this.category);
}

class _SoldOutScheduleDialogState extends State<SoldOutScheduleDialog> {
  // 구독은 한 번만 (100차 규칙) — 30초마다도 다시 알려 줘서 '지금 품절 중' 표시가 바뀜
  late final Stream<List<SoldOutRule>> _rulesStream = SoldOutSchedule.watchTicking();
  List<_MenuLite> _menus = const [];
  List<String> _categories = const [];
  bool _loaded = false;
  final Set<String> _switching = {}; // 켜고 끄는 중인 규칙 (버튼 흐리게)

  @override
  void initState() {
    super.initState();
    _loadMenus();
  }

  Future<void> _loadMenus() async {
    try {
      final menuFuture = StoreScope.col('menus').get();
      final catSnap = await StoreScope.col('settings').doc('categories').get();
      final menuSnap = await menuFuture;
      final menus = <_MenuLite>[
        for (final d in menuSnap.docs)
          _MenuLite(d.id, (d.data()['name'] ?? '').toString(), (d.data()['category'] ?? '').toString()),
      ];
      final rawList = catSnap.data()?['list'];
      final cats = <String>[
        if (rawList is List)
          for (final c in rawList) c.toString(),
      ];
      // 목록에 없는 카테고리의 메뉴도 고를 수 있게 뒤에 붙임
      for (final m in menus) {
        if (m.category.isNotEmpty && !cats.contains(m.category)) cats.add(m.category);
      }
      if (!mounted) return;
      setState(() {
        _menus = menus;
        _categories = cats;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  int _menuCount(SoldOutRule r) => _menus.where((m) => r.appliesTo(m.id, m.category)).length;

  Future<void> _toggle(List<SoldOutRule> rules, SoldOutRule r, bool on) async {
    if (_switching.contains(r.id)) return;
    setState(() => _switching.add(r.id));
    try {
      await SoldOutSchedule.save([for (final x in rules) x.id == r.id ? x.copyWith(enabled: on) : x]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('바꾸지 못했어요: $e')));
    } finally {
      if (mounted) setState(() => _switching.remove(r.id));
    }
  }

  Future<void> _edit(List<SoldOutRule> rules, SoldOutRule? rule) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RuleEditor(
        rule: rule ?? SoldOutRule(id: 'r${DateTime.now().millisecondsSinceEpoch}', name: ''),
        isNew: rule == null,
        menus: _menus,
        categories: _categories,
        onSave: (r) async {
          final latest = await SoldOutSchedule.load(); // 그사이 다른 화면에서 바꿨을 수도 있어서 다시 읽음
          final exists = latest.any((x) => x.id == r.id);
          await SoldOutSchedule.save(exists ? [for (final x in latest) x.id == r.id ? r : x] : [...latest, r]);
        },
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('자동 품절 시간을 저장했어요. 손님 패드에 바로 반영돼요.')));
    }
  }

  Future<void> _delete(SoldOutRule r) async {
    await showBusyConfirm(
      context,
      title: '자동 품절 삭제',
      message: "'${r.name.isEmpty ? r.timeLabel : r.name}' 자동 품절을 지울까요?\n지금 이 규칙 때문에 품절로 보이던 메뉴는 바로 다시 팔아요.",
      errorText: '지우지 못했어요',
      action: () async {
        final latest = await SoldOutSchedule.load();
        await SoldOutSchedule.save([for (final x in latest) if (x.id != r.id) x]);
      },
    );
  }

  Widget _ruleCard(List<SoldOutRule> rules, SoldOutRule r, DateTime now) {
    final active = r.activeAt(now);
    final count = _menuCount(r);
    final where = [
      if (r.categories.isNotEmpty) '카테고리 ${r.categories.join(', ')}',
      if (r.menuIds.isNotEmpty) '메뉴 ${r.menuIds.length}개',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? Colors.orange.shade300 : Colors.grey.shade300, width: active ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(r.name.isEmpty ? '이름 없음' : r.name,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: r.enabled ? Colors.black87 : Colors.black38)),
                    if (active)
                      _badge('지금 품절 중 · ${r.untilLabel}', Colors.orange.shade800, Colors.orange.shade50)
                    else if (!r.enabled)
                      _badge('꺼짐', Colors.black45, Colors.grey.shade100),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${r.timeLabel} · ${r.daysLabel}', style: const TextStyle(color: kAdminAccent, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  where.isEmpty ? '붙은 메뉴가 없어요 — [수정]에서 카테고리나 메뉴를 골라 주세요' : '$where → 메뉴 $count개',
                  style: TextStyle(color: where.isEmpty ? Colors.redAccent : Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          Tooltip(
            message: r.enabled ? '끄기' : '켜기',
            child: Switch(
              value: r.enabled,
              activeTrackColor: kAdminAccent,
              onChanged: _switching.contains(r.id) ? null : (v) => _toggle(rules, r, v),
            ),
          ),
          IconButton(
            tooltip: '수정',
            icon: const Icon(Icons.edit, color: Colors.blue),
            onPressed: () => _edit(rules, r),
          ),
          IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _delete(r),
          ),
        ],
      ),
    );
  }

  static Widget _badge(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('자동 품절 시간', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: adminDialogWidth(context, 620),
        child: StreamBuilder<List<SoldOutRule>>(
          stream: _rulesStream,
          builder: (context, snap) {
            final rules = snap.data ?? const <SoldOutRule>[];
            final now = DateTime.now();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '정해 둔 시간에는 손님 패드에서 메뉴가 저절로 품절로 보이고, 시간이 지나면 다시 팔아요.\n'
                  '예: 주방 마감(22:00 ~ 다음 날 11:00) 음식 카테고리 품절. 메뉴의 품절 스위치는 따로 그대로 써요.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (!snap.hasData || !_loaded)
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                else if (rules.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
                    child: const Text('아직 자동 품절이 없어요. 아래 [자동 품절 추가]로 만들어 주세요.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(children: [for (final r in rules) _ruleCard(rules, r, now)]),
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: !_loaded || !snap.hasData ? null : () => _edit(rules, null),
                    icon: const Icon(Icons.add, color: kAdminAccent),
                    label: const Text('자동 품절 추가', style: TextStyle(color: kAdminAccent, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: kAdminAccent, width: 1.5)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
    );
  }
}

// ───────────────────────── 규칙 하나 편집 ─────────────────────────
class _RuleEditor extends StatefulWidget {
  final SoldOutRule rule;
  final bool isNew;
  final List<_MenuLite> menus;
  final List<String> categories;
  final Future<void> Function(SoldOutRule rule) onSave;

  const _RuleEditor({
    required this.rule,
    required this.isNew,
    required this.menus,
    required this.categories,
    required this.onSave,
  });

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.rule.name);
  late int _from = widget.rule.from;
  late int _to = widget.rule.to;
  late final Set<int> _days = {...widget.rule.days};
  late final Set<String> _cats = {...widget.rule.categories};
  late final Set<String> _menuIds = {...widget.rule.menuIds};
  late bool _enabled = widget.rule.enabled;
  bool _saving = false;
  bool _closed = false;
  String? _error;

  static const _dayNames = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  SoldOutRule get _rule => widget.rule.copyWith(
        name: _name.text.trim(),
        enabled: _enabled,
        from: _from,
        to: _to,
        days: (_days.length == 7 ? <int>[] : (_days.toList()..sort())),
        categories: [for (final c in widget.categories) if (_cats.contains(c)) c],
        menuIds: [for (final m in widget.menus) if (_menuIds.contains(m.id)) m.id],
      );

  Future<void> _pickTime(bool start) async {
    final cur = start ? _from : _to;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
      helpText: start ? '품절 시작 시각' : '다시 파는 시각',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _from = picked.hour * 60 + picked.minute;
      } else {
        _to = picked.hour * 60 + picked.minute;
      }
    });
  }

  Future<void> _pickMenus() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _MenuPicker(menus: widget.menus, selected: _menuIds, coveredCategories: _cats),
    );
    if (result != null && mounted) {
      setState(() {
        _menuIds
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _closed) return;
    final r = _rule;
    if (r.categories.isEmpty && r.menuIds.isEmpty) {
      setState(() => _error = '품절할 카테고리나 메뉴를 하나 이상 골라 주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(r.copyWith(name: r.name.isEmpty ? '${r.timeLabel} 품절' : r.name));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '저장하지 못했어요: $e';
        });
      }
      return;
    }
    if (!mounted || _closed) return;
    _closed = true;
    Navigator.pop(context, true);
  }

  Widget _section(String title, Widget child, {String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (hint != null) Text(hint, style: const TextStyle(color: Colors.black45, fontSize: 12)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  Widget _timeButton(bool start) {
    final v = start ? _from : _to;
    return OutlinedButton.icon(
      onPressed: _saving ? null : () => _pickTime(start),
      icon: const Icon(Icons.schedule, size: 18, color: kAdminAccent),
      label: Text(
        '${!start && _from > _to ? '다음 날 ' : ''}${SoldOutRule.formatTime(v)}',
        style: const TextStyle(color: kAdminAccent, fontWeight: FontWeight.bold, fontSize: 16),
      ),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _rule;
    final count = widget.menus.where((m) => r.appliesTo(m.id, m.category)).length;
    final pickedMenus = [for (final m in widget.menus) if (_menuIds.contains(m.id)) m];
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.isNew ? '자동 품절 추가' : '자동 품절 수정', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: adminDialogWidth(context, 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  readOnly: _saving,
                  decoration: const InputDecoration(
                    labelText: '이름 (예: 주방 마감)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                _section(
                  '시간',
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _timeButton(true),
                      const Text('부터', style: TextStyle(color: Colors.black54)),
                      _timeButton(false),
                      const Text('까지 품절', style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                  hint: _from == _to
                      ? '시작과 끝이 같으면 고른 요일 하루 종일 품절이에요.'
                      : _from > _to
                          ? '밤을 넘겨요 — 시작한 날 ${SoldOutRule.formatTime(_from)}부터 다음 날 ${SoldOutRule.formatTime(_to)}까지.'
                          : null,
                ),
                _section(
                  '요일',
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(_dayNames[d - 1]),
                          selected: _days.isEmpty || _days.contains(d),
                          selectedColor: kAdminAccentSoft,
                          checkmarkColor: kAdminAccent,
                          onSelected: _saving
                              ? null
                              : (on) => setState(() {
                                    if (_days.isEmpty) _days.addAll([1, 2, 3, 4, 5, 6, 7]);
                                    on ? _days.add(d) : _days.remove(d);
                                    if (_days.isEmpty) _days.add(d); // 하나도 안 고르면 안 됨
                                    if (_days.length == 7) _days.clear(); // 전부 = 매일
                                  }),
                        ),
                      const SizedBox(width: 6),
                      for (final (label, pick) in [
                        ('매일', <int>{}),
                        ('평일', {1, 2, 3, 4, 5}),
                        ('주말', {6, 7}),
                      ])
                        ActionChip(
                          label: Text(label, style: const TextStyle(fontSize: 12)),
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                    _days
                                      ..clear()
                                      ..addAll(pick);
                                  }),
                        ),
                    ],
                  ),
                  hint: '시작 시각 기준이에요. (금 22:00 ~ 다음 날 11:00이면 토요일 오전까지)',
                ),
                _section(
                  '품절할 카테고리',
                  widget.categories.isEmpty
                      ? const Text('카테고리가 없어요.', style: TextStyle(color: Colors.black45))
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final c in widget.categories)
                              FilterChip(
                                label: Text(c),
                                selected: _cats.contains(c),
                                selectedColor: kAdminAccentSoft,
                                checkmarkColor: kAdminAccent,
                                onSelected: _saving ? null : (on) => setState(() => on ? _cats.add(c) : _cats.remove(c)),
                              ),
                          ],
                        ),
                  hint: '나중에 이 카테고리에 추가한 메뉴도 같이 품절돼요.',
                ),
                _section(
                  '개별 메뉴',
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final m in pickedMenus)
                        InputChip(
                          label: Text(m.name),
                          onDeleted: _saving ? null : () => setState(() => _menuIds.remove(m.id)),
                        ),
                      TextButton.icon(
                        onPressed: _saving ? null : _pickMenus,
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: const Text('메뉴 고르기'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: kAdminAccentSoft, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${r.timeLabel} · ${r.daysLabel} · 메뉴 $count개가 품절돼요.'
                    '${r.activeAt(DateTime.now()) ? '\n지금 시간 안이라 저장하면 바로 품절로 보여요.' : ''}',
                    style: const TextStyle(color: kAdminAccent, fontWeight: FontWeight.w600),
                  ),
                ),
                Row(
                  children: [
                    Switch(
                      value: _enabled,
                      activeTrackColor: kAdminAccent,
                      onChanged: _saving ? null : (v) => setState(() => _enabled = v),
                    ),
                    Text(_enabled ? '켜짐' : '꺼짐 (저장만 해 두고 쓰지 않음)'),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: busyButtonStyle(kAdminAccent),
            child: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── 메뉴 고르기 ─────────────────────────
class _MenuPicker extends StatefulWidget {
  final List<_MenuLite> menus;
  final Set<String> selected;
  final Set<String> coveredCategories; // 카테고리로 이미 들어가는 메뉴는 흐리게

  const _MenuPicker({required this.menus, required this.selected, required this.coveredCategories});

  @override
  State<_MenuPicker> createState() => _MenuPickerState();
}

class _MenuPickerState extends State<_MenuPicker> {
  late final Set<String> _sel = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.replaceAll(' ', '').toLowerCase();
    final list = widget.menus
        .where((m) => q.isEmpty || '${m.name}${m.category}'.replaceAll(' ', '').toLowerCase().contains(q))
        .toList();
    return AlertDialog(
      title: const Text('메뉴 고르기', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: adminDialogWidth(context, 440),
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '메뉴 이름·카테고리 찾기',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('맞는 메뉴가 없어요.', style: TextStyle(color: Colors.black45)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final m = list[i];
                        final covered = widget.coveredCategories.contains(m.category);
                        return CheckboxListTile(
                          dense: true,
                          value: covered || _sel.contains(m.id),
                          activeColor: kAdminAccent,
                          title: Text(m.name, style: TextStyle(color: covered ? Colors.black38 : null)),
                          subtitle: Text(covered ? '${m.category} — 카테고리로 이미 들어가요' : m.category,
                              style: const TextStyle(fontSize: 12)),
                          onChanged: covered ? null : (v) => setState(() => v == true ? _sel.add(m.id) : _sel.remove(m.id)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _sel),
          style: busyButtonStyle(kAdminAccent),
          child: Text('${_sel.length}개 고르기'),
        ),
      ],
    );
  }
}
