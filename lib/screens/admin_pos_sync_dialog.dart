import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:boardpad/services/option_library.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/toss_pos_service.dart';
import 'package:boardpad/services/translate_sync.dart';
import 'package:boardpad/widgets/admin_busy_dialog.dart';
import 'package:boardpad/widgets/admin_colors.dart';
import 'package:boardpad/widgets/admin_dialog_width.dart';

/// 121차: 포스와 다르게 된 고도리 메뉴를 포스 값으로 맞추기 (관리자 웹 '토스 POS 연동 > 메뉴 연결')
///   - 포스 상품과 연결된 고도리 메뉴만 봄. 다른 점마다 체크해서 고침:
///     ① 가격 = 포스 상품 값 + 미리 골라 둔 필수 선택 값 (주문 보낼 때 포스가 쓰는 값 — 103차)
///     ② 옵션 = 포스 옵션(미리 골라 둔 옵션은 뺌)과 같게: 그룹 이름·필수 여부·선택지 이름·값.
///        이름이 같은 고도리 선택지는 번역·품절·기본 선택을 그대로 두고 값만 바꿈, 포스에 없는 메뉴 전용 그룹은 뺌
///        ★옵션 목록(106차)에서 온 그룹은 여기서 안 바꿈(옵션 관리에서 — 저장하면 메뉴에 다시 복사되므로)
///     ③ 이름 = 포스 상품 이름 (처음엔 꺼 둠 — 고도리 이름을 일부러 다르게 쓴 메뉴가 많아서)
///   - 사진·카테고리·품절·연결은 그대로
/// 고친 메뉴 수를 돌려줌 (닫으면 null)
class PosSyncDialog extends StatefulWidget {
  final List<TossCatalogItem> catalog;
  final Map<String, String> menuMap; // 고도리 메뉴 ID → 연결 값

  const PosSyncDialog({super.key, required this.catalog, required this.menuMap});

  @override
  State<PosSyncDialog> createState() => _PosSyncDialogState();
}

/// 메뉴 하나의 다른 점
class PosSyncDiff {
  final String menuId;
  final String name;
  final String category;
  final String posTitle;
  final int? price; // 고도리 값 (다를 때만)
  final int? posPrice; // 포스 값 (다를 때만)
  final List<String> optionNotes; // 옵션 다른 점 (비면 같음)
  final List<Map<String, dynamic>>? newGroups; // 옵션을 맞출 때 쓸 optionGroups
  final List<String> libraryNotes; // 옵션 목록 그룹이 달라서 옵션 관리에서 고쳐야 하는 것
  final bool nameDiff;

  const PosSyncDiff({
    required this.menuId,
    required this.name,
    required this.category,
    required this.posTitle,
    this.price,
    this.posPrice,
    this.optionNotes = const [],
    this.newGroups,
    this.libraryNotes = const [],
    this.nameDiff = false,
  });

  bool get priceDiff => price != null && posPrice != null;
  bool get optionDiff => optionNotes.isNotEmpty && newGroups != null;
  bool get any => priceDiff || optionDiff || nameDiff || libraryNotes.isNotEmpty;

  static String _won(int v) => '${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';

