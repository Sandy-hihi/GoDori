import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/services/stock_service.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/widgets/admin_colors.dart';

/// 고도리 재고 앱 (148차) — 직원이 휴대폰을 들고 창고를 돌며 재고 숫자를 바로 입력 (종이에 적지 않게)
///   실행: flutter run -t lib/main_stock.dart  /  APK: flutter build apk -t lib/main_stock.dart -P godoriApp=stock
///   로그인: 매장 아이디 + 패드 비밀번호(직원) 또는 관리자 웹 비밀번호(사장님) → 서버 /api/auth/stock-login
///          재고관리를 신청한 매장(features.stock — 운영자가 켬)만 들어올 수 있음
///   항목은 관리자 웹 '재고관리'에서 사장님이 만들고, 센 숫자는 관리자 웹에서 바로(실시간) 확인
///   인터넷이 끊겨도 입력한 숫자는 휴대폰에 모아 두었다가 연결되면 올라감(Firestore 오프라인 저장)
///   직원용 화면이라 한국어만(관리자 화면과 같은 80차 결정)

const _bg = Color(0xFFF4F6F8);
const _red = Color(0xFFD64545);
const _green = Color(0xFF2E9D5B);
const _orange = Color(0xFFE67E22);

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '고도리 재고',
        theme: ThemeData(
          fontFamily: 'Pretendard',
          colorScheme: ColorScheme.fromSeed(seedColor: kAdminAccent, primary: kAdminAccent),
          scaffoldBackgroundColor: _bg,
          appBarTheme: const AppBarTheme(backgroundColor: kAdminAccent, foregroundColor: Colors.white),
        ),
        home: const StockGate(),
      );
}

// ───────────────────────── 로그인 ─────────────────────────

class StockSession {
  final String store;
  final String storeName;
  final bool owner; // 관리자 웹 비밀번호로 들어온 사장님
  const StockSession({required this.store, required this.storeName, required this.owner});
}

class StockAuthException implements Exception {
  final String message;
  StockAuthException(this.message);
  @override
  String toString() => message;
}

class StockAuth {
  static const _kStore = 'stock.storeId';
  static const _kCounter = 'stock.counter';
  static final _storeIdRe = RegExp(r'^[a-z0-9][a-z0-9-]{2,29}$');

  /// 토큰 표시(claims)로 재고 앱 로그인인지 (직원 { stock, store } / 사장님 { admin, stock, store })
  static StockSession? sessionFromClaims(Map<String, dynamic>? claims, {String storeName = ''}) {
    final store = claims?['store'];
    if (store is! String || !_storeIdRe.hasMatch(store)) return null;
    if (claims?['stock'] != true) return null;
    return StockSession(store: store, storeName: storeName, owner: claims?['admin'] == true);
  }

  /// 기기에 저장된 로그인 (없거나 재고 앱 로그인이 아니면 null)
  static Future<StockSession?> restore() async {
    final auth = FirebaseAuth.instance;
    var user = auth.currentUser;
    user ??= await auth.authStateChanges().first.timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (user == null) return null;
    final s = sessionFromClaims(await tokenClaimsOf(user));
    if (s == null) return null;
    StoreScope.set(s.store);
    var name = '';
    try {
      name = ((await StoreScope.doc.get()).data()?['name'] ?? '').toString();
    } catch (_) {}
    StoreScope.set(s.store, name: name);
    return StockSession(store: s.store, storeName: name, owner: s.owner);
  }

