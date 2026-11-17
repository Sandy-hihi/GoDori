import 'package:flutter_test/flutter_test.dart';

import 'package:boardpad/services/option_library.dart';

// 106차: 옵션 목록 → 메뉴 optionGroups 복사본 만들기
void main() {
  OptionLibGroup temp() => OptionLibGroup(
        id: 'gTemp',
        name: '온도',
        isRequired: true,
        options: [OptionLibChoice(name: 'ICE'), OptionLibChoice(name: 'HOT')],
        categories: ['커피'],
      );
  OptionLibGroup shot() => OptionLibGroup(
        id: 'gShot',
        name: '추가',
        maxSelect: 2,
        options: [
          OptionLibChoice(name: '샷 추가', price: 500),
          OptionLibChoice(name: '얼음 컵 추가', price: 500, soldOut: true),
          OptionLibChoice(name: '연하게'),
        ],
        menuIds: ['m2'],
      );

  test('붙는 곳 = 카테고리 + 개별 메뉴 − 뺀 메뉴', () {
    final g = temp()..menuIds.add('m9')..excludeMenuIds.add('m1');
    expect(g.attachedTo('m1', '커피'), isFalse);
    expect(g.attachedTo('m2', '커피'), isTrue);
    expect(g.attachedTo('m9', '음식'), isTrue);
    expect(g.attachedTo('m3', '음식'), isFalse);
  });

  test('메뉴 전용 옵션은 앞에 그대로, 목록 옵션은 뒤에 목록 순서로', () {
    final own = {
      'groupName': '종류',
      'isRequired': true,
      'options': [
        {'name': '자몽', 'price': 0},
      ],
    };
    final out = menuGroupsWithLibrary(menuId: 'm2', category: '커피', current: [own], groups: [temp(), shot()]);
    expect(out.map((g) => g['groupName']).toList(), ['종류', '온도', '추가']);
    expect(out[1]['libraryId'], 'gTemp');
    expect(out[1].containsKey('maxSelect'), isFalse); // 1이면 안 씀
    expect(out[2]['maxSelect'], 2);
    expect((out[2]['options'] as List)[1], {'name': '얼음 컵 추가', 'price': 500, 'soldOut': true});
    expect((out[2]['options'] as List)[0].containsKey('soldOut'), isFalse);
  });

  test('목록에서 지우거나 안 붙으면 복사본이 빠짐', () {
    final cur = [temp().menuCopy(), shot().menuCopy()];
    final out = menuGroupsWithLibrary(menuId: 'm5', category: '커피', current: cur, groups: [temp()]);
    expect(out.map((g) => g['libraryId']).toList(), ['gTemp']);
  });

  test('이름이 같으면 번역을 이어받고, 바뀌면 버림', () {
    final old = temp().menuCopy();
    old['translations'] = {'en': {'groupName': 'Temperature'}, '_src': 'x'};
    (old['options'] as List)[0] = <String, dynamic>{
      ...((old['options'] as List)[0] as Map<String, dynamic>),
      'translations': {'en': {'name': 'Iced'}},
    };
    final same = menuGroupsWithLibrary(menuId: 'm1', category: '커피', current: [old], groups: [temp()]).single;
    expect(same['translations'], isNotNull);
    expect((same['options'] as List)[0]['translations'], isNotNull);
    expect(sameJson(same, old), isTrue); // 그대로면 다시 안 씀

    final renamed = temp()..name = '온도 선택';
    renamed.options[0].name = '아이스';
    final out = menuGroupsWithLibrary(menuId: 'm1', category: '커피', current: [old], groups: [renamed]).single;
    expect(out.containsKey('translations'), isFalse);
    expect((out['options'] as List)[0].containsKey('translations'), isFalse);
  });

  test('가져오기: 같은 모양의 메뉴 전용 옵션을 목록 복사본으로 바꿈', () {
    final own = {
      'groupName': '온도',
      'isRequired': true,
      'options': [
        {'name': 'ICE', 'price': 0},
        {'name': 'HOT', 'price': 0},
      ],
    };
    final g = temp()..importSig = ownGroupSignature(own);
    final out = menuGroupsWithLibrary(menuId: 'm1', category: '커피', current: [own], groups: [g]);
    expect(out.length, 1);
    expect(out.single['libraryId'], 'gTemp');
    // 붙지 않는 메뉴의 같은 옵션은 그대로 둠
    final other = menuGroupsWithLibrary(menuId: 'm7', category: '음식', current: [own], groups: [g]);
    expect(other.single.containsKey('libraryId'), isFalse);
  });

  test('저장 모양 왕복', () {
    final g = OptionLibGroup.fromJson(shot().toJson());
    expect(g.id, 'gShot');
    expect(g.maxSelect, 2);
    expect(g.options[1].soldOut, isTrue);
    expect(g.menuIds, ['m2']);
    expect(OptionLibGroup.fromJson({'name': 'x', 'maxSelect': 0}).maxSelect, 1);
  });
}
