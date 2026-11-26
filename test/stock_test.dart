import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/services/stock_service.dart';
import 'package:boardpad/stock/stock_app.dart';

// 148차 재고관리 — 화면 없는 계산
void main() {
  const cola = StockItem(id: 'a', name: '콜라', category: '음료', unit: '캔', order: 20, minQty: 24);
  const cup = StockItem(id: 'b', name: '종이컵', category: '소모품', unit: '줄', order: 10, minQty: 5);
  const cider = StockItem(id: 'c', name: '사이다', category: '음료', unit: '캔', order: 30);

  test('정렬·카테고리 묶기: 순서대로, 카테고리는 첫 항목 순서', () {
    final g = groupStockItems([cola, cider, cup]);
    expect(g.map((e) => e.key).toList(), ['소모품', '음료']);
    expect(g[1].value.map((e) => e.name).toList(), ['콜라', '사이다']);
    expect(const StockItem(id: 'x', name: 'x').categoryLabel, '기타');
  });

  test('숫자 글자·차이·부족', () {
    expect(stockNum(3.0), '3');
    expect(stockNum(2.5), '2.5');
    expect(stockNum(1234), '1,234');
    expect(stockNum(-1500), '-1,500');
    expect(stockNum(null), '-');
    expect(stockDiffText(10, 7), '+3');
    expect(stockDiffText(5, 7), '-2');
    expect(stockDiffText(5, 5), '0');
    expect(stockDiffText(5, null), isNull);
    expect(stockLow(3, 5), isTrue);
    expect(stockLow(5, 5), isFalse);
    expect(stockLow(null, 5), isFalse);
    expect(stockLow(3, null), isFalse);
  });

  test('입력 글자 읽기', () {
    expect(parseStockInput('').value, isNull);
    expect(parseStockInput('').ok, isTrue);
    expect(parseStockInput('12').value, 12);
    expect(parseStockInput('1,200').value, 1200);
    expect(parseStockInput('2.5').value, 2.5);
    expect(parseStockInput('3.').value, 3);
    expect(parseStockInput('-1').ok, isFalse);
    expect(parseStockInput('abc').ok, isFalse);
    expect(parseStockInput('1.234').ok, isFalse);
    expect(parseStockInput('12345678').ok, isFalse);
  });

  test('한꺼번에 추가 글', () {
    final rows = parseStockBulk('// 메모\n# 음료 냉장고\n콜라 | 캔 | 24\n사이다\n\n# 소모품\n종이컵 | 줄 | 5\n물티슈 | | x');
    expect(rows.length, 4);
    expect(rows[0].name, '콜라');
    expect(rows[0].category, '음료 냉장고');
    expect(rows[0].unit, '캔');
    expect(rows[0].minQty, 24);
    expect(rows[1].unit, '개');
    expect(rows[1].minQty, isNull);
    expect(rows[2].category, '소모품');
    expect(rows[3].unit, '개');
    expect(rows[3].minQty, isNull);
  });

  test('직전 끝난 조사·엑셀용 표', () {
    const done1 = StockCount(id: 'd1', title: '1차', status: 'done', counts: {'a': 20, 'b': 6});
    const open = StockCount(id: 'o', title: '2차', status: 'open', counts: {'a': 10});
    const done0 = StockCount(id: 'd0', title: '0차', status: 'done', counts: {'a': 30});
    final recent = [open, done1, done0];
    expect(previousDoneCount(recent, open)?.id, 'd1');
    expect(previousDoneCount(recent, done1)?.id, 'd0');
    expect(previousDoneCount(recent, done0), isNull);

    final table = stockCountTable(open, [cola, cup, cider], previous: done1).trim().split('\n');
    expect(table.first, '카테고리\t항목\t단위\t수량\t적정 재고\t직전\t차이');
    expect(table, contains('음료\t콜라\t캔\t10\t24\t20\t-10'));
    expect(table, contains('소모품\t종이컵\t줄\t\t5\t6\t'));
    // 지운 항목도 기록에 있으면 이름(끝낼 때 저장한 이름)으로
    const withGone = StockCount(id: 'g', title: 'g', status: 'done', counts: {'z': 3}, items: {'z': {'name': '옛 항목', 'unit': '병', 'category': '창고'}});
    expect(stockCountTable(withGone, [cola]), contains('창고\t옛 항목\t병\t3'));
  });

  test('조사 제목·시간', () {
    expect(stockCountTitle(DateTime(2026, 11, 24)), '11월 24일 (화) 재고 조사');
    expect(stockTime(DateTime(2026, 11, 24, 9, 5)), '11/24 09:05');
  });

  test('재고 앱 로그인 표시: 직원·사장님만, 패드·관리자 토큰은 아님', () {
    expect(StockAuth.sessionFromClaims({'stock': true, 'store': 'platform6'})?.owner, isFalse);
    expect(StockAuth.sessionFromClaims({'stock': true, 'admin': true, 'store': 'platform6'})?.owner, isTrue);
    expect(StockAuth.sessionFromClaims({'admin': true, 'store': 'platform6'}), isNull);
    expect(StockAuth.sessionFromClaims({'pad': true, 'room': 3, 'store': 'platform6'}), isNull);
    expect(StockAuth.sessionFromClaims({'stock': true, 'store': 'BAD ID'}), isNull);
    expect(StockAuth.sessionFromClaims(null), isNull);
  });
}
