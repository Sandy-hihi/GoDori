import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/models/home_layout.dart';

void main() {
  final base = HomeLayout.defaults(); // 6×8칸이 꽉 찬 기본 배치

  GridItem byId(List<GridItem> list, String id) => list.firstWhere((w) => w.id == id);

  test('같은 크기 위젯 위에 놓으면 서로 자리가 바뀐다 (시계 ↔ 방 번호)', () {
    final clock = byId(base.widgets, 'w7'); // (4,1) 2×1
    final r = base.swapFor(clock.copyWith(y: 2))!;
    expect(byId(r.widgets, 'w7').y, 2);
    expect(byId(r.widgets, 'w8').y, 1);
    expect(r.displaced.map((e) => e.id), ['w8']);
  });

  test('큰 사진 카드끼리 맞바꾸기', () {
    final food = byId(base.widgets, 'w3'); // (0,1) 2×6
    final r = base.swapFor(food.copyWith(x: 2))!;
    expect(byId(r.widgets, 'w3').x, 2);
    expect(byId(r.widgets, 'w4').x, 0);
  });

  test('한 칸 어긋나게 놓아도 가장 많이 겹친 같은 크기 위젯과 바뀐다', () {
    final food = byId(base.widgets, 'w3'); // (0,1) 2×6, 옆 게임 목록 (2,1) 2×6
    final r = base.swapFor(food.copyWith(x: 1))!;
    expect(r.moved.x, 2);
    expect(byId(r.widgets, 'w3').x, 2);
    expect(byId(r.widgets, 'w4').x, 0);
  });

  test('크기가 달라 원래 자리에 안 들어가면 null', () {
    final search = byId(base.widgets, 'w2'); // (4,0) 2×1
    // 공지(2×3) 위로 → 공지가 원래 자리(위쪽)로 못 감
    expect(base.swapFor(search.copyWith(y: 4)), isNull);
  });

  test('보관함은 저장했다가 다시 읽어도 남고, 검사(겹침)에서 빠진다', () {
    final clock = byId(base.widgets, 'w7');
    final parked = base.copyWith(
      widgets: base.widgets.where((w) => w.id != 'w7').toList(),
      parked: [clock.copyWith(x: 0, y: 0)], // 격자 위치와 겹쳐도 상관없음
    );
    final back = HomeLayout.fromMap(parked.toMap())!;
    expect(back.parked.map((e) => e.id), ['w7']);
    expect(back.widgets.any((w) => w.id == 'w7'), isFalse);
  });

  test('보관함 위젯을 빈 칸에 넣기', () {
    final clock = byId(base.widgets, 'w7');
    final freed = base.copyWith(
      widgets: base.widgets.where((w) => w.id != 'w7').toList(),
      parked: [clock],
    );
    final (placed, problem) = freed.placeParked(clock, 4, 1);
    expect(problem, isNull);
    expect((placed.x, placed.y), (4, 1));
    final (_, blocked) = freed.placeParked(clock, 0, 3); // 음식 주문 카드 자리
    expect(blocked, isNotNull);
  });
}
