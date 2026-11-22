import 'package:flutter/material.dart';

/// 직원 호출 사유 — 손님이 호출할 때 고르는 항목 (리엔지니어링 실습, 2026-11-15).
/// 139차: 팀원 staff-call-reason 브랜치(406b9ec)의 이 기능만 main에 가져옴.
/// ★ lib/models/room_board.dart(방 현황판)도 이 목록의 이름을 씀.
///
/// 일반 테이블오더는 '물·앞접시·수저' 같은 식당 항목을 쓰지만,
/// 보드게임카페에서 직원을 부르는 이유는 대부분 게임(설명·교체)이라 항목을 거기에 맞춤.
///
/// [key]  Firestore stores/{매장}/staff_calls 문서의 reason 필드에 저장하는 값.
///        ★ firestore.rules 의 staff_calls 허용 목록과 같아야 함 (test/staff_call_reason_test.dart 가 검사)
/// [label]·[hint]  한국어 원문. 손님 화면은 GuestText 가 번역하고(guest_messages.dart),
///        관리자 화면은 한국어 그대로 보여 줌.
class StaffCallReason {
  const StaffCallReason(this.key, this.label, this.hint, this.icon);

  final String key;
  final String label;
  final String hint;
  final IconData icon;
}

const List<StaffCallReason> staffCallReasons = [
  StaffCallReason('rule', '게임 설명', '룰을 알려 주세요', Icons.menu_book_rounded),
  StaffCallReason('swap', '게임 추천·교체', '다른 게임으로 바꾸고 싶어요', Icons.swap_horiz_rounded),
  StaffCallReason('water', '물·컵', '물이나 컵이 필요해요', Icons.local_drink_rounded),
  StaffCallReason('clean', '테이블 정리', '자리를 치워 주세요', Icons.cleaning_services_rounded),
  StaffCallReason('pay', '계산', '계산하고 싶어요', Icons.receipt_long_rounded),
  StaffCallReason('staff', '직원 부르기', '그 밖의 요청이 있어요', Icons.notifications_active_rounded),
];

/// 저장된 reason 값 → 사유. 예전 호출(사유 없음)이나 모르는 값이면 null → 화면은 그냥 '직원 호출'로 표시
StaffCallReason? staffCallReasonOf(Object? key) {
  if (key is! String) return null;
  for (final r in staffCallReasons) {
    if (r.key == key) return r;
  }
  return null;
}
