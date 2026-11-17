import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:boardpad/services/store_scope.dart';

/// 옵션 목록 (106차) — 토스 포스처럼 옵션 그룹을 따로 만들어 두고 카테고리·메뉴에 붙임
///
///   저장: settings/optionLibrary = { groups: [OptionLibGroup…], updatedAt }   (배열 순서 = 손님 패드에 나오는 옵션 순서)
///   메뉴에는 복사본을 넣음:
///     menus/{id}.optionGroups[] = { groupName, isRequired, maxSelect?, options[{name, price, soldOut?}], libraryId, translations? }
///     → 손님 패드·주문·토스 연동·자동 번역(translate.js)은 지금처럼 메뉴의 optionGroups만 봄 (서버는 그대로)
///   메뉴 전용 옵션(libraryId 없음)은 그대로 두고 앞에, 목록에서 온 옵션은 뒤에(목록 순서대로) 둠
///   붙는 곳 = categories(그 카테고리 메뉴 전부) + menuIds(개별 메뉴) − excludeMenuIds('이 메뉴에서 빼기')
///   maxSelect: 한 그룹에서 고를 수 있는 개수(1 = 하나만, 기본). soldOut: 그 선택지 품절(손님 패드에서 못 고름)
class OptionLibChoice {
  String name;
  int price;
  bool soldOut;
  final String uid; // 화면에서 줄을 알아보는 값 (저장 안 함)

  OptionLibChoice({required this.name, this.price = 0, this.soldOut = false, String? uid}) : uid = uid ?? _newId('c');

  factory OptionLibChoice.fromJson(Map m) => OptionLibChoice(
        name: '${m['name'] ?? ''}'.trim(),
        price: int.tryParse('${m['price'] ?? 0}') ?? 0,
        soldOut: m['soldOut'] == true,
      );

  Map<String, dynamic> toJson() => {'name': name.trim(), 'price': price, if (soldOut) 'soldOut': true};

  OptionLibChoice copy() => OptionLibChoice(name: name, price: price, soldOut: soldOut, uid: uid);
}

class OptionLibGroup {
  final String id;
  String name;
  bool isRequired;
  int maxSelect;
  List<OptionLibChoice> options;
  List<String> categories;
  List<String> menuIds;
  List<String> excludeMenuIds;

  /// '지금 메뉴 옵션 가져오기'로 만든 그룹이면, 가져온 메뉴 전용 옵션의 모양(ownGroupSignature).
  /// 저장할 때 그 메뉴들에서 같은 모양의 메뉴 전용 옵션을 빼고 이 그룹 복사본으로 바꿈 (저장 안 함)
  String? importSig;

  OptionLibGroup({
    String? id,
    required this.name,
    this.isRequired = false,
    this.maxSelect = 1,
    List<OptionLibChoice>? options,
    List<String>? categories,
    List<String>? menuIds,
    List<String>? excludeMenuIds,
    this.importSig,
  })  : id = id ?? _newId('g'),
        options = options ?? [],
        categories = categories ?? [],
        menuIds = menuIds ?? [],
        excludeMenuIds = excludeMenuIds ?? [];

  factory OptionLibGroup.fromJson(Map m) {
    List<String> strs(Object? v) => [for (final x in (v is List ? v : const [])) '$x'];
    return OptionLibGroup(
      id: '${m['id'] ?? ''}'.isEmpty ? null : '${m['id']}',
      name: '${m['name'] ?? ''}'.trim(),
      isRequired: m['required'] == true,
      maxSelect: (int.tryParse('${m['maxSelect'] ?? 1}') ?? 1).clamp(1, 99).toInt(),
      options: [for (final o in (m['options'] is List ? m['options'] as List : const [])) if (o is Map) OptionLibChoice.fromJson(o)],
      categories: strs(m['categories']),
      menuIds: strs(m['menuIds']),
      excludeMenuIds: strs(m['excludeMenuIds']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name.trim(),
        'required': isRequired,
        'maxSelect': maxSelect,
        'options': [for (final o in options) o.toJson()],
        'categories': categories,
        'menuIds': menuIds,
        'excludeMenuIds': excludeMenuIds,
      };

  OptionLibGroup copy() => OptionLibGroup(
        id: id,
        name: name,
        isRequired: isRequired,
        maxSelect: maxSelect,
        options: [for (final o in options) o.copy()],
        categories: [...categories],
        menuIds: [...menuIds],
        excludeMenuIds: [...excludeMenuIds],
        importSig: importSig,
      );

  bool attachedTo(String menuId, String category) =>
      !excludeMenuIds.contains(menuId) && (categories.contains(category) || menuIds.contains(menuId));

  /// 메뉴에 넣을 복사본. old = 그 메뉴에 이미 있던 같은 libraryId 복사본 — 이름이 같으면 번역(translations)을 이어받음
  /// (자동 번역 서버가 원문(_src)이 같으면 다시 번역하지 않으므로 글자가 그대로면 번역도 그대로)
  Map<String, dynamic> menuCopy([Map? old]) {
    final oldOpts = <String, Map>{
      for (final o in (old?['options'] is List ? old!['options'] as List : const []))
        if (o is Map) '${o['name'] ?? ''}'.trim(): o,
    };
    final cleanOpts = [for (final o in options) if (o.name.trim().isNotEmpty) o];
    return {
      'groupName': name.trim(),
      'isRequired': isRequired,
      if (maxSelect > 1) 'maxSelect': maxSelect,
      'options': [
        for (final o in cleanOpts)
          {
            ...o.toJson(),
            if (oldOpts[o.name.trim()]?['translations'] != null) 'translations': oldOpts[o.name.trim()]!['translations'],
          },
      ],
      'libraryId': id,
      if (old != null && '${old['groupName'] ?? ''}'.trim() == name.trim() && old['translations'] != null)
        'translations': old['translations'],
    };
  }
}

var _seq = 0;
String _newId(String p) => '$p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

bool isLibraryGroup(Object? g) => g is Map && '${g['libraryId'] ?? ''}'.isNotEmpty;

/// 메뉴 전용 옵션 그룹의 모양(이름·필수·선택지 이름과 값) — '지금 메뉴 옵션 가져오기'에서 같은 그룹 묶기에 씀
String ownGroupSignature(Map g) {
  final opts = [
    for (final o in (g['options'] is List ? g['options'] as List : const []))
      if (o is Map) '${'${o['name'] ?? ''}'.trim()}=${int.tryParse('${o['price'] ?? 0}') ?? 0}',
  ];
  return '${'${g['groupName'] ?? ''}'.trim()}|${g['isRequired'] == true ? 1 : 0}|${opts.join(',')}';
}

/// 메뉴 하나의 optionGroups를 옵션 목록에 맞춰 새로 만듦: 메뉴 전용 옵션(앞) + 붙는 목록 옵션(뒤, 목록 순서)
List<Map<String, dynamic>> menuGroupsWithLibrary({
  required String menuId,
  required String category,
  required List<dynamic> current,
  required List<OptionLibGroup> groups,
}) {
  final drop = {
    for (final g in groups)
      if (g.importSig != null && g.attachedTo(menuId, category)) g.importSig!,
  };
  final oldLib = <String, Map>{
    for (final g in current)
      if (isLibraryGroup(g)) '${(g as Map)['libraryId']}': g,
  };
  return [
    for (final g in current)
      if (g is Map && !isLibraryGroup(g) && !drop.contains(ownGroupSignature(g))) Map<String, dynamic>.from(g),
    for (final g in groups)
      if (g.attachedTo(menuId, category)) g.menuCopy(oldLib[g.id]),
  ];
}

bool sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !sameJson(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is num && b is num) return a == b;
  return a == b;
}

/// Firestore 쪽 (관리자 웹)
class OptionLibrary {
  static DocumentReference<Map<String, dynamic>> get ref => StoreScope.col('settings').doc('optionLibrary');