  static Future<StockSession> login(String storeId, String password) async {
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${AdminSession.apiOrigin()}/api/auth/stock-login'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'storeId': storeId.trim().toLowerCase(), 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw StockAuthException('서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
    }
    Map<String, dynamic>? body;
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is Map<String, dynamic>) body = d;
    } catch (_) {}
    if (res.statusCode != 200 || body == null) {
      final msg = body?['message']?.toString();
      throw StockAuthException(msg != null && msg.isNotEmpty ? msg : '로그인하지 못했어요. (${res.statusCode})');
    }
    final token = body['token'];
    if (token is! String || token.isEmpty) throw StockAuthException('로그인하지 못했어요. 잠시 후 다시 시도해 주세요.');
    try {
      await FirebaseAuth.instance.signInWithCustomToken(token);
    } on FirebaseAuthException catch (e) {
      throw StockAuthException('로그인하지 못했어요. (${e.code})');
    }
    final name = (body['storeName'] ?? '').toString();
    final store = (body['store'] ?? storeId).toString();
    StoreScope.set(store, name: name);
    try {
      (await SharedPreferences.getInstance()).setString(_kStore, store);
    } catch (_) {}
    return StockSession(store: store, storeName: name, owner: body['role'] == 'owner');
  }

  static Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    StoreScope.clear();
  }

  static Future<String> lastStoreId() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_kStore) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> lastCounter() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_kCounter) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveCounter(String name) async {
    try {
      (await SharedPreferences.getInstance()).setString(_kCounter, name.trim());
    } catch (_) {}
  }
}

/// 앱 시작: 저장된 로그인이 있으면 바로 홈, 없으면 로그인
class StockGate extends StatefulWidget {
  const StockGate({super.key});

  @override
  State<StockGate> createState() => _StockGateState();
}

class _StockGateState extends State<StockGate> {
  late final Future<StockSession?> _restore = StockAuth.restore().catchError((_) => null);

  @override
  Widget build(BuildContext context) => FutureBuilder<StockSession?>(
        future: _restore,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(backgroundColor: kAdminAccent, body: Center(child: CircularProgressIndicator(color: Colors.white)));
          }
          final s = snap.data;
          return s == null ? const StockLoginScreen() : StockHomeScreen(session: s);
        },
      );
}

class StockLoginScreen extends StatefulWidget {
  const StockLoginScreen({super.key});

  @override
  State<StockLoginScreen> createState() => _StockLoginScreenState();
}

