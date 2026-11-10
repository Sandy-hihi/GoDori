import 'package:flutter/material.dart';

import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/services/store_features.dart';
import 'package:boardpad/screens/admin_toss_pos_screen.dart';

const _navy = Color(0xFF1E2B3C);
const _toss = Color(0xFF3182F6);

/// 관리자 웹 '매장 설정' — 기능 켜기·끄기 카드 (59차)
///   패드 관리자 대시보드(방 번호 0): 사장님이 여기서 켜고 끔 (서버 /api/store/features)
///   토스 POS 연동: 운영자 페이지에서만 바꿈 — 여기서는 지금 상태만 보여 줌
class StoreFeaturesCard extends StatefulWidget {
  const StoreFeaturesCard({super.key});

  @override
  State<StoreFeaturesCard> createState() => _StoreFeaturesCardState();
}

class _StoreFeaturesCardState extends State<StoreFeaturesCard> {
  late final Stream<StoreFeatures> _stream = StoreFeaturesService.watch();
  bool _saving = false;

  Future<void> _setDashboard(bool on) async {
    if (_saving) return;
    if (!on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('패드 관리자 대시보드를 끌까요?', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('패드에서 방 번호 0으로 로그인할 수 없게 되고, 지금 열려 있는 패드 대시보드도 바로 닫혀요.\n'
              // DEF-017(91차): 관리자 웹엔 주문 화면이 없음(주문은 매장 관리자 패드에서 — 11/8 팀 결정)
              '관리자 웹에는 주문 화면이 없어서, 끄면 패드 주문은 토스 POS(연동 매장)에서만 볼 수 있어요. 언제든 다시 켤 수 있어요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('끄기')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await StoreFeaturesService.setAdminDashboard(on);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(on ? '패드 관리자 대시보드를 켰어요. 방 번호 0 + PIN으로 들어갈 수 있어요.' : '패드 관리자 대시보드를 껐어요.'),
      ));
    } on AdminLoginException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _row({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: Colors.black54, height: 1.45)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
  }

  Widget _badge(bool on) {
    final c = on ? _toss : Colors.black45;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(on ? '사용 중' : '사용 안 함', style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: StreamBuilder<StoreFeatures>(
        stream: _stream,
        builder: (context, snap) {
          final f = snap.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('기능 사용', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  if (_saving || f == null)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 6),
              const Text('매장에서 쓰는 기능만 켜 두세요.', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              _row(
                icon: Icons.dashboard_outlined,
                color: _navy,
                title: '패드 관리자 대시보드 (방 번호 0)',
                description: '매장 패드에서 방 번호 0 + 관리자 PIN으로 들어가는 주문 현황 화면이에요.\n'
                    '주문을 토스 POS로만 보신다면 꺼 두셔도 돼요. (관리자 웹에는 주문 화면이 없어요)',
                trailing: Switch(
                  value: f?.adminDashboard ?? true,
                  activeTrackColor: _navy,
                  onChanged: (f == null || _saving) ? null : _setDashboard,
                ),
              ),
              const Divider(height: 24),
              _row(
                icon: Icons.point_of_sale_outlined,
                color: _toss,
                title: '토스 POS 연동',
                description: '패드 주문을 토스 POS로 보내는 기능이에요. 연동 신청·설정은 고도리 운영자에게 요청해 주세요.',
                trailing: f == null
                    ? const SizedBox.shrink()
                    : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        _badge(f.tossPos),
                        // 64차: 메뉴 연결·보내지 못한 주문
                        if (f.tossPos)
                          TextButton(
                            onPressed: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => const AdminTossPosScreen())),
                            child: const Text('연동 설정'),
                          ),
                      ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
