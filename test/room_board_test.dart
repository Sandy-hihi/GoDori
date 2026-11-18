import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/models/room_board.dart';

// 112차: 방 현황판 — 방마다 상태·주문 수·호출·합계
void main() {
  test('빈 방·이용 중·결제 대기', () {
    final board = buildRoomBoard(
      roomCount: 4,
      roomStatus: {
        '1': {
          'open': ['o1'],
          'cycle': [
            {'id': 'o1', 'at': '2026-11-17T12:00:00Z', 'price': '8000', 'state': 'open'},
            {'id': 'o0', 'at': '2026-11-17T11:30:00Z', 'price': '5,000', 'state': 'paid'},
            {'id': 'ox', 'at': '2026-11-17T11:40:00Z', 'price': '3000', 'state': 'cancelled'},
          ],
        },
        '3': {'open': [], 'cycle': [], 'settledAt': '2026-11-17T13:00:00Z'},
      },
      orders: [
        {'id': 'a', 'room': '#2', 'status': 'pending', 'items': ['콜라 x 1'], 'price': '2000'},
        {'id': 'b', 'room': '#2', 'status': 'preparing', 'items': ['라면 x 1'], 'price': '5000'},
      ],
      calls: [
        {'roomNumber': 4, 'reason': 'water'},
      ],
    );
    expect(board.map((e) => e.room), [1, 2, 3, 4]);
    expect(board[0].state, RoomBoardState.awaitingPay);
    expect(board[0].total, 13000);
    expect(board[0].unpaid, 8000);
    expect(board[0].openCount, 1);
    expect(board[0].firstAt, DateTime.parse('2026-11-17T11:30:00Z').toLocal());
    expect(board[1].state, RoomBoardState.inUse);
    expect(board[1].countOf('pending'), 1);
    expect(board[1].countOf('preparing'), 1);
    expect(board[2].state, RoomBoardState.empty);
    expect(board[2].settledAt, isNotNull);
    expect(board[3].state, RoomBoardState.inUse);
    expect(board[3].calls.single.label, '물');
  });

  test('방 개수 밖 방은 진행 중인 것이 있을 때만', () {
    final board = buildRoomBoard(
      roomCount: 2,
      roomStatus: {
        '5': {'open': [], 'cycle': []},
      },
      orders: [
        {'id': 'a', 'room': '#7', 'status': 'ready'},
      ],
    );
    expect(board.map((e) => e.room), [1, 2, 7]);
    expect(board.last.beyondCount, isTrue);
    expect(board.last.countOf('ready'), 1);
  });

  test('roomFromOrder · 지난 시간 글자', () {
    expect(roomFromOrder('#12'), 12);
    expect(roomFromOrder('abc'), isNull);
    final t = DateTime(2026, 11, 17, 21, 0);
    expect(roomElapsedLabel(t, t.add(const Duration(seconds: 20))), '방금');
    expect(roomElapsedLabel(t, t.add(const Duration(minutes: 35))), '35분째');
    expect(roomElapsedLabel(t, t.add(const Duration(minutes: 65))), '1시간 5분째');
    expect(roomElapsedLabel(t, t.add(const Duration(minutes: 120))), '2시간째');
  });
  test('114차: 모두 취소됨·옮겨 간 방', () {
    final board = buildRoomBoard(roomCount: 2, roomStatus: {
      '1': {
        'open': [],
        'cycle': [
          {'id': 'x', 'price': '5000', 'state': 'cancelled'},
        ],
      },
      '2': {'open': [], 'cycle': [], 'settledAt': '2026-11-18T08:00:00Z', 'movedTo': 3},
    });
    expect(board[0].allCancelled, isTrue);
    expect(board[0].total, 0);
    expect(board[1].movedTo, 3);
    expect(board[1].allCancelled, isFalse);
  });
  test('114차 2: 단체손님 묶음 — group·색 번호', () {
    final board = buildRoomBoard(roomCount: 6, roomStatus: {
      '2': {'open': [], 'cycle': [], 'group': {'id': 9, 'rooms': [2, 3]}},
      '3': {'open': [], 'cycle': [], 'group': {'id': 9, 'rooms': [2, 3]}},
      '5': {'open': [], 'cycle': [], 'group': {'id': 4, 'rooms': [5, 6]}},
      '6': {'open': [], 'cycle': [], 'group': {'id': 4, 'rooms': [5, 6]}},
      '1': {'open': [], 'cycle': [], 'group': null},
    });
    expect(board[0].group, isNull);
    expect(board[1].group!.rooms, [2, 3]);
    expect(roomGroupColorIndex(board), {9: 0, 4: 1});
  });
  test('115차: 토스 묶음 색', () {
    expect(parseGroupColor('#E05297'), 0xFFE05297);
    expect(parseGroupColor('e05297'), 0xFFE05297);
    expect(parseGroupColor('#80E05297'), 0x80E05297);
    expect(parseGroupColor('pink'), isNull);
    expect(parseGroupColor(null), isNull);
    expect(roomGroupOf({'group': {'id': 1, 'rooms': [2, 3], 'color': '#112233'}})!.color, 0xFF112233);
  });
  test('117차: 포스 계산서 — 포스에서만 넣은 주문도 결제 대기, 포스 추가 금액', () {
    final board = buildRoomBoard(roomCount: 2, roomStatus: {
      '1': {'open': [], 'cycle': [], 'posBill': {'total': 5500, 'paid': 0, 'unpaid': 5500}},
      '2': {
        'open': ['a'],
        'cycle': [
          {'id': 'a', 'price': '3500', 'state': 'open'},
        ],
        'posBill': {'total': 7500, 'paid': 0, 'unpaid': 7500},
      },
    });
    expect(board[0].state, RoomBoardState.awaitingPay);
    expect(board[0].posExtra, 5500);
    expect(board[1].total, 3500);
    expect(board[1].posExtra, 4000);
  });
}