class _StockLoginScreenState extends State<StockLoginScreen> {
  final _store = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    StockAuth.lastStoreId().then((v) {
      if (mounted && _store.text.isEmpty) _store.text = v;
    });
  }

  @override
  void dispose() {
    _store.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    if (_store.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = '매장 아이디와 비밀번호를 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await StockAuth.login(_store.text, _password.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => StockHomeScreen(session: s)),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kAdminAccent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.inventory_2_outlined, size: 56, color: Colors.white),
                  const SizedBox(height: 12),
                  const Text('고도리 재고',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('창고를 돌며 휴대폰으로 바로 재고를 세요',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 28),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        TextField(
                          controller: _store,
                          readOnly: _busy,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                          decoration: const InputDecoration(labelText: '매장 아이디', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _password,
                          focusNode: _passwordFocus,
                          readOnly: _busy,
                          obscureText: !_show,
                          onSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: '비밀번호',
                            helperText: '직원: 패드 비밀번호 · 사장님: 관리자 웹 비밀번호',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              onPressed: () => setState(() => _show = !_show),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: _red)),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _busy ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kAdminAccent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: kAdminAccent.withValues(alpha: 0.45),
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('로그인', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

// ───────────────────────── 홈 ─────────────────────────

String _errorText(Object e) {
  if (e is FirebaseException && e.code == 'permission-denied') {
    return '재고관리 권한이 없어요. 재고관리가 꺼졌거나 비밀번호가 바뀌었을 수 있어요. 다시 로그인해 주세요.';
  }
  return '불러오지 못했어요: $e';
}

class StockHomeScreen extends StatefulWidget {
  final StockSession session;
  const StockHomeScreen({super.key, required this.session});

  @override
  State<StockHomeScreen> createState() => _StockHomeScreenState();
}

class _StockHomeScreenState extends State<StockHomeScreen> {
  final List<StreamSubscription> _subs = [];
  List<StockItem>? _items;
  List<StockCount>? _counts;
  String? _error;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    void fail(Object e) {
      if (mounted) setState(() => _error = _errorText(e));
    }

    _subs.add(StockService.watchItems(activeOnly: true).listen((v) {
      if (mounted) setState(() => _items = v);
    }, onError: fail));
    _subs.add(StockService.watchCounts(limit: 30).listen((v) {
      if (mounted) setState(() => _counts = v);
    }, onError: fail));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _logout() async {
    await StockAuth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const StockLoginScreen()), (_) => false);
  }

  void _openCount(StockCount c) {
    final prev = previousDoneCount(_counts ?? const [], c);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => c.isOpen
          ? StockCountScreen(countId: c.id, session: widget.session, previous: prev)
          : StockResultScreen(countId: c.id, previous: prev),
    ));
  }

  Future<void> _start() async {
    if (_starting) return;
    final items = _items ?? const <StockItem>[];
    final name = TextEditingController(text: await StockAuth.lastCounter());
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('재고 조사 시작', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('항목 ${items.length}개를 셀 거예요.'),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: '센 사람 이름 (선택)', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kAdminAccent, foregroundColor: Colors.white),
            child: const Text('시작'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _starting = true);
    await StockAuth.saveCounter(name.text);
    try {
      final id = await StockService.startCount(counter: name.text, owner: widget.session.owner, itemCount: items.length);
      if (!mounted) return;
      final prev = (_counts ?? const <StockCount>[]).where((c) => !c.isOpen).firstOrNull;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StockCountScreen(countId: id, session: widget.session, previous: prev),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('시작하지 못했어요: $e')));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.storeName.isEmpty ? '고도리 재고' : '${s.storeName} 재고', style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'logout') _logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('${s.store} · ${s.owner ? '사장님' : '직원'}', style: const TextStyle(color: Colors.black54)),
              ),
              const PopupMenuItem(value: 'logout', child: Text('로그아웃')),
            ],
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 44, color: _red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _logout, child: const Text('다시 로그인')),
          ]),
        ),
      );
    }
    final items = _items, counts = _counts;
    if (items == null || counts == null) return const Center(child: CircularProgressIndicator());
    final open = counts.where((c) => c.isOpen).toList();
    final done = counts.where((c) => !c.isOpen).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (items.isEmpty)
        _infoCard(Icons.info_outline, '셀 항목이 아직 없어요', '사장님이 관리자 웹 → 재고관리 → [재고 항목]에서 항목을 만들면 여기에 바로 나와요.')
      else ...[
        for (final c in open) _openCard(c, items.length),
        SizedBox(
          height: 64,
          child: ElevatedButton.icon(
            onPressed: _starting ? null : _start,
            icon: const Icon(Icons.add_circle_outline),
            label: Text(open.isEmpty ? '재고 조사 시작' : '새 조사 따로 시작', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: open.isEmpty ? kAdminAccent : Colors.white,
              foregroundColor: open.isEmpty ? Colors.white : kAdminAccent,
              disabledBackgroundColor: kAdminAccent.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),
      const Text('지난 조사', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
      const SizedBox(height: 8),
      if (done.isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: Text('아직 끝낸 조사가 없어요.', style: TextStyle(color: Colors.black45)))
      else
        for (final c in done)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                stockTime(c.finishedAt ?? c.startedAt),
                if (c.counter.isNotEmpty) c.counter,
                '${c.counts.length}개 셈',
              ].where((e) => e.isNotEmpty).join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openCount(c),
            ),
          ),
    ]);
  }

  Widget _openCard(StockCount c, int total) => Card(
        elevation: 0,
        color: const Color(0xFFFFF4E8),
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _orange)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openCount(c),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('진행 중인 조사', style: TextStyle(color: _orange, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(c.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    [
                      '${c.counts.length}/$total개 셈',
                      if (c.counter.isNotEmpty) c.counter,
                      if (c.startedAt != null) '시작 ${stockTime(c.startedAt)}',
                    ].join(' · '),
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : (c.counts.length / total).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      color: _orange,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              const Text('이어서 세기', style: TextStyle(color: kAdminAccent, fontWeight: FontWeight.bold)),
              const Icon(Icons.chevron_right, color: kAdminAccent),
            ]),
          ),
        ),
      );

  Widget _infoCard(IconData icon, String title, String message) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Icon(icon, size: 40, color: kAdminAccent),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, height: 1.5)),
          ]),
        ),
      );
}

// ───────────────────────── 숫자 세기 ─────────────────────────

