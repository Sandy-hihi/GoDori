import 'package:flutter/material.dart';
import 'package:boardpad/services/admin_session.dart';

const _navy = Color(0xFF1E2B3C);

/// 사장님 가입 신청 (48차) — 관리자 웹 로그인 화면의 '회원가입'
/// 신청하면 '승인 대기' 매장이 만들어지고, 운영자 페이지(/ops)에서 승인해야 로그인할 수 있음.
/// 패드 비밀번호·관리자 PIN은 승인 뒤 관리자 웹 → 매장 설정에서 정함.
class AdminSignupScreen extends StatefulWidget {
  const AdminSignupScreen({super.key});

  @override
  State<AdminSignupScreen> createState() => _AdminSignupScreenState();
}

class _AdminSignupScreenState extends State<AdminSignupScreen> {
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _agree = false;
  bool _busy = false;
  bool _done = false;
  String? _error;
  String? _idMessage; // 아이디 확인 결과
  bool? _idOk;

  static final _idRe = RegExp(r'^[a-z0-9][a-z0-9-]{2,29}$');

  @override
  void dispose() {
    for (final c in [_id, _name, _owner, _phone, _pw, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkId() async {
    final id = _id.text.trim().toLowerCase();
    if (!_idRe.hasMatch(id)) {
      setState(() {
        _idOk = false;
        _idMessage = '영어 소문자·숫자·-로 3~30자 (첫 글자는 영어·숫자)';
      });
      return;
    }
    try {
      final ok = await AdminSession.isStoreIdAvailable(id);
      if (!mounted) return;
      setState(() {
        _idOk = ok;
        _idMessage = ok ? '쓸 수 있는 아이디예요.' : '이미 쓰고 있는 아이디예요.';
      });
    } on AdminLoginException catch (e) {
      if (mounted) {
        setState(() {
          _idOk = false;
          _idMessage = e.message;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    String? err;
    if (!_idRe.hasMatch(_id.text.trim().toLowerCase())) {
      err = '매장 아이디를 확인해 주세요.';
    } else if (_name.text.trim().isEmpty) {
      err = '매장 이름을 입력해 주세요.';
    } else if (_owner.text.trim().isEmpty) {
      err = '사장님 이름을 입력해 주세요.';
    } else if (_phone.text.trim().length < 9) {
      err = '연락처를 입력해 주세요. (승인 연락용)';
    } else if (_pw.text.trim().length < 8) {
      err = '관리자 웹 비밀번호는 8자 이상으로 정해 주세요.';
    } else if (_pw.text.trim() != _pw2.text.trim()) {
      err = '비밀번호 확인이 달라요.';
    } else if (!_agree) {
      err = '이름·연락처 저장에 동의해 주세요.';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminSession.signup(
        storeId: _id.text,
        storeName: _name.text,
        ownerName: _owner.text,
        phone: _phone.text,
        webPassword: _pw.text.trim(),
      );
      await AdminSession.savePrefs(storeId: _id.text.trim().toLowerCase(), prefix: 'web.');
      if (mounted) setState(() => _done = true);
    } on AdminLoginException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {String? helper, bool obscure = false, TextInputType? type, ValueChanged<String>? onChanged, Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        enabled: !_busy,
        obscureText: obscure,
        keyboardType: type,
        autocorrect: false,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          prefixIcon: Icon(icon),
          suffixIcon: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _doneView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64, color: _navy),
        const SizedBox(height: 16),
        const Text('가입 신청이 접수됐어요', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          '매장 아이디 ${_id.text.trim().toLowerCase()}\n운영자가 확인하고 승인하면 로그인할 수 있어요.\n'
          '승인되면 남겨 주신 연락처로 알려 드릴게요.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, height: 1.6),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
            child: const Text('로그인 화면으로', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: _done
                ? _doneView()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: '로그인 화면으로',
                            onPressed: _busy ? null : () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          const SizedBox(width: 4),
                          const Text('고도리 가입 신청', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('신청 후 운영자 승인이 끝나면 관리자 웹을 쓸 수 있어요.',
                          style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 20),
                      _field(
                        _id,
                        '매장 아이디 (로그인 아이디)',
                        Icons.storefront_outlined,
                        helper: _idMessage ?? '영어 소문자·숫자·- 3~30자. 패드 로그인에도 써요. 나중에 못 바꿔요.',
                        onChanged: (_) {
                          if (_idOk != null) {
                            setState(() {
                              _idOk = null;
                              _idMessage = null;
                            });
                          }
                        },
                        suffix: TextButton(
                          onPressed: _busy ? null : _checkId,
                          child: Text(_idOk == true ? '확인됨' : '중복 확인',
                              style: TextStyle(color: _idOk == false ? Colors.redAccent : null)),
                        ),
                      ),
                      _field(_name, '매장 이름', Icons.badge_outlined, helper: '패드·관리자 웹에 보이는 이름 (홈 화면 꾸미기에서 따로 바꿀 수 있어요)'),
                      _field(_owner, '사장님 이름', Icons.person_outline),
                      _field(_phone, '연락처', Icons.phone_outlined, type: TextInputType.phone, helper: '승인 결과를 알려 드릴 번호'),
                      _field(_pw, '관리자 웹 비밀번호', Icons.lock_outline, obscure: true, helper: '8자 이상'),
                      _field(_pw2, '비밀번호 확인', Icons.lock_outline, obscure: true),
                      Material(
                        type: MaterialType.transparency,
                        child: CheckboxListTile(
                        value: _agree,
                        onChanged: _busy ? null : (v) => setState(() => _agree = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: _navy,
                        title: const Text('가입 승인 연락을 위해 이름·연락처를 저장하는 데 동의해요', style: TextStyle(fontSize: 14)),
                      ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: _busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('가입 신청', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
