import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/models/home_layout.dart';

void main() {
  // 135차: 사용자 사진의 배치 — 맨 아래 '추천 게임' 오른쪽 3칸 × 0.5칸만 빔
  HomeLayout photoLayout() {
    GridItem g(String id, String type, int x, int y, int w, int h) =>
        GridItem(id: id, type: type, x: x, y: y, w: w, h: h);
    final base = HomeLayout.defaults();
    return base.copyWith(widgets: [
      g('a', 'greeting', 0, 0, 4, 1),
      g('b', 'search', 4, 0, 2, 1),
      g('c', 'foodOrder', 0, 1, 2, 6),
      g('d', 'gameList', 2, 1, 2, 6),
      g('e', 'clock', 4, 1, 2, 1),
      g('f', 'room', 4, 2, 2, 1),
      g('h', 'notice', 4, 3, 2, 3),
      g('i', 'event', 4, 6, 2, 2),
      g('j', 'recommended', 0, 7, 1, 1),
    ]);
  }

  test('135차 빈칸 덩어리: 꽉 찬 기본 배치는 없음, 사진 배치는 3×0.5 하나', () {
    expect(HomeLayout.defaults().emptyAreas(), isEmpty);
    final areas = photoLayout().emptyAreas();
    expect(areas, [(x: 1, y: 7, w: 3, h: 1)]);
  });

  test('135차 와이파이는 0.5칸 빈자리에 3×0.5로 들어감, 1×1이 필요한 위젯은 안 들어감', () {
    final wifi = specOf('wifi')!;
    expect(HomeLayout.fitSize(wifi, 3, 1), const WidgetSize(3, 1));
    expect(HomeLayout.fitSize(wifi, 2, 1), const WidgetSize(2, 1));
    expect(HomeLayout.fitSize(wifi, 1, 2), const WidgetSize(1, 2));
    expect(HomeLayout.fitSize(wifi, 1, 1), const WidgetSize(1, 1)); // 137차 1×0.5 버튼
    expect(HomeLayout.fitSize(specOf('dice')!, 3, 1), isNull);
    final layout = photoLayout();
    expect(layout.findSpot(3, 1), (x: 1, y: 7));
    expect(layout.findSpot(1, 2), isNull);
  });
}