class StockCountScreen extends StatefulWidget {
  final String countId;
  final StockSession session;
  final StockCount? previous; // 직전에 끝낸 조사 ('지난번 N' 표시)
  const StockCountScreen({super.key, required this.countId, required this.session, this.previous});

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  final List<StreamSubscription> _subs = [];
  List<StockItem>? _items;
  StockCount? _count;
  bool _loaded = false;
  String? _error;
  String _filter = 'all'; // all | todo | low
  String? _category; // null = 전체
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    void fail(Object e) {
      if (mounted) setState(() => _error = _errorText(e));
    }

    _subs.add(StockService.watchItems(activeOnly: true).listen((v) {
      if (mounted) setState(() => _items = v);
    }, onError: fail));
    _subs.add(StockService.watchCount(widget.countId).listen((v) {
      if (mounted) {
        setState(() {
          _count = v;
          _loaded = true;
        });
      }
    }, onError: fail));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  bool get _editable => _count != null && _count!.isOpen;

  List<StockItem> _visible() {
    final c = _count;
    return (_items ?? const <StockItem>[]).where((it) {
      if (_category != null && it.categoryLabel != _category) return false;
      final v = c?.counts[it.id];
      if (_filter == 'todo') return v == null;
      if (_filter == 'low') return stockLow(v, it.minQty);
      return true;
    }).toList();
  }

