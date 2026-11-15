import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/models/staff_call_reason.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:flutter/material.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/services/store_scope.dart';

class StaffCallService {
  /// 직원 호출 창을 띄움. 손님이 사유를 누르면 바로 호출이 가고, 창 안에서 '전달했어요'를 보여 줌.
  /// (예전: "직원을 호출하시겠습니까?" 확인만 — 왜 불렀는지 직원이 모르고, 보냈는지 손님도 확인이 안 됐음)
  static Future<void> callStaff(BuildContext context, int roomNumber) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => StaffCallDialog(onSend: (reason) => sendCall(roomNumber, reason.key)),
    );
  }

  /// 호출 문서 만들기 — 보안 규칙: 로그인한 그 방 패드만, 자기 방 번호로 호출 가능
  static Future<void> sendCall(int roomNumber, String reasonKey) async {
    await AdminSession.ensureSignedIn();
    final col = StoreScope.col('staff_calls');
    final base = <String, dynamic>{
      'roomNumber': roomNumber,
      'timestamp': FieldValue.serverTimestamp(),
      'isAcknowledged': false,
    };
    try {
      await col.add({...base, 'reason': reasonKey});
    } on FirebaseException catch (e) {
      // 보안 규칙이 아직 reason 필드를 모르면(규칙 배포 전) 거절됨 → 사유 없이 예전 모양으로 다시 보냄.
      // 앱과 규칙의 배포 순서가 어긋나도 호출 자체는 끊기지 않게 하려는 것. 규칙이 배포된 뒤에는 이 길로 오지 않음
      if (e.code != 'permission-denied') rethrow;
      await col.add(base);
    }
  }
}

/// 직원 호출 창 — 사유 타일을 누르면 [onSend] 로 보내고 결과를 창 안에 보여 줌.
/// [onSend] 를 밖에서 받는 건 화면 테스트에서 서버 없이 확인하려는 것 (test/staff_call_reason_test.dart)
class StaffCallDialog extends StatefulWidget {
  const StaffCallDialog({super.key, required this.onSend});

  final Future<void> Function(StaffCallReason reason) onSend;

  @override
  State<StaffCallDialog> createState() => _StaffCallDialogState();
}

class _StaffCallDialogState extends State<StaffCallDialog> {
  final Set<String> _sent = {}; // 이 창에서 이미 보낸 사유 — 같은 걸 두 번 못 누르게
  String? _sending; // 보내는 중인 사유 key
  StaffCallReason? _lastSent;
  String? _error;

  Future<void> _send(StaffCallReason reason) async {
    if (_sending != null || _sent.contains(reason.key)) return;
    setState(() {
      _sending = reason.key;
      _error = null;
    });
    try {
      await widget.onSend(reason);
      if (!mounted) return;
      setState(() {
        _sent.add(reason.key);
        _lastSent = reason;
        _sending = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = null;
        _error = e is AdminLoginException ? e.message : '직원 호출을 보내지 못했어요. 인터넷 연결을 확인해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, c) {
                  // 패드는 3칸, 좁은 화면(폰)은 2칸
                  final cols = c.maxWidth >= 520 ? 3 : 2;
                  const gap = 12.0;
                  final tileWidth = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final r in staffCallReasons) SizedBox(width: tileWidth, height: 136, child: _tile(r)),
                    ],
                  );
                },
              ),
              if (_lastSent != null || _error != null) ...[
                const SizedBox(height: 14),
                _statusBanner(),
              ],
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: kInk,
                    minimumSize: const Size(140, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const GuestText('닫기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: kOrange, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GuestText('직원 호출', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kInk)),
              SizedBox(height: 2),
              GuestText(
                '필요한 걸 누르면 바로 직원에게 전달돼요',
                style: TextStyle(fontSize: 15, color: kMuted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(StaffCallReason r) {
    final sent = _sent.contains(r.key);
    final sending = _sending == r.key;
    final enabled = _sending == null && !sent;
    final fg = sent ? Colors.white : kInk;
    return Material(
      color: sent ? kOrange : kBg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => _send(r) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 32,
                child: sending
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 3, color: kOrange),
                      )
                    : Icon(sent ? Icons.check_circle_rounded : r.icon, size: 30, color: sent ? Colors.white : kOrange),
              ),
              const SizedBox(height: 8),
              // 번역문이 길어도 잘리지 않게 한 줄 안에서 글자를 줄임
              FittedBox(
                fit: BoxFit.scaleDown,
                child: GuestText(
                  r.label,
                  maxLines: 1,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg),
                ),
              ),
              const SizedBox(height: 2),
              GuestText(
                r.hint,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.3, color: sent ? Colors.white70 : kMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBanner() {
    final isError = _error != null;
    final color = isError ? const Color(0xFFC0392B) : const Color(0xFF1E7B4F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFDECEA) : const Color(0xFFE8F5EE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: color, size: 22),
          const SizedBox(width: 10),
          if (!isError) ...[
            GuestText(_lastSent!.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: GuestText(
              isError ? _error! : '직원에게 전달했어요. 잠시만 기다려 주세요.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
