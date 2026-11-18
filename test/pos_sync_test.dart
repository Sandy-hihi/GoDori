import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/screens/admin_pos_sync_dialog.dart';
import 'package:boardpad/services/toss_pos_service.dart';

// 121차: 포스와 다른 메뉴 맞추기 — 가격(골라 둔 필수 선택 값 포함)·옵션·이름 비교
void main() {
  const temp = TossCatalogOption(id: 'o1', title: '온도', required: true, choices: [
    TossCatalogChoice('c1', 'HOT', 0),
    TossCatalogChoice('c2', 'ICE', 500),
  ]);
  const shot = TossCatalogOption(id: 'o2', title: '샷', required: false, choices: [TossCatalogChoice('c3', '샷 추가', 500)]);
  const item = TossCatalogItem(id: 'i1', title: '아메리카노', category: '커피', price: 3500, soldOut: false, options: [temp, shot]);

  test('같으면 다른 점 없음', () {
    final d = PosSyncDiff.compare('m1', {
      'name': '아메리카노',
      'price': 3500,
      'optionGroups': [
        {'groupName': '온도', 'isRequired': true, 'options': [{'name': 'HOT', 'price': 0}, {'name': '아이스', 'price': 500}]},
        {'groupName': '샷', 'isRequired': false, 'options': [{'name': '샷추가', 'price': 500}]},
      ],
    }, const TossMenuLink('i1'), item);
    expect(d.any, isFalse);
  });

  test('가격·옵션 다르면 포스 값으로 — 번역·품절은 이어받고 포스에 없는 메뉴 전용 그룹은 뺌, 옵션 목록 그룹은 그대로', () {
    final d = PosSyncDiff.compare('m1', {
      'name': '아메리카노(HOT)',
      'price': 3000,
      'optionGroups': [
        {'groupName': '온도', 'isRequired': false, 'options': [
          {'name': 'HOT', 'price': 0, 'soldOut': true, 'translations': {'en': {'name': 'Hot'}}},
        ]},
        {'groupName': '사이즈', 'options': [{'name': '라지', 'price': 1000}]},
        {'groupName': '샷', 'libraryId': 'L1', 'options': [{'name': '샷 추가', 'price': 300}]},
      ],
    }, const TossMenuLink('i1'), item);
    expect(d.priceDiff, isTrue);
    expect(d.posPrice, 3500);
    expect(d.nameDiff, isTrue);
    expect(d.optionDiff, isTrue);
    final g = d.newGroups!;
    expect(g[0]['isRequired'], isTrue);
    final opts = g[0]['options'] as List;
    expect(opts.length, 2);
    expect((opts[0] as Map)['soldOut'], isTrue); // 이어받음
    expect((opts[0] as Map)['translations'], isNotNull);
    expect((opts[1] as Map)['name'], 'ICE');
    expect(g.any((x) => x['groupName'] == '사이즈'), isFalse); // 뺌
    expect(g.firstWhere((x) => x['groupName'] == '샷')['libraryId'], 'L1'); // 그대로
    expect(d.libraryNotes.single, contains('샷'));
  });

  test('골라 둔 필수 선택 값도 가격에 더함, 그 옵션은 비교에서 뺌', () {
    final d = PosSyncDiff.compare('m2', {'name': '아이스 아메리카노', 'price': 4000, 'optionGroups': [
      {'groupName': '샷', 'isRequired': false, 'options': [{'name': '샷 추가', 'price': 500}]},
    ]}, const TossMenuLink('i1', {'o1': 'c2'}), item);
    expect(d.priceDiff, isFalse); // 3500 + ICE 500
    expect(d.optionDiff, isFalse);
  });
}
