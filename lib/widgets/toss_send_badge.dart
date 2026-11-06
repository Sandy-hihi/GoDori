import 'package:flutter/material.dart';

import 'package:boardpad/services/toss_pos_service.dart';

/// 주문 카드의 '포스 전송' 표시 (64차) — 주문 문서의 tossPos 칸(서버가 적음)
///   보내는 중 / 포스 ✓ / 포스 거절·취소(웹훅) / 포스 실패 → 누르면 다시 보내기
/// 토스 POS 연동을 안 쓰는 매장 주문(tossPos 없음)에는 아무것도 안 보임
class TossSendBadge extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic>? tossPos;
  const TossSendBadge({super.key, required this.orderId, required this.tossPos});

  @override
  State<TossSendBadge> createState() => _TossSendBadgeState();
}

class _TossSendBadgeState extends State<TossSendBadge> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await TossPosService.sendOrder(widget.orderId);
      if (!mounted) return;
      final ok = r['state'] == 'sent';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? '포스로 보냈어요.' : '다시 실패했어요: ${r['error'] ?? ''}'),
      ));
    } on TossPosException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chip(String text, Color color, {IconData? icon, VoidCallback? onTap, String? tip}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_busy)
          SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: color))
        else if (icon != null)
          Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
    );
    final child = onTap == null ? chip : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: chip);
    return tip == null ? child : Tooltip(message: tip, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tossPos;
    if (t == null) return const SizedBox.shrink();
    final state = '${t['state'] ?? ''}';
    final posState = '${t['posState'] ?? ''}';
    if (state == 'sent' && (posState == 'DECLINED' || posState == 'CANCELLED' || posState == 'EXPIRED')) {
      const labels = {'DECLINED': '포스 거절', 'CANCELLED': '포스 취소', 'EXPIRED': '포스 만료'};
      return _chip(labels[posState]!, Colors.red, icon: Icons.block, tip: '${t['posReason'] ?? ''}');
    }
    if (state == 'sent') {
      final fake = t['mode'] == 'fake';
      final warn = (t['warnings'] as List?)?.join('\n') ?? '';
      return _chip(fake ? '가짜 포스 ✓' : '포스 ✓', const Color(0xFF27AE60),
          icon: Icons.point_of_sale, tip: warn.isEmpty ? null : warn);
    }
    if (state == 'sending') return _chip('포스로 보내는 중', Colors.grey, icon: Icons.schedule);
    if (state == 'failed') {
      return _chip('포스 실패 · 다시', Colors.red,
          icon: Icons.refresh, onTap: _busy ? null : _retry, tip: '${t['error'] ?? ''}');
    }
    return const SizedBox.shrink();
  }
}
