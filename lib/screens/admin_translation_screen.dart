import 'package:flutter/material.dart';

import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/translate_sync.dart';
import 'package:boardpad/services/translation_overrides.dart';
import 'package:boardpad/widgets/admin_busy_dialog.dart';
import 'package:boardpad/widgets/admin_colors.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';

/// 관리자 웹: 번역 관리 (120차) — 자동 번역(83차)이 틀린 말을 사장님이 직접 고침
///
/// - 매장 글(메뉴 이름·옵션·카테고리·공지·이벤트)을 원문마다 한 줄로 모아 영어·중국어·일본어 번역을 보여 줌
/// - 고치고 [저장] → 번역 고침표(settings/translationOverrides) → 서버 자동 번역이 같은 원문이 쓰인 모든 곳에 넣음
///   (TranslateSync.kick — 손님 패드에는 잠시 뒤 보임). 비운 언어는 자동 번역 그대로
/// - [자동 번역으로] = 고침을 지움 → 다음 번역 때 구글 번역으로 되돌아감
/// - 원문(한국어)을 바꾸면 그 고침은 더 이상 안 쓰임('지금 쓰는 곳 없음'으로 남음 — 지울 수 있음)
/// - 게임 이름은 번역하지 않음(원문 그대로 — 83차)
class AdminTranslationScreen extends StatefulWidget {
  const AdminTranslationScreen({super.key});

  @override
  State<AdminTranslationScreen> createState() => _AdminTranslationScreenState();
}

/// 번역 줄 하나 (같은 원문은 한 줄)
class TrRow {
  final String src;
  final Set<String> kinds = {}; // menu · option · category · notice
  final List<String> where = [];
  final Map<String, String> auto = {}; // 지금 문서에 들어 있는 번역 (처음 찾은 곳)
  TrRow(this.src);
}

const _langLabels = {'en': 'English', 'zh': '中文(简体)', 'ja': '日本語'};
const _kindLabels = {
  'all': '전체',
  'menu': '메뉴 이름',
  'option': '옵션',
  'category': '카테고리',
  'notice': '공지·이벤트',
  'fixed': '직접 고친 것',
};

class _AdminTranslationScreenState extends State<AdminTranslationScreen> {
  bool _loading = true;
  String? _error;
  List<TrRow> _rows = [];
  Map<String, Map<String, String>> _ovr = {};
  String _kind = 'all';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = StoreScope.col('settings');
      // 같이 시작해서 기다림
      final menusF = StoreScope.col('menus').get();
      final catF = settings.doc('categories').get();
      final noticeF = settings.doc('notices').get();
      final eventF = settings.doc('events').get();
      final ovrF = TranslationOverrides.load();
      final menuDocs = (await menusF).docs;
      final cat = (await catF).data();
      final itemDocs = [('공지', (await noticeF).data()), ('이벤트', (await eventF).data())];
      final ovr = await ovrF;
      final rows = <String, TrRow>{};
      void add(String text, String kind, String where, dynamic translations, String field) {
        final src = text.trim();
        final key = TranslationOverrides.keyOf(src);
        if (key.isEmpty) return;
        final row = rows.putIfAbsent(key, () => TrRow(src));
        row.kinds.add(kind);
        if (!row.where.contains(where)) row.where.add(where);
        if (translations is Map) {
          for (final c in TranslationOverrides.langs) {
            final t = translations[c];
            final v = t is Map ? t[field] : null;
            if (v is String && v.trim().isNotEmpty) row.auto.putIfAbsent(c, () => v);
          }
        }
      }

