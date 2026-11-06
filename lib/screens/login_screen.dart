import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:boardpad/services/admin_session.dart';
import 'admin_order_screen.dart';
import 'dashboard_screen.dart';
import '../widgets/admin_pad_gate.dart';
import '../widgets/pad_shell.dart';

const _navy = Color(0xFF1E2B3C);
const _orange = Color(0xFFE2711D);

/// 패드 로그인 (47차) — 매장 아이디 + 패드 비밀번호 + 방 번호
///  - 방 번호 1~ : 그 매장 설정이 반영된 그 방 손님 화면
///  - 방 번호 0  : 비밀번호 확인 후 관리자 PIN을 한 번 더 묻고 관리자 대시보드
///                 (매장 설정에서 대시보드를 끈 매장은 서버가 막음 — 59차, 열려 있던 것도 AdminPadGate가 닫음)
///  - 자동 로그인: 켜 두면 앱을 다시 켜도 로그인 화면 없이 바로 그 방으로 (손님 방은 기본 켜짐, 0번은 기본 꺼짐)
///    로그아웃은 홈 화면 왼쪽 위(로고)를 빠르게 10번 누르기(56차) → 패드 비밀번호 또는 관리자 PIN 입력(55차) → 이 화면으로, 자동 로그인도 풀림
class LoginScreen extends StatefulWidget {
  /// 관리자 자동 로그인으로 켜졌을 때: 바로 관리자 대시보드를 엶
  final bool openAdmin;
  const LoginScreen({super.key, this.openAdmin = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final _roomController = TextEditingController();
  bool _autoLogin = true;
  bool _autoTouched = false; // 직접 바꿨으면 방 번호에 따라 자동으로 바꾸지 않음
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _roomController.addListener(_onRoomChanged);
    _loadPrefs();
    if (widget.openAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAdmin());
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final p = await AdminSession.loadPrefs();
    if (!mounted) return;
    setState(() {
      if (_idController.text.isEmpty) _idController.text = p.storeId;
      if (_roomController.text.isEmpty && p.room != null) _roomController.text = '${p.room}';
    });
  }

  void _onRoomChanged() {
    if (_autoTouched) return;
    final isAdminRoom = _roomController.text.trim() == '0';
    if (_autoLogin == isAdminRoom) setState(() => _autoLogin = !isAdminRoom);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final id = _idController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final room = int.tryParse(_roomController.text.trim());
    if (id.isEmpty || password.isEmpty || room == null) {
      setState(() => _error = '매장 아이디, 비밀번호, 방 번호를 모두 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var result = await AdminSession.storeLogin(storeId: id, password: password, room: room);
      if (result.needPin) {
        if (!mounted) return;
        setState(() => _busy = false);
        final pinResult = await _askPin(id, password);
        if (pinResult == null) return; // 취소
        result = pinResult;
      }
      final session = result.session!;
      await AdminSession.savePrefs(storeId: id, room: room, autoLogin: _autoLogin);
      if (!mounted) return;
      _passwordController.clear();
      setState(() => _busy = false);
      if (session.isAdmin) {
        await _openAdmin();
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: PadShell.homeRouteName),
            builder: (_) => DashboardScreen(roomNumber: session.room),
          ),
          (_) => false,
        );
      }
    } on AdminLoginException catch (e) {
      if (!mounted) return;
      _passwordController.clear();
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  /// 관리자 대시보드. 나오면 로그아웃 (패드에 관리자 권한이 남지 않게) — 자동 로그인도 풂
  Future<void> _openAdmin() async {
    final closed = await Navigator.push(context, adminPadRoute(const AdminOrderScreen()));
    await AdminSession.signOut();
    await AdminSession.savePrefs(storeId: _idController.text.trim().toLowerCase(), autoLogin: false);
    if (!mounted) return;
    setState(() {
      _autoTouched = false;
      _autoLogin = _roomController.text.trim() != '0';
      if (closed == AdminPadGate.closedByOwner) {
        _error = '매장 설정에서 패드 관리자 대시보드를 꺼서 닫았어요. 주문 관리는 관리자 웹에서 해 주세요.';
      }
    });
  }

  /// 방 번호 0: 관리자 PIN을 한 번 더 물음. 맞으면 로그인 결과, 취소하면 null
  Future<StoreLoginResult?> _askPin(String id, String password) {
    final pinController = TextEditingController();
    bool checking = false;
    String? errorText;
    return showDialog<StoreLoginResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          Future<void> submit() async {
            if (checking) return;
            final pin = pinController.text.trim();
            if (pin.isEmpty) return;
            setDlg(() {
              checking = true;
              errorText = null;
            });
            try {
              final r = await AdminSession.storeLogin(storeId: id, password: password, room: 0, pin: pin);
              if (ctx.mounted) Navigator.pop(ctx, r);
            } on AdminLoginException catch (e) {
              if (!ctx.mounted) return;
              pinController.clear();
              setDlg(() {
                checking = false;
                errorText = e.message;
              });
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.lock, color: _navy),
                SizedBox(width: 8),
                Text('관리자 인증', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('방 번호 0은 관리자 대시보드예요.\n관리자 PIN을 입력하세요.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                TextField(
                  controller: pinController,
                  autofocus: true,
                  obscureText: true,
                  enabled: !checking,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 10,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '• • • • • •',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _navy, width: 2),
                    ),
                    errorText: errorText,
                    errorMaxLines: 2,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: checking ? null : () => Navigator.pop(ctx),
                child: const Text('취소', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: checking ? null : submit,
                style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
                child: checking
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon, {String? helper, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _navy, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdminRoom = _roomController.text.trim() == '0';
    return Scaffold(
      backgroundColor: _navy,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: Container(
            width: 440,
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.casino_rounded, size: 56, color: _orange),
                  const SizedBox(height: 12),
                  const Text('고도리 패드 로그인',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('매장 직원이 처음 한 번만 해 주세요',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _idController,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: _decoration('매장 아이디', Icons.storefront_outlined),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: !_showPassword,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.password],
                    decoration: _decoration(
                      '비밀번호',
                      Icons.lock_outline,
                      suffix: IconButton(
                        tooltip: _showPassword ? '비밀번호 숨기기' : '비밀번호 보기',
                        icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _roomController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: _decoration('방 번호', Icons.meeting_room_outlined,
                        helper: isAdminRoom ? '0 = 관리자 대시보드 (로그인 후 PIN을 한 번 더 물어요)' : '관리자 대시보드는 0'),
                  ),
                  const SizedBox(height: 6),
                  // 흰 카드(Container) 위라 눌림 효과가 보이게 Material로 한 번 감쌈 (54차)
                  Material(
                    type: MaterialType.transparency,
                    child: CheckboxListTile(
                    value: _autoLogin,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                              _autoLogin = v ?? false;
                              _autoTouched = true;
                            }),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: _navy,
                    title: const Text('자동 로그인', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      isAdminRoom
                          ? '관리자는 꺼 두는 걸 추천해요. 켜면 앱을 켤 때 PIN 없이 대시보드가 열려요.'
                          : '앱을 껐다 켜도 이 방으로 바로 들어가요.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('로그인', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
