import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:boardpad/services/option_library.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/toss_pos_service.dart';
import 'package:boardpad/services/translate_sync.dart';
import 'package:boardpad/widgets/admin_busy_dialog.dart';
import 'package:boardpad/widgets/admin_colors.dart';
import 'package:boardpad/widgets/admin_dialog_width.dart';

/// 113차: 포스 메뉴를 고도리 메뉴로 가져오기 (관리자 웹 '토스 POS 연동 > 메뉴 연결')
///   - 아직 어떤 고도리 메뉴와도 연결 안 된 포스 상품만 보여 줌, 포스 카테고리별로 묶음
///   - 고도리에 같은 이름(띄어쓰기 무시) 메뉴가 있으면 못 고름 → 메뉴 연결에서 그 메뉴에 연결하면 됨
///   - 가져오면: 메뉴 만들기(이름·값·포스 카테고리 이름·옵션 그룹(필수 여부·선택지 값)) + 그 포스 상품과 바로 연결
///     + 새 카테고리는 카테고리 목록 뒤에 (번역 칸은 그대로 — merge) + 목록 옵션 붙이기·자동 번역
///   - 사진은 가져오지 않음(포스 상품 목록에 사진이 없음) — 메뉴 관리에서 넣어 주세요
/// 가져온 메뉴 수를 돌려줌 (닫으면 null)
class PosImportDialog extends StatefulWidget {
  final List<TossCatalogItem> catalog;
  final Set<String> linkedItemIds; // 이미 고도리 메뉴와 연결된 포스 상품
  final Set<String> existingNames; // 고도리 메뉴 이름(띄어쓰기 뺀 것)

  const PosImportDialog({super.key, required this.catalog, required this.linkedItemIds, required this.existingNames});

  static String nameKey(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  @override
  State<PosImportDialog> createState() => _PosImportDialogState();
}

class _PosImportDialogState extends State<PosImportDialog> {
  final Set<String> _picked = {};
  bool _busy = false;
  bool _closed = false;
  String? _error;

  List<TossCatalogItem> get _candidates => [
        for (final i in widget.catalog)
          if (!widget.linkedItemIds.contains(i.id)) i,
      ];

  bool _sameName(TossCatalogItem i) => widget.existingNames.contains(PosImportDialog.nameKey(i.title));

  Map<String, List<TossCatalogItem>> get _byCategory {
    final out = <String, List<TossCatalogItem>>{};
    for (final i in _candidates) {
      out.putIfAbsent(i.category.isEmpty ? '분류 없음' : i.category, () => []).add(i);
    }
    return out;
  }

