/// 메뉴 한꺼번에 추가 (99차) — 관리자 웹 메뉴 관리 '한꺼번에 추가'에 붙여 넣는 글
///
///   # 카테고리 이름              ← 아래 메뉴들의 카테고리
///   메뉴 이름 | 가격 | 옵션들     ← 메뉴 한 줄
///   // 메모                      ← 무시 (빈 줄도 무시)
///
/// 옵션들: '그룹: 선택, 선택+500; 그룹2*: 선택, 선택'  (그룹 이름 끝 * = 필수, +숫자 = 추가 금액)
/// 예)  아메리카노 | 3500 | 온도*: ICE, HOT; 추가: 샷 추가+500, 연하게
///
/// 결과 모양은 메뉴 문서 그대로: {category, name, price, optionGroups: [{groupName, isRequired, options: [{name, price}]}]}
library;

class MenuBulkLine {
  final int lineNo;
  final String category;
  final String name;
  final int price;
  final List<Map<String, dynamic>> optionGroups;
  const MenuBulkLine(this.lineNo, this.category, this.name, this.price, this.optionGroups);
}

class MenuBulkResult {
  final List<MenuBulkLine> menus;
  final List<String> errors; // '3번째 줄: …'
  const MenuBulkResult(this.menus, this.errors);
}

int? _price(String s) {
  final t = s.replaceAll(RegExp(r'[,\s원]'), '');
  if (!RegExp(r'^\d{1,7}$').hasMatch(t)) return null;
  return int.parse(t);
}

MenuBulkResult parseMenuBulkText(String text, {String defaultCategory = '기본 카테고리'}) {
  final menus = <MenuBulkLine>[];
  final errors = <String>[];
  final seen = <String>{};
  var category = defaultCategory;
  final lines = text.split(RegExp(r'\r?\n'));
  for (var i = 0; i < lines.length; i++) {
    final no = i + 1;
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('//')) continue;
    if (line.startsWith('#')) {
      final c = line.substring(1).trim();
      if (c.isEmpty) {
        errors.add('$no번째 줄: # 뒤에 카테고리 이름을 써 주세요.');
      } else {
        category = c;
      }
      continue;
    }
    final parts = line.split('|').map((p) => p.trim()).toList();
    if (parts.length < 2 || parts.length > 3 || parts[0].isEmpty) {
      errors.add('$no번째 줄: "이름 | 가격 | 옵션" 모양이 아니에요.');
      continue;
    }
    final name = parts[0];
    final price = _price(parts[1]);
    if (price == null) {
      errors.add('$no번째 줄 ($name): 가격이 숫자가 아니에요.');
      continue;
    }
    if (!seen.add(name.replaceAll(RegExp(r'\s+'), ''))) {
      errors.add('$no번째 줄 ($name): 같은 이름이 위에 또 있어요.');
      continue;
    }
    final groups = <Map<String, dynamic>>[];
    var bad = false;
    if (parts.length == 3 && parts[2].isNotEmpty) {
      for (final g in parts[2].split(';')) {
        if (g.trim().isEmpty) continue;
        final colon = g.indexOf(':');
        if (colon <= 0) {
          errors.add('$no번째 줄 ($name): 옵션은 "그룹: 선택, 선택" 모양으로 써 주세요.');
          bad = true;
          break;
        }
        var gName = g.substring(0, colon).trim();
        final required = gName.endsWith('*');
        if (required) gName = gName.substring(0, gName.length - 1).trim();
        final opts = <Map<String, dynamic>>[];
        for (final o in g.substring(colon + 1).split(',')) {
          final s = o.trim();
          if (s.isEmpty) continue;
          final m = RegExp(r'^(.*?)\s*\+\s*([\d,]+)\s*원?$').firstMatch(s);
          final oName = (m == null ? s : m.group(1)!).trim();
          final oPrice = m == null ? 0 : (_price(m.group(2)!) ?? 0);
          if (oName.isEmpty) continue;
          opts.add({'name': oName, 'price': oPrice});
        }
        if (gName.isEmpty || opts.isEmpty) {
          errors.add('$no번째 줄 ($name): 옵션 그룹 이름이나 선택지가 비었어요.');
          bad = true;
          break;
        }
        groups.add({'groupName': gName, 'isRequired': required, 'options': opts});
      }
    }
    if (bad) continue;
    menus.add(MenuBulkLine(no, category, name, price, groups));
  }
  return MenuBulkResult(menus, errors);
}