  /// 메뉴 문서 + 연결 값 + 포스 상품 → 다른 점 (같으면 any == false)
  static PosSyncDiff compare(String menuId, Map<String, dynamic> menu, TossMenuLink link, TossCatalogItem item) {
    final name = '${menu['name'] ?? ''}';
    final price = int.tryParse('${menu['price'] ?? 0}') ?? 0;
    // ① 가격
    var fixedPrice = 0;
    for (final o in item.options) {
      for (final c in o.choices) {
        if (link.fixed[o.id] == c.id) fixedPrice += c.price;
      }
    }
    final posPrice = item.price == null ? null : item.price! + fixedPrice;
    // ② 옵션
    final groups = [for (final g in (menu['optionGroups'] as List? ?? const [])) if (g is Map) Map<String, dynamic>.from(g)];
    final posOpts = [for (final o in item.options) if (!link.fixed.containsKey(o.id) && o.choices.isNotEmpty) o];
    final notes = <String>[];
    final libNotes = <String>[];
    final used = <int>{};
    final next = <Map<String, dynamic>>[];
    for (final o in posOpts) {
      final gi = groups.indexWhere((g) => tossNormName('${g['groupName'] ?? ''}') == tossNormName(o.title));
      final posLabel = o.choices.map((c) => c.price == 0 ? c.title : '${c.title}+${c.price}').join('·');
      if (gi < 0) {
        notes.add("옵션 '${o.title}' 추가 ($posLabel)");
        next.add({
          'groupName': o.title,
          'isRequired': o.required,
          'options': [for (final c in o.choices) {'name': c.title, 'price': c.price}],
        });
        continue;
      }
      used.add(gi);
      final g = groups[gi];
      final oldOpts = [for (final x in (g['options'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
      final changes = <String>[];
      if ((g['isRequired'] == true) != o.required) changes.add(o.required ? '필수로' : '선택으로');
      final newOpts = <Map<String, dynamic>>[];
      for (final c in o.choices) {
        final old = oldOpts.where((x) => tossNormName('${x['name'] ?? ''}') == tossNormName(c.title)).firstOrNull;
        if (old == null) {
          changes.add('${c.title} 추가');
          newOpts.add({'name': c.title, 'price': c.price});
        } else {
          final op = int.tryParse('${old['price'] ?? 0}') ?? 0;
          if (op != c.price) changes.add('${old['name']} ${_won(op)}→${_won(c.price)}');
          newOpts.add({...old, 'price': c.price});
        }
      }
      for (final x in oldOpts) {
        if (!o.choices.any((c) => tossNormName(c.title) == tossNormName('${x['name'] ?? ''}'))) changes.add('${x['name']} 뺌');
      }
      if (isLibraryGroup(g)) {
        // 옵션 목록 그룹은 그대로 둠 — 다르면 옵션 관리에서 고치라고만
        if (changes.isNotEmpty) libNotes.add("옵션 목록 '${g['groupName']}': ${changes.join(', ')}");
        next.add(g);
      } else {
        if (changes.isNotEmpty) notes.add("옵션 '${g['groupName']}': ${changes.join(', ')}");
        next.add({...g, 'isRequired': o.required, 'options': newOpts});
      }
    }
    for (var i = 0; i < groups.length; i++) {
      if (used.contains(i)) continue;
      final g = groups[i];
      if (isLibraryGroup(g)) {
        next.add(g); // 옵션 목록 그룹은 그대로
        libNotes.add("옵션 목록 '${g['groupName']}'은 포스 상품에 없어요");
      } else {
        notes.add("옵션 '${g['groupName']}' 뺌 (포스에 없음)");
      }
    }
    return PosSyncDiff(
      menuId: menuId,
      name: name,
      category: '${menu['category'] ?? ''}',
      posTitle: item.title,
      price: posPrice != null && posPrice != price ? price : null,
      posPrice: posPrice != null && posPrice != price ? posPrice : null,
      optionNotes: notes,
      newGroups: notes.isEmpty ? null : next,
      libraryNotes: libNotes,
      nameDiff: item.title.trim().isNotEmpty && item.title.trim() != name.trim(),
    );
  }
}

class _PosSyncDialogState extends State<PosSyncDialog> {
  bool _loading = true;
  String? _error;
  List<PosSyncDiff> _diffs = [];
  // 고를 것: 메뉴 ID → {'price', 'options', 'name'}
  final Map<String, Set<String>> _pick = {};
  bool _busy = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final byId = {for (final i in widget.catalog) i.id: i};
      final snap = await StoreScope.col('menus').get();
      final diffs = <PosSyncDiff>[];
      for (final d in snap.docs) {
        final link = TossMenuLink.parse(widget.menuMap[d.id]);
        final item = link == null ? null : byId[link.itemId];
        if (link == null || item == null) continue;
        final diff = PosSyncDiff.compare(d.id, d.data(), link, item);
        if (diff.any) diffs.add(diff);
      }
      diffs.sort((a, b) => '${a.category} ${a.name}'.compareTo('${b.category} ${b.name}'));
      if (!mounted) return;
      setState(() {
        _diffs = diffs;
        for (final d in diffs) {
          _pick[d.menuId] = {if (d.priceDiff) 'price', if (d.optionDiff) 'options'}; // 이름은 처음엔 꺼 둠
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '불러오지 못했어요: $e';
          _loading = false;
        });
      }
    }
  }

  int get _count => _pick.values.where((s) => s.isNotEmpty).length;

  Future<void> _apply() async {
    if (_busy || _closed || _count == 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var optionsChanged = false;
    try {
      final menus = StoreScope.col('menus');
      final todo = [for (final d in _diffs) if ((_pick[d.menuId] ?? const {}).isNotEmpty) d];
      for (var k = 0; k < todo.length; k += 400) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in todo.skip(k).take(400)) {
          final p = _pick[d.menuId]!;
          final update = <String, dynamic>{
            if (p.contains('price') && d.priceDiff) 'price': d.posPrice,
            if (p.contains('options') && d.optionDiff) 'optionGroups': d.newGroups,
            if (p.contains('name') && d.nameDiff) 'name': d.posTitle,
          };
          if (p.contains('options') && d.optionDiff) optionsChanged = true;
          if (update.isNotEmpty) batch.update(menus.doc(d.menuId), update);
        }
        await batch.commit();
      }
      if (optionsChanged) {
        try {
          await OptionLibrary.syncMenus(); // 옵션 목록 그룹 순서(메뉴 전용 먼저) 맞춤
        } catch (_) {}
      }
      TranslateSync.kick(); // 바뀐 이름·옵션 자동 번역
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '고치지 못했어요: $e';
        });
      }
      return;
    }
    if (!mounted || _closed) return;
    _closed = true;
    Navigator.of(context).pop(_count);
  }

  Widget _check(PosSyncDiff d, String key, String label, {String? detail}) {
    final on = _pick[d.menuId]?.contains(key) ?? false;
    return CheckboxListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 4),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: kAdminAccent,
      value: on,
      onChanged: _busy
          ? null
          : (v) => setState(() {
                final s = _pick.putIfAbsent(d.menuId, () => <String>{});
                v == true ? s.add(key) : s.remove(key);
              }),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: detail == null ? null : Text(detail, style: const TextStyle(fontSize: 12, color: Colors.black54)),
    );
  }

  Widget _row(PosSyncDiff d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            Text(d.category, style: const TextStyle(fontSize: 12, color: Colors.black45)),
            const Spacer(),
            Flexible(
              child: Text('포스: ${d.posTitle}',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ),
          ]),
          if (d.priceDiff) _check(d, 'price', '가격 ${PosSyncDiff._won(d.price!)} → ${PosSyncDiff._won(d.posPrice!)}'),
          if (d.optionDiff) _check(d, 'options', '옵션을 포스와 같게', detail: d.optionNotes.join('\n')),
          if (d.nameDiff) _check(d, 'name', "이름 '${d.name}' → '${d.posTitle}'"),
          for (final n in d.libraryNotes)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text('$n → 메뉴 관리 [옵션 관리]에서 고쳐 주세요',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allOn = _diffs.isNotEmpty &&
        _diffs.every((d) => (_pick[d.menuId] ?? const {}).containsAll({if (d.priceDiff) 'price', if (d.optionDiff) 'options'}));
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('포스와 다른 메뉴 맞추기', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: adminDialogWidth(context, 680),
          height: 540,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '포스 상품과 연결된 고도리 메뉴 중 가격·옵션·이름이 포스와 다른 것이에요. 고른 것만 포스 값으로 고쳐요.\n'
                '주문은 포스 값으로 결제돼서, 가격·옵션을 맞춰 두면 손님 패드와 계산서가 같아져요. 사진·카테고리·품절은 그대로예요.',
                style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Text('고칠 메뉴 $_count개', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: _busy || _diffs.isEmpty
                      ? null
                      : () => setState(() {
                            for (final d in _diffs) {
                              final s = _pick.putIfAbsent(d.menuId, () => <String>{});
                              if (allOn) {
                                s.removeAll(['price', 'options']);
                              } else {
                                if (d.priceDiff) s.add('price');
                                if (d.optionDiff) s.add('options');
                              }
                            }
                          }),
                  child: Text(allOn ? '가격·옵션 모두 풀기' : '가격·옵션 모두 고르기'),
                ),
              ]),
              const Divider(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _diffs.isEmpty
                        ? const Center(
                            child: Text('포스와 다른 메뉴가 없어요. (연결된 메뉴 모두 같아요)', style: TextStyle(color: Colors.black45)))
                        : ListView(children: [for (final d in _diffs) _row(d)]),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('닫기', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _busy || _count == 0 ? null : _apply,
            style: busyButtonStyle(kAdminAccent),
            child: Text('$_count개 고치기', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
