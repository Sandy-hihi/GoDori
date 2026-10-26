import 'package:flutter/material.dart';

import 'package:boardpad/services/room_settings_service.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';
import 'admin_event_manage_screen.dart';
import 'admin_game_manage_screen.dart';
import 'admin_home_layout_screen.dart';
import 'admin_menu_manage_screen.dart';
import 'admin_notice_manage_screen.dart';

/// 관리자 웹: 매장 설정 (방 개수)
class AdminStoreSettingsScreen extends StatefulWidget {
  const AdminStoreSettingsScreen({super.key});

  @override
  State<AdminStoreSettingsScreen> createState() => _AdminStoreSettingsScreenState();
}

const _navy = Color(0xFF1E2B3C);
const _green = Color(0xFF00B37E);

class _AdminStoreSettingsScreenState extends State<AdminStoreSettingsScreen> {
  int? _saved;
  int _count = RoomSettingsService.defaultCount;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    RoomSettingsService.loadCount().then((n) {
      if (mounted) {
        setState(() {
          _saved = n;
          _count = n;
        });
      }
    });
  }

  void _navigate(String screen) {
    final targets = <String, Widget>{
      'menu': const AdminMenuManageScreen(),
      'game': const AdminGameManageScreen(),
      'event': const AdminEventManageScreen(),
      'notice': const AdminNoticeManageScreen(),
      'home': const AdminHomeLayoutScreen(),
    };
    final target = targets[screen];
    if (target == null) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => target,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _save() async {
    final saved = _saved ?? RoomSettingsService.defaultCount;
    if (_count < saved) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('방 개수를 줄일까요?', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('${_count + 1}번 ~ $saved번 방은 방 선택 화면에서 사라지고, '
              '그 방으로 켜 둔 패드에서는 주문과 직원 호출이 안 돼요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('줄이기')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _saving = true);
    try {
      await RoomSettingsService.saveCount(_count);
      if (!mounted) return;
      setState(() => _saved = _count);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장했어요. 손님 패드의 방 선택 화면에 바로 반영돼요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장하지 못했어요. Firestore 규칙을 확인해 주세요. ($e)')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _stepButton(IconData icon, String tip, VoidCallback? onPressed) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tip,
      iconSize: 28,
      style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _saved != null && _count != _saved;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Row(
        children: [
          AdminSidebar(currentScreen: 'store', onNavigate: _navigate),
          Expanded(
            child: _saved == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('매장 설정', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 24),
                        Container(
                          constraints: const BoxConstraints(maxWidth: 720),
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('방 개수', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              const Text(
                                '손님 패드의 방 선택 화면에 나오는 방 수예요. '
                                '주문과 직원 호출도 이 번호까지만 받아요.',
                                style: TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  _stepButton(Icons.remove, '하나 줄이기',
                                      _count > RoomSettingsService.minCount ? () => setState(() => _count--) : null),
                                  SizedBox(
                                    width: 120,
                                    child: Text('$_count개',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
                                  ),
                                  _stepButton(Icons.add, '하나 늘리기',
                                      _count < RoomSettingsService.maxCount ? () => setState(() => _count++) : null),
                                  const SizedBox(width: 16),
                                  Text('(최대 ${RoomSettingsService.maxCount}개)',
                                      style: const TextStyle(color: Colors.black45)),
                                ],
                              ),
                              const SizedBox(height: 24),
                              const Text('방 선택 화면 미리보기', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(12)),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (var i = 1; i <= _count; i++)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(6)),
                                        child: Text('$i번 방',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  FilledButton.icon(
                                    onPressed: (!dirty || _saving) ? null : _save,
                                    icon: _saving
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Icon(Icons.save_outlined),
                                    label: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: FilledButton.styleFrom(backgroundColor: _navy, minimumSize: const Size(120, 48)),
                                  ),
                                  const SizedBox(width: 12),
                                  if (dirty)
                                    TextButton(
                                      onPressed: () => setState(() => _count = _saved!),
                                      child: Text('원래대로 ($_saved개)'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