  void _save(StockItem it, num? value) {
    HapticFeedback.selectionClick();
    // 기다리지 않음 — 인터넷이 끊겨도 휴대폰에 먼저 저장되고 화면은 바로 바뀜(연결되면 올라감)
    StockService.setCount(widget.countId, it.id, value).catchError((Object e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('\'${it.name}\' 저장 실패: ${_errorText(e)}')));
      }
    });
  }

  Future<void> _openKeypad(StockItem it) async {
    if (!_editable) return;
    var current = it;
    while (mounted) {
      final r = await showModalBottomSheet<_KeypadResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _KeypadSheet(
          item: current,
          initial: _count?.counts[current.id],
          previous: widget.previous?.counts[current.id],
        ),
      );
      if (r == null) return;
      _save(current, r.value);
      if (!r.next) return;
      // 다음 안 센 항목 (지금 보이는 순서대로, 방금 저장한 항목 뒤부터)
      final list = _visible();
      final i = list.indexWhere((e) => e.id == current.id);
      StockItem? next;
      for (var j = 1; j <= list.length; j++) {
        final cand = list[(i + j) % list.length];
        if (cand.id != current.id && _count?.counts[cand.id] == null) {
          next = cand;
          break;
        }
      }
      if (next == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('다 셌어요! 아래 [조사 끝내기]를 눌러 주세요.')));
        return;
      }
      current = next;
    }
  }

  Future<void> _finish() async {
    final items = _items ?? const <StockItem>[];
    final c = _count;
    if (c == null || _finishing) return;
    final missing = items.where((it) => !c.counts.containsKey(it.id)).length;
    final note = TextEditingController(text: c.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('조사를 끝낼까요?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(missing == 0 ? '항목 ${items.length}개를 모두 셌어요.' : '아직 안 센 항목이 $missing개 있어요. 빈칸으로 끝낼까요?',
              style: TextStyle(color: missing == 0 ? Colors.black87 : _red, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('끝내면 사장님이 관리자 웹에서 결과를 확인해요. 끝낸 뒤 고칠 땐 사장님이 다시 열어 줘야 해요.',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            maxLength: 200,
            decoration: const InputDecoration(labelText: '메모 (선택)', hintText: '예: 콜라 유통기한 임박 3개', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속 세기')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kAdminAccent, foregroundColor: Colors.white),
            child: const Text('조사 끝내기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _finishing = true);
    var queued = false;
    try {
      await StockService.finish(widget.countId, items, note: note.text).timeout(const Duration(seconds: 6));
    } on TimeoutException {
      queued = true; // 인터넷이 느리거나 끊김 — 휴대폰에 저장돼 있다가 연결되면 올라감
    } catch (e) {
      if (mounted) {
        setState(() => _finishing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('끝내지 못했어요: ${_errorText(e)}')));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(queued ? '끝냈어요. 인터넷이 연결되면 사장님 화면에 올라가요.' : '조사를 끝냈어요. 수고하셨어요!'),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = _count;
    return Scaffold(
      appBar: AppBar(title: Text(c?.title ?? '재고 조사', style: const TextStyle(fontWeight: FontWeight.bold))),
      body: SafeArea(child: _body()),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget? _bottomBar() {
    final c = _count, items = _items;
    if (c == null || items == null || !_loaded) return null;
    final total = items.length;
    final counted = items.where((it) => c.counts.containsKey(it.id)).length;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
        child: Row(children: [
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('센 항목 $counted / $total', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : counted / total,
                  minHeight: 6,
                  color: counted == total ? _green : kAdminAccent,
                  backgroundColor: const Color(0xFFE6E9EE),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          if (_editable)
            ElevatedButton(
              onPressed: _finishing ? null : _finish,
              style: ElevatedButton.styleFrom(
                backgroundColor: counted == total ? _green : kAdminAccent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: kAdminAccent.withValues(alpha: 0.45),
                disabledForegroundColor: Colors.white70,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('조사 끝내기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    final items = _items, c = _count;
    if (items == null || !_loaded) return const Center(child: CircularProgressIndicator());
    if (c == null) return const Center(child: Text('이 조사는 지워졌어요.', style: TextStyle(color: Colors.black54)));
    final categories = groupStockItems(items).map((e) => e.key).toList();
    final visible = _visible();
    final lowCount = items.where((it) => stockLow(c.counts[it.id], it.minQty)).length;
    final todo = items.where((it) => !c.counts.containsKey(it.id)).length;
    final groups = groupStockItems(visible);
    return Column(children: [
      if (!c.isOpen)
        _banner(Icons.check_circle, _green, '이 조사는 끝났어요. 숫자를 고치려면 사장님이 관리자 웹에서 [다시 열기]를 눌러야 해요.'),
      if (c.pending)
        _banner(Icons.sync, _orange, '인터넷 연결을 기다리는 중 — 입력한 숫자는 휴대폰에 저장돼 있어요.'),
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 10, 12, 4), children: [
          _filterChip('전체 ${items.length}', _filter == 'all', () => setState(() => _filter = 'all')),
          _filterChip('안 센 것 $todo', _filter == 'todo', () => setState(() => _filter = 'todo')),
          _filterChip('부족 $lowCount', _filter == 'low', () => setState(() => _filter = 'low'), color: lowCount > 0 ? _red : null),
          if (categories.length > 1) ...[
            const SizedBox(width: 8),
            _filterChip('모든 위치', _category == null, () => setState(() => _category = null)),
            for (final cat in categories) _filterChip(cat, _category == cat, () => setState(() => _category = cat)),
          ],
        ]),
      ),
      Expanded(
        child: visible.isEmpty
            ? Center(
                child: Text(_filter == 'todo' ? '다 셌어요!' : _filter == 'low' ? '부족한 항목이 없어요.' : '항목이 없어요.',
                    style: const TextStyle(color: Colors.black45, fontSize: 16)))
            : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 20), children: [
                for (final g in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                    child: Text(g.key, style: const TextStyle(fontWeight: FontWeight.bold, color: kAdminAccent, fontSize: 15)),
                  ),
                  for (final it in g.value) _itemCard(it, c),
                ],
              ]),
      ),
    ]);
  }

  Widget _banner(IconData icon, Color color, String text) => Container(
        width: double.infinity,
        color: color.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _filterChip(String label, bool selected, VoidCallback onTap, {Color? color}) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: TextStyle(color: selected ? Colors.white : color, fontWeight: FontWeight.w600)),
          selected: selected,
          showCheckmark: false,
          selectedColor: kAdminAccent,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _itemCard(StockItem it, StockCount c) {
    final v = c.counts[it.id];
    final prev = widget.previous?.counts[it.id];
    final low = stockLow(v, it.minQty);
    final sub = [
      if (prev != null) '지난번 ${stockNum(prev)}',
      if (it.minQty != null) '적정 ${stockNum(it.minQty)}',
      if (it.memo.isNotEmpty) it.memo,
    ].join(' · ');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: v == null ? Colors.white : low ? const Color(0xFFFDECEC) : const Color(0xFFEFF7F2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _editable ? () => _openKeypad(it) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 13, color: low ? _red : Colors.black54)),
                ],
              ]),
            ),
            _roundButton(Icons.remove, !_editable || v == null || v <= 0 ? null : () => _save(it, v - 1 < 0 ? 0 : v - 1)),
            Container(
              constraints: const BoxConstraints(minWidth: 72),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(v == null ? '—' : stockNum(v),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: v == null ? Colors.black26 : low ? _red : Colors.black87)),
                Text(it.unit, style: const TextStyle(fontSize: 12, color: Colors.black45)),
              ]),
            ),
            _roundButton(Icons.add, !_editable ? null : () => _save(it, (v ?? 0) + 1)),
          ]),
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback? onTap) => SizedBox(
        width: 46,
        height: 46,
        child: IconButton.filledTonal(
          onPressed: onTap,
          icon: Icon(icon),
        ),
      );
}