      for (final d in menuDocs) {
        final m = d.data();
        add('${m['name'] ?? ''}', 'menu', '메뉴 · ${m['category'] ?? ''}', m['translations'], 'name');
        for (final g in (m['optionGroups'] as List? ?? const [])) {
          if (g is! Map) continue;
          add('${g['groupName'] ?? ''}', 'option', '옵션 그룹', g['translations'], 'groupName');
          for (final o in (g['options'] as List? ?? const [])) {
            if (o is! Map) continue;
            add('${o['name'] ?? ''}', 'option', '옵션 · ${g['groupName'] ?? ''}', o['translations'], 'name');
          }
        }
      }
      final catTr = cat?['translations'];
      for (final c in (cat?['list'] as List? ?? const [])) {
        final name = '$c';
        final row = rows.putIfAbsent(TranslationOverrides.keyOf(name), () => TrRow(name.trim()));
        row.kinds.add('category');
        if (!row.where.contains('카테고리')) row.where.add('카테고리');
        if (catTr is Map) {
          for (final code in TranslationOverrides.langs) {
            final v = catTr[code] is Map ? (catTr[code] as Map)[name] : null;
            if (v is String && v.trim().isNotEmpty) row.auto.putIfAbsent(code, () => v);
          }
        }
      }
      for (final (label, data) in itemDocs) {
        for (final it in (data?['items'] as List? ?? const [])) {
          if (it is! Map) continue;
          add('${it['title'] ?? ''}', 'notice', '$label 제목', it['translations'], 'title');
          if (it['type'] != 'image') add('${it['content'] ?? ''}', 'notice', '$label 내용', it['translations'], 'content');
        }
      }
      // 원문이 바뀌어 지금 안 쓰이는 고침도 보여 줌 (지울 수 있게)
      for (final e in ovr.entries) {
        if (rows.containsKey(e.key)) continue;
        rows[e.key] = TrRow(e.value['src'] ?? e.key)..where.add('지금 쓰는 곳 없음');
      }
      final list = rows.values.toList()
        ..sort((a, b) {
          int rank(TrRow r) => r.kinds.contains('category')
              ? 0
              : r.kinds.contains('menu')
                  ? 1
                  : r.kinds.contains('option')
                      ? 2
                      : r.kinds.contains('notice')
                          ? 3
                          : 4;
          final c = rank(a).compareTo(rank(b));
          return c != 0 ? c : a.src.compareTo(b.src);
        });
      if (!mounted) return;
      setState(() {
        _rows = list;
        _ovr = ovr;
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

  List<TrRow> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _rows.where((r) {
      final key = TranslationOverrides.keyOf(r.src);
      if (_kind == 'fixed' && !_ovr.containsKey(key)) return false;
      if (_kind != 'all' && _kind != 'fixed' && !r.kinds.contains(_kind)) return false;
      if (q.isEmpty) return true;
      if (r.src.toLowerCase().contains(q)) return true;
      final o = _ovr[key] ?? const {};
      return TranslationOverrides.langs.any((c) => (o[c] ?? r.auto[c] ?? '').toLowerCase().contains(q));
    }).toList();
  }

  void _saved(String src, Map<String, String>? values) {
    final key = TranslationOverrides.keyOf(src);
    setState(() {
      if (values == null || values.length <= 1) {
        _ovr.remove(key);
      } else {
        _ovr[key] = values;
      }
    });
    TranslateSync.kick(); // 서버가 같은 원문이 쓰인 곳 모두에 넣음
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Row(
        children: [
          AdminSidebar(currentScreen: 'translate', onNavigate: (s) => AdminSidebar.go(context, s)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(narrow ? 16 : 32, narrow ? 16 : 32, narrow ? 16 : 32, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('번역 관리', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        tooltip: '다시 불러오기',
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '손님 패드의 영어·중국어·일본어 번역을 직접 고쳐요. 고친 번역은 같은 글이 쓰인 모든 곳(메뉴·옵션·카테고리·공지)에 들어가고, '
                    '비운 언어는 자동 번역 그대로예요. 손님 패드에는 저장하고 잠시 뒤 보여요. 게임 이름은 번역하지 않아요.',
                    style: TextStyle(color: Colors.black54, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final e in _kindLabels.entries)
                        ChoiceChip(
                          label: Text(e.key == 'fixed' ? '${e.value} ${_ovr.length}' : e.value),
                          selected: _kind == e.key,
                          selectedColor: kAdminAccent,
                          labelStyle: TextStyle(
                              color: _kind == e.key ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _kind = e.key),
                        ),
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '찾기 (원문·번역)',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: _list(narrow)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(bool narrow) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    final rows = _visible;
    if (rows.isEmpty) {
      return Center(
        child: Text(_kind == 'fixed' ? '직접 고친 번역이 없어요.' : '보여 줄 글이 없어요.',
            style: const TextStyle(color: Colors.black45)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final r = rows[i];
        final key = TranslationOverrides.keyOf(r.src);
        return _TrRowCard(
          key: ValueKey('$key/${_ovr[key]}'),
          row: r,
          fixed: _ovr[key],
          narrow: narrow,
          onSaved: (v) => _saved(r.src, v),
        );
      },
    );
  }
}

class _TrRowCard extends StatefulWidget {
  final TrRow row;
  final Map<String, String>? fixed; // 고침표 값
  final bool narrow;
  final void Function(Map<String, String>? values) onSaved;
  const _TrRowCard({super.key, required this.row, required this.fixed, required this.narrow, required this.onSaved});

  @override
  State<_TrRowCard> createState() => _TrRowCardState();
}

class _TrRowCardState extends State<_TrRowCard> {
  late final Map<String, TextEditingController> _c = {
    for (final code in TranslationOverrides.langs) code: TextEditingController(text: _initial(code)),
  };
  bool _saving = false;
  String? _error;

  String _initial(String code) => widget.fixed?[code] ?? widget.row.auto[code] ?? '';

  bool get _dirty => TranslationOverrides.langs.any((c) => _c[c]!.text.trim() != _initial(c).trim());

  @override
  void initState() {
    super.initState();
    for (final c in _c.values) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 저장할 값: 이미 고친 언어 + 자동 번역과 달라진 언어만 (나머지는 자동 번역 그대로)
  Map<String, String> _values() {
    final out = <String, String>{};
    for (final code in TranslationOverrides.langs) {
      final v = _c[code]!.text.trim();
      if (v.isEmpty) continue;
      final wasFixed = (widget.fixed?[code] ?? '').isNotEmpty;
      if (wasFixed || v != (widget.row.auto[code] ?? '').trim()) out[code] = v;
    }
    return out;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final v = _values();
      await TranslationOverrides.save(widget.row.src, v);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(v.isEmpty ? '고친 번역이 없어서 자동 번역 그대로예요.' : '저장했어요. 손님 패드에는 잠시 뒤 바뀌어요.')),
      );
      widget.onSaved(v.isEmpty ? null : {'src': widget.row.src, ...v});
    } catch (e) {
      if (mounted) setState(() => _error = '저장하지 못했어요. ($e)');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final ok = await showBusyConfirm(
      context,
      title: '자동 번역으로 되돌릴까요?',
      message: "'${widget.row.src}'의 직접 고친 번역을 지워요. 다음 자동 번역 때 구글 번역으로 바뀌어요.",
      confirmLabel: '되돌리기',
      danger: false,
      errorText: '되돌리지 못했어요',
      action: () => TranslationOverrides.remove(widget.row.src),
    );
    if (ok && mounted) widget.onSaved(null);
  }

  Widget _field(String code) {
    final fixed = (widget.fixed?[code] ?? '').isNotEmpty;
    final long = widget.row.src.length > 40;
    return TextField(
      controller: _c[code],
      readOnly: _saving,
      minLines: 1,
      maxLines: long ? 4 : 1,
      decoration: InputDecoration(
        isDense: true,
        labelText: _langLabels[code],
        helperText: fixed ? '직접 고침' : null,
        helperStyle: const TextStyle(color: kAdminAccent, fontWeight: FontWeight.w600),
        hintText: '비우면 자동 번역',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final hasFixed = widget.fixed != null;
    final unused = r.where.length == 1 && r.where.first == '지금 쓰는 곳 없음';
    final wide = MediaQuery.sizeOf(context).width >= 1200;
    final fields = [for (final code in TranslationOverrides.langs) _field(code)];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasFixed ? kAdminAccent.withValues(alpha: 0.35) : const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(r.src, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      r.where.take(3).join(' · ') + (r.where.length > 3 ? ' 외 ${r.where.length - 3}곳' : ''),
                      style: TextStyle(fontSize: 12, color: unused ? Colors.orange.shade800 : Colors.black45),
                    ),
                  ],
                ),
              ),
              if (hasFixed)
                TextButton.icon(
                  onPressed: _saving ? null : _reset,
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text(unused ? '고침 지우기' : '자동 번역으로'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: (!_dirty || _saving) ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('저장'),
                style: FilledButton.styleFrom(
                  backgroundColor: kAdminAccent,
                  disabledBackgroundColor: _saving ? kAdminAccent.withValues(alpha: 0.45) : null,
                  disabledForegroundColor: _saving ? Colors.white : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (wide && !widget.narrow)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, f) in fields.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: f),
                ],
              ],
            )
          else
            Column(
              children: [
                for (final (i, f) in fields.indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  f,
                ],
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