  Future<void> _import() async {
    if (_busy || _closed || _picked.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = [for (final i in _candidates) if (_picked.contains(i.id)) i];
      final menus = StoreScope.col('menus');
      final base = DateTime.now().millisecondsSinceEpoch;
      final links = <String, String?>{};
      for (var k = 0; k < items.length; k += 400) {
        final batch = FirebaseFirestore.instance.batch();
        for (var j = k; j < items.length && j < k + 400; j++) {
          final i = items[j];
          final ref = menus.doc();
          batch.set(ref, {
            'category': i.category.isEmpty ? '분류 없음' : i.category,
            'name': i.title,
            'price': i.price ?? 0,
            'imageUrl': '',
            'optionGroups': [
              for (final o in i.options)
                if (o.choices.isNotEmpty)
                  {
                    'groupName': o.title,
                    'isRequired': o.required,
                    'options': [
                      for (final c in o.choices) {'name': c.title, 'price': c.price},
                    ],
                  },
            ],
            'isSoldOut': false,
            'timestamp': Timestamp.fromMillisecondsSinceEpoch(base + j),
          });
          links[ref.id] = i.id;
        }
        await batch.commit();
      }
      // 새 카테고리는 목록 뒤에 (번역 칸 유지 — merge, 104차)
      final catRef = StoreScope.col('settings').doc('categories');
      final cats = List<String>.from((((await catRef.get()).data() ?? const {})['list'] as List?) ?? const []);
      final newCats = items.map((i) => i.category.isEmpty ? '분류 없음' : i.category).where((c) => !cats.contains(c)).toSet().toList();
      if (newCats.isNotEmpty) await catRef.set({'list': [...cats, ...newCats]}, SetOptions(merge: true));
      // 포스 상품과 바로 연결 (한 번에 500개까지)
      final entries = links.entries.toList();
      for (var k = 0; k < entries.length; k += 500) {
        await TossPosService.saveMenuMap(Map.fromEntries(entries.sublist(k, k + 500 > entries.length ? entries.length : k + 500)));
      }
      try {
        await OptionLibrary.syncMenus(); // 106차: 카테고리에 붙은 목록 옵션을 새 메뉴에도
      } catch (_) {}
      TranslateSync.kick(); // 손님 패드 자동 번역
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '가져오지 못했어요: $e';
        });
      }
      return;
    }
    if (!mounted || _closed) return;
    _closed = true;
    Navigator.of(context).pop(_picked.length);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _byCategory;
    final pickable = [for (final i in _candidates) if (!_sameName(i)) i];
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('포스 메뉴 가져오기', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: adminDialogWidth(context, 640),
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '아직 고도리 메뉴와 연결되지 않은 포스 상품이에요. 고르면 같은 이름·값·옵션으로 고도리 메뉴를 만들고 바로 연결해요.\n'
                '카테고리는 포스 카테고리 이름을 그대로 써요. 사진은 메뉴 관리에서 넣어 주세요. '
                '같은 이름 메뉴가 이미 있으면 못 골라요 — 아래 메뉴 연결에서 그 메뉴에 연결해 주세요.',
                style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Text('고른 상품 ${_picked.length}개', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: _busy || pickable.isEmpty
                      ? null
                      : () => setState(() {
                            if (_picked.length == pickable.length) {
                              _picked.clear();
                            } else {
                              _picked.addAll(pickable.map((i) => i.id));
                            }
                          }),
                  child: Text(_picked.length == pickable.length && pickable.isNotEmpty ? '모두 풀기' : '모두 고르기'),
                ),
              ]),
              const Divider(height: 8),
              Expanded(
                child: _candidates.isEmpty
                    ? const Center(
                        child: Text('가져올 포스 상품이 없어요. (모두 고도리 메뉴와 연결돼 있어요)', style: TextStyle(color: Colors.black45)))
                    : ListView(
                        children: [
                          for (final g in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 2),
                              child: Row(children: [
                                Text(g.key, style: const TextStyle(fontWeight: FontWeight.bold, color: kAdminAccent)),
                                const SizedBox(width: 6),
                                Text('${g.value.length}', style: const TextStyle(color: Colors.black45)),
                                const Spacer(),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                            final ids = [for (final i in g.value) if (!_sameName(i)) i.id];
                                            if (ids.every(_picked.contains)) {
                                              _picked.removeAll(ids);
                                            } else {
                                              _picked.addAll(ids);
                                            }
                                          }),
                                  child: const Text('이 카테고리 모두', style: TextStyle(fontSize: 12)),
                                ),
                              ]),
                            ),
                            for (final i in g.value)
                              CheckboxListTile(
                                dense: true,
                                value: _picked.contains(i.id),
                                activeColor: kAdminAccent,
                                onChanged: _busy || _sameName(i)
                                    ? null
                                    : (v) => setState(() => v == true ? _picked.add(i.id) : _picked.remove(i.id)),
                                title: Text(i.title, style: TextStyle(color: _sameName(i) ? Colors.black38 : null)),
                                subtitle: Text(
                                  [
                                    i.price == null ? '값 없음' : '${i.price}원',
                                    if (i.options.isNotEmpty) '옵션 ${i.options.map((o) => o.required ? '${o.title}*' : o.title).join(', ')}',
                                    if (i.soldOut) '포스 품절',
                                    if (_sameName(i)) '같은 이름 메뉴 있음',
                                  ].join(' · '),
                                  style: TextStyle(fontSize: 12, color: _sameName(i) ? Colors.black38 : Colors.black54),
                                ),
                              ),
                          ],
                        ],
                      ),
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
            onPressed: _busy || _picked.isEmpty ? null : _import,
            style: busyButtonStyle(kAdminAccent),
            child: Text('${_picked.length}개 가져오기', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