class _KeypadResult {
  final num? value;
  final bool next;
  const _KeypadResult(this.value, this.next);
}

/// 큰 숫자 키패드 (창고에서 한 손으로 누르기 쉽게) — [저장 후 다음]이면 다음 안 센 항목으로
class _KeypadSheet extends StatefulWidget {
  final StockItem item;
  final num? initial;
  final num? previous;
  const _KeypadSheet({required this.item, this.initial, this.previous});

  @override
  State<_KeypadSheet> createState() => _KeypadSheetState();
}

class _KeypadSheetState extends State<_KeypadSheet> {
  late String _text = widget.initial == null ? '' : '${widget.initial}';
  bool _fresh = true; // 처음 누른 숫자는 원래 값을 지우고 새로 씀

  void _press(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_fresh && k != '⌫') _text = '';
      _fresh = false;
      if (k == '⌫') {
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
      } else if (k == '.') {
        if (!_text.contains('.')) _text = _text.isEmpty ? '0.' : '$_text.';
      } else {
        final cand = _text == '0' ? k : '$_text$k';
        if (parseStockInput(cand).ok) _text = cand;
      }
    });
  }

  void _done(bool next) {
    final r = parseStockInput(_text);
    if (!r.ok) return;
    Navigator.pop(context, _KeypadResult(r.value, next));
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    Widget key(String k, {Widget? child}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SizedBox(
              height: 60,
              child: OutlinedButton(
                onPressed: () => _press(k),
                style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: child ?? Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87)),
              ),
            ),
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(it.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          Text(
            [
              if (widget.previous != null) '지난번 ${stockNum(widget.previous)} ${it.unit}',
              if (it.minQty != null) '적정 ${stockNum(it.minQty)} ${it.unit}',
              if (it.memo.isNotEmpty) it.memo,
            ].join(' · '),
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(_text.isEmpty ? '—' : _text,
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: _text.isEmpty ? Colors.black26 : Colors.black87)),
              const SizedBox(width: 8),
              Text(it.unit, style: const TextStyle(fontSize: 18, color: Colors.black54)),
            ]),
          ),
          const SizedBox(height: 10),
          for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
            Row(children: [for (final k in row) key(k)]),
          Row(children: [
            key('.'),
            key('0'),
            key('⌫', child: const Icon(Icons.arrow_back, size: 26, color: Colors.black87)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(
              onPressed: () => Navigator.pop(context, const _KeypadResult(null, false)),
              child: const Text('비우기', style: TextStyle(color: _red)),
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: () => _done(false),
              style: OutlinedButton.styleFrom(minimumSize: const Size(80, 52)),
              child: const Text('저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _done(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAdminAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(140, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('저장 후 다음', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ───────────────────────── 끝난 조사 보기 ─────────────────────────

class StockResultScreen extends StatefulWidget {
  final String countId;
  final StockCount? previous;
  const StockResultScreen({super.key, required this.countId, this.previous});

  @override
  State<StockResultScreen> createState() => _StockResultScreenState();
}

class _StockResultScreenState extends State<StockResultScreen> {
  final List<StreamSubscription> _subs = [];
  List<StockItem>? _items;
  StockCount? _count;
  bool _loaded = false;
  String? _error;
  bool _lowOnly = false;

  @override
  void initState() {
    super.initState();
    void fail(Object e) {
      if (mounted) setState(() => _error = _errorText(e));
    }

    _subs.add(StockService.watchItems().listen((v) {
      if (mounted) setState(() => _items = v);
    }, onError: fail));
    _subs.add(StockService.watchCount(widget.countId).listen((v) {
      if (mounted) {
        setState(() {
          _count = v;
          _loaded = true;
        });
      }
    }, onError: fail));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _count;
    return Scaffold(
      appBar: AppBar(title: Text(c?.title ?? '조사 결과', style: const TextStyle(fontWeight: FontWeight.bold))),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    final items = _items, c = _count;
    if (items == null || !_loaded) return const Center(child: CircularProgressIndicator());
    if (c == null) return const Center(child: Text('이 조사는 지워졌어요.', style: TextStyle(color: Colors.black54)));
    final live = {for (final it in items) it.id: it};
    final ids = <String>[
      ...items.where((it) => c.items.containsKey(it.id) || c.counts.containsKey(it.id)).map((e) => e.id),
      ...c.items.keys.where((k) => !live.containsKey(k)),
    ];
    final rows = [
      for (final id in ids)
        (
          id: id,
          name: c.nameOf(id, live),
          unit: c.unitOf(id, live),
          category: (() {
            final cat = (c.items[id]?['category'] ?? live[id]?.category ?? '').toString().trim();
            return cat.isEmpty ? '기타' : cat;
          })(),
          min: c.items[id]?['minQty'] is num ? c.items[id]!['minQty'] as num : live[id]?.minQty,
        ),
    ];
    final lowCount = rows.where((r) => stockLow(c.counts[r.id], r.min)).length;
    final shown = _lowOnly ? rows.where((r) => stockLow(c.counts[r.id], r.min)).toList() : rows;
    final groups = <String, List<({String id, String name, String unit, String category, num? min})>>{};
    for (final r in shown) {
      groups.putIfAbsent(r.category, () => []).add(r);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(
        [
          if (c.counter.isNotEmpty) '센 사람 ${c.counter}',
          if (c.finishedAt != null) '끝 ${stockTime(c.finishedAt)}',
          '${c.counts.length}개 셈',
          if (widget.previous != null) '비교: ${widget.previous!.title}',
        ].join(' · '),
        style: const TextStyle(color: Colors.black54),
      ),
      if (c.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('메모: ${c.note}')),
      const SizedBox(height: 10),
      Row(children: [
        ChoiceChip(label: const Text('전체'), selected: !_lowOnly, onSelected: (_) => setState(() => _lowOnly = false)),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text('부족 $lowCount', style: TextStyle(color: lowCount > 0 && !_lowOnly ? _red : null)),
          selected: _lowOnly,
          onSelected: (_) => setState(() => _lowOnly = true),
        ),
      ]),
      if (shown.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('해당하는 항목이 없어요.', style: TextStyle(color: Colors.black45)))),
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text(g.key, style: const TextStyle(fontWeight: FontWeight.bold, color: kAdminAccent)),
        ),
        for (final r in g.value) _row(r.name, r.unit, c.counts[r.id], widget.previous?.counts[r.id], r.min),
      ],
    ]);
  }

  Widget _row(String name, String unit, num? v, num? before, num? min) {
    final low = stockLow(v, min);
    final diff = stockDiffText(v, before);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: low ? const Color(0xFFFDECEC) : Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            Text(
              [if (before != null) '직전 ${stockNum(before)}', if (min != null) '적정 ${stockNum(min)}', if (low) '부족'].join(' · '),
              style: TextStyle(fontSize: 12, color: low ? _red : Colors.black45),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(v == null ? '안 셈' : '${stockNum(v)} $unit',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: v == null ? Colors.black38 : low ? _red : Colors.black87)),
          if (diff != null)
            Text(diff,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: diff == '0' ? Colors.black45 : diff.startsWith('+') ? _green : _red,
                )),
        ]),
      ]),
    );
  }
}
