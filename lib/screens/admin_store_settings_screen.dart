import 'package:flutter/material.dart';

import 'package:boardpad/models/order_flow.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/services/order_flow_service.dart';
import 'package:boardpad/services/room_settings_service.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';
import 'package:boardpad/widgets/store_features_card.dart';
import 'admin_event_manage_screen.dart';
import 'admin_game_manage_screen.dart';
import 'admin_home_layout_screen.dart';
import 'admin_menu_manage_screen.dart';
import 'admin_notice_manage_screen.dart';

/// 관리자 웹: 매장 설정 (방 개수, 음식 수령 방식, 로그인 아이디·비밀번호)
class AdminStoreSettingsScreen extends StatefulWidget {
  const AdminStoreSettingsScreen({super.key});

  @override
  State<AdminStoreSettingsScreen> createState() => _AdminStoreSettingsScreenState();
}

const _navy = Color(0xFF1E2B3C);

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
          content: Text('${_count + 1}번 ~ $saved번 방으로는 패드 로그인이 안 되고, '
              '이미 그 방으로 로그인해 둔 패드에서는 주문과 직원 호출이 안 돼요.'),
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
        SnackBar(content: Text('저장했어요. 패드 로그인 때 1~$_count번 방을 쓸 수 있어요.')),
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
                                '패드 로그인 때 입력할 수 있는 방 번호(1번부터, 관리자는 0)예요. '
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
                        const SizedBox(height: 24),
                        const _OrderFlowCard(),
                        const SizedBox(height: 24),
                        const StoreFeaturesCard(), // 59차: 패드 관리자 대시보드 켜기·끄기, 토스 POS 연동 상태
                        const SizedBox(height: 24),
                        const _LoginCard(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 음식 수령 방식 카드 (58차) — 누르면 바로 저장. settings/orderFlow
/// 이미 들어온 주문은 주문할 때의 방식대로 처리되고, 바꾼 뒤 새로 들어오는 주문부터 새 방식.
class _OrderFlowCard extends StatefulWidget {
  const _OrderFlowCard();

  @override
  State<_OrderFlowCard> createState() => _OrderFlowCardState();
}

class _OrderFlowCardState extends State<_OrderFlowCard> {
  late final Stream<OrderFlow> _stream = OrderFlowService.watch();
  bool _saving = false;

  Future<void> _select(OrderFlow flow, OrderFlow current) async {
    if (flow == current || _saving) return;
    setState(() => _saving = true);
    try {
      await OrderFlowService.save(flow);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장했어요. 지금부터 들어오는 주문은 \'${flow.title}\' 방식이에요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장하지 못했어요. Firestore 규칙(배포.bat 5번)을 확인해 주세요. ($e)')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _option(OrderFlow flow, OrderFlow current) {
    final selected = flow == current;
    final icon = switch (flow) {
      OrderFlow.serve => Icons.room_service_outlined,
      OrderFlow.pickup => Icons.storefront_outlined,
      OrderFlow.pickupPay => Icons.payments_outlined,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? _navy.withValues(alpha: 0.06) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? _navy : Colors.black12, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _saving ? null : () => _select(flow, current),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? _navy : Colors.black38),
                const SizedBox(width: 12),
                Icon(icon, color: selected ? _navy : Colors.black54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(flow.title,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: selected ? _navy : Colors.black87)),
                      const SizedBox(height: 4),
                      Text(flow.description, style: const TextStyle(color: Colors.black54, height: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: StreamBuilder<OrderFlow>(
        stream: _stream,
        builder: (context, snap) {
          final current = snap.data ?? OrderFlow.fallback;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('음식 수령 방식', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  if (_saving) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '음식이 준비됐을 때 손님에게 어떻게 전달하는지 골라 주세요. 누르면 바로 저장돼요.\n'
                '이미 들어온 주문은 주문할 때의 방식 그대로 처리돼요.',
                style: TextStyle(color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 20),
              for (final f in OrderFlow.values) _option(f, current),
            ],
          );
        },
      ),
    );
  }
}

/// 로그인 아이디·비밀번호 카드 (비밀번호 확인·저장은 서버 /api/store/passwords — 앱은 지금 값을 읽을 수 없음)
class _LoginCard extends StatefulWidget {
  const _LoginCard();

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  final _pad = TextEditingController();
  final _pin = TextEditingController();
  final _web = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _pad.dispose();
    _pin.dispose();
    _web.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pad = _pad.text.trim();
    final pin = _pin.text.trim();
    final web = _web.text.trim();
    if (pad.isEmpty && pin.isEmpty && web.isEmpty) {
      setState(() => _error = '바꿀 비밀번호를 하나 이상 입력해 주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final changed = await AdminSession.changePasswords(
        padPassword: pad.isEmpty ? null : pad,
        pin: pin.isEmpty ? null : pin,
        webPassword: web.isEmpty ? null : web,
      );
      if (!mounted) return;
      _pad.clear();
      _pin.clear();
      _web.clear();
      const names = {'padPassword': '패드 비밀번호', 'pin': '관리자 PIN', 'webPassword': '관리자 웹 비밀번호'};
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${changed.map((c) => names[c] ?? c).join(', ')}을(를) 바꿨어요.')),
      );
    } on AdminLoginException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label, String help, {bool digits = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        enabled: !_saving,
        obscureText: true,
        keyboardType: digits ? TextInputType.number : TextInputType.visiblePassword,
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          helperMaxLines: 2,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('로그인', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            '패드는 매장 아이디 + 패드 비밀번호 + 방 번호로 로그인해요. 방 번호 0은 관리자 대시보드(PIN을 한 번 더 물음).\n'
            '비밀번호를 바꿔도 이미 로그인해 둔 패드는 그대로 써요. 새로 로그인할 때부터 새 비밀번호가 필요해요.',
            style: TextStyle(color: Colors.black54, height: 1.5),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('매장 아이디', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              SelectableText(StoreScope.isSet ? StoreScope.id : '-',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _navy)),
            ],
          ),
          const SizedBox(height: 20),
          const Text('비밀번호 바꾸기 (바꿀 것만 입력)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _field(_pad, '새 패드 비밀번호', '손님 패드 로그인용, 4자 이상. 직원들과 같이 쓰는 비밀번호예요.'),
          _field(_pin, '새 관리자 PIN', '방 번호 0으로 로그인할 때 묻는 숫자 4~10자리. 사장님만 알고 있게.', digits: true),
          _field(_web, '새 관리자 웹 비밀번호', '이 관리자 웹 로그인용, 6자 이상. 비워 두면 지금 값 그대로.'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
            ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.key_outlined),
            label: const Text('비밀번호 바꾸기', style: TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(backgroundColor: _navy, minimumSize: const Size(160, 48)),
          ),
        ],
      ),
    );
  }
}