  static List<OptionLibGroup> _parse(Map<String, dynamic>? data) => [
        for (final g in ((data ?? const {})['groups'] as List? ?? const []))
          if (g is Map) OptionLibGroup.fromJson(g),
      ];

  static Future<List<OptionLibGroup>> load() async => _parse((await ref.get()).data());

  static Future<void> save(List<OptionLibGroup> groups) =>
      ref.set({'groups': [for (final g in groups) g.toJson()], 'updatedAt': FieldValue.serverTimestamp()});

  /// 메뉴들의 optionGroups를 옵션 목록에 맞춤 — 바뀐 메뉴만 씀. 반환: 고친 메뉴 수
  static Future<int> syncMenus({List<OptionLibGroup>? groups, String? onlyMenuId}) async {
    final lib = groups ?? await load();
    final docs = onlyMenuId == null
        ? (await StoreScope.col('menus').get()).docs.cast<DocumentSnapshot<Map<String, dynamic>>>()
        : [await StoreScope.col('menus').doc(onlyMenuId).get()];
    final changes = <DocumentReference<Map<String, dynamic>>, List<Map<String, dynamic>>>{};
    for (final d in docs) {
      final m = d.data();
      if (m == null) continue;
      final cur = (m['optionGroups'] as List?) ?? const [];
      final next = menuGroupsWithLibrary(menuId: d.id, category: '${m['category'] ?? ''}', current: cur, groups: lib);
      if (!sameJson(cur, next)) changes[d.reference] = next;
    }
    final refs = changes.keys.toList();
    for (var i = 0; i < refs.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final r in refs.skip(i).take(400)) {
        batch.update(r, {'optionGroups': changes[r]});
      }
      await batch.commit();
    }
    return refs.length;
  }

  /// 메뉴 수정 창의 '이 메뉴에서 빼기'·'붙이기' → 옵션 목록의 붙는 곳을 고침(트랜잭션). 반환: 고친 뒤 목록
  static Future<List<OptionLibGroup>> updateMembership(
    String menuId,
    String category, {
    Set<String> add = const {},
    Set<String> remove = const {},
  }) {
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final groups = _parse((await tx.get(ref)).data());
      for (final g in groups) {
        if (remove.contains(g.id)) {
          g.menuIds.remove(menuId);
          if (g.categories.contains(category) && !g.excludeMenuIds.contains(menuId)) g.excludeMenuIds.add(menuId);
        } else if (add.contains(g.id)) {
          g.excludeMenuIds.remove(menuId);
          if (!g.categories.contains(category) && !g.menuIds.contains(menuId)) g.menuIds.add(menuId);
        }
      }
      if (add.isNotEmpty || remove.isNotEmpty) {
        tx.set(ref, {'groups': [for (final g in groups) g.toJson()], 'updatedAt': FieldValue.serverTimestamp()});
      }
      return groups;
    });
  }

  /// 카테고리 이름을 바꾸면 옵션 목록의 붙는 카테고리도 같이 바꿈
  static Future<void> renameCategory(String from, String to) async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final groups = _parse(snap.data());
      var changed = false;
      for (final g in groups) {
        final i = g.categories.indexOf(from);
        if (i < 0) continue;
        changed = true;
        if (g.categories.contains(to)) {
          g.categories.removeAt(i);
        } else {
          g.categories[i] = to;
        }
      }
      if (changed) tx.set(ref, {'groups': [for (final g in groups) g.toJson()], 'updatedAt': FieldValue.serverTimestamp()});
    });
  }
}
