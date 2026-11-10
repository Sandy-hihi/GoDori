import 'package:flutter/material.dart';

import 'ops_insights.dart';
import 'ops_service.dart';
import 'ops_toss.dart';
import 'ops_videos.dart';

/// 운영자 페이지 (48차, 49차부터 따로 사이트) — https://godori-ops.web.app (lib/main_ops.dart)
/// 가입된 매장 관리(가입 승인·거절·정지·다시 열기·삭제, 59차 기능 켜기·끄기 — 토스 POS 연동·패드 대시보드)와 서버 이용 통계(비용 관리).
/// 65차: '매장 통계' 탭 — 매장별 인기 메뉴·많이 찾는 게임·시간대별 주문 (lib/ops/ops_insights.dart)
/// 운영자 비밀번호는 Firestore _ops/account (처음엔 콘솔에서 password 필드로 만들고, 여기 '설정'에서 바꾸기)
class OpsApp extends StatelessWidget {
  const OpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '고도리 운영자',
      theme: ThemeData(
        fontFamily: 'Pretendard',
        colorScheme: ColorScheme.fromSeed(seedColor: _ink),
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
      ),
      home: const _OpsGate(),
    );
  }
}

const _ink = Color(0xFF2B2D42);
const _green = Color(0xFF00B37E);
const _orange = Color(0xFFE2711D);
const _red = Color(0xFFD64545);

/// 요금 기준 (USD, 2026-11 확인). 실제 청구서와 다를 수 있는 추정치 — 정확한 금액은 각 콘솔의 결제 화면
class OpsPricing {
  // Firestore 표준 (cloud.google.com/firestore/pricing, 기본 단가 — 서울 별도 단가는 페이지에 따로 없음)
  static const firestoreReadPer100k = 0.03, firestoreWritePer100k = 0.09, firestoreDeletePer100k = 0.01;
  static const firestoreFreeReadsPerDay = 50000, firestoreFreeWritesPerDay = 20000, firestoreFreeDeletesPerDay = 20000;
  // 서버 함수(2세대 = Cloud Run) 요청 — 한 달 200만 번 무료, 100만 번당 $0.40 (CPU·메모리 시간은 빠짐)
  static const runFreeRequestsPerMonth = 2000000, runPerMillion = 0.40;
  // Firebase Storage 내보내기 — 대략 $0.12/GB로 계산(무료 사용량은 빼지 않은 최대치)
  static const storageEgressPerGb = 0.12;
  // Cloudflare R2 (developers.cloudflare.com/r2/pricing): 저장 $0.015/GB-월, 10GB 무료, 내보내기 무료,
  // 읽기(Class B) 한 달 1천만 번 무료 — 영상 재생 1번 = 조각 요청 여러 번이라 정확히는 Cloudflare 대시보드에서
  static const r2PerGbMonth = 0.015, r2FreeGb = 10.0;
}

String _n(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0 && s[i - 1] != '-') b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _gb(num bytes) {
  final gb = bytes / (1024 * 1024 * 1024);
  if (gb >= 10) return '${gb.toStringAsFixed(1)} GB';
  if (gb >= 0.01) return '${gb.toStringAsFixed(2)} GB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _usd(double v) => v < 0.005 ? '\$0' : '\$${v.toStringAsFixed(v < 10 ? 2 : 1)}';

String _date(Object? iso) {
  final t = DateTime.tryParse(iso?.toString() ?? '');
  if (t == null) return '-';
  final l = t.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

num _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

class _OpsGate extends StatefulWidget {
  const _OpsGate();

  @override
  State<_OpsGate> createState() => _OpsGateState();
}

class _OpsGateState extends State<_OpsGate> {
  bool? _loggedIn;
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    OpsService.restore().then((ok) {
      if (mounted) setState(() => _loggedIn = ok);
    });
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy || _pw.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await OpsService.login(_pw.text.trim());
      _pw.clear();
      if (mounted) setState(() => _loggedIn = true);
    } on OpsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '로그인하지 못했어요. ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_loggedIn == true) {
      return _OpsHome(onLogout: () async {
        await OpsService.logout();
        if (mounted) setState(() => _loggedIn = false);
      });
    }
    return Scaffold(
      backgroundColor: _ink,
      body: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 56, color: _ink),
              const SizedBox(height: 12),
              const Text('고도리 운영자', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('매장 승인·관리와 서버 이용 통계', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 24),
              TextField(
                controller: _pw,
                autofocus: true,
                obscureText: true,
                enabled: !_busy,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: '운영자 비밀번호',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  errorText: _error,
                  errorMaxLines: 4,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _login,
                  style: FilledButton.styleFrom(backgroundColor: _ink),
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('로그인', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpsHome extends StatelessWidget {
  final VoidCallback onLogout;
  const _OpsHome({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
          title: const Text('고도리 운영자', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            TextButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout, color: Colors.white70),
              label: const Text('로그아웃', style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: _orange,
            tabs: [Tab(text: '매장'), Tab(text: '매장 통계'), Tab(text: '이용 통계'), Tab(text: '공용 룰 영상'), Tab(text: '설정')],
          ),
        ),
        body: const TabBarView(children: [_StoresTab(), OpsInsightsTab(), _UsageTab(), OpsSharedVideosTab(), _SettingsTab()]),
      ),
    );
  }
}

// ───────────────────────── 매장 ─────────────────────────

class _StoresTab extends StatefulWidget {
  const _StoresTab();

  @override
  State<_StoresTab> createState() => _StoresTabState();
}

class _StoresTabState extends State<_StoresTab> {
  late Future<List<Map<String, dynamic>>> _future = OpsService.stores();
  final Set<String> _busy = {};
  Map<String, dynamic>? _toss; // 64차: 토스 POS 연결 현황 (/api/ops/toss/overview)

  @override
  void initState() {
    super.initState();
    _loadToss();
  }

  Future<void> _loadToss() async {
    try {
      final t = await OpsService.tossOverview();
      if (mounted) setState(() => _toss = t);
    } catch (_) {
      // 서버가 아직 64차 전이면 토스 줄만 안 보임
    }
  }

  void _reload() {
    setState(() => _future = OpsService.stores());
    _loadToss();
  }

  Future<void> _act(Map<String, dynamic> s, String action) async {
    final id = s['id'] as String;
    const titles = {
      'active': '승인(운영 시작)할까요?',
      'suspended': '이용을 정지할까요?',
      'rejected': '가입을 거절할까요?',
      'delete': '가입 신청을 지울까요?',
    };
    const bodies = {
      'active': '사장님이 관리자 웹에 로그인할 수 있게 돼요. 승인했다고 연락해 주세요.',
      'suspended': '그 매장의 패드·관리자 웹이 바로 막히고, 로그인한 기기도 1시간 안에 로그아웃돼요. 데이터는 그대로 남아요.',
      'rejected': '사장님이 로그인하면 "승인되지 않았어요"가 나와요. 아이디는 계속 차지해요(지우면 다시 쓸 수 있음).',
      'delete': '매장 정보와 가입 정보가 지워지고 아이디를 다시 쓸 수 있게 돼요.',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$id — ${titles[action]}'),
        content: Text(bodies[action]!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: action == 'active' ? _green : _red),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(id));
    try {
      if (action == 'delete') {
        await OpsService.deleteSignup(id);
      } else {
        await OpsService.setStatus(id, action);
      }
      if (mounted) _toast(context, '$id: 처리했어요.');
      _reload();
    } on OpsException catch (e) {
      if (mounted) _toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  // 59차: 매장 기능 켜기·끄기 (토스 POS 연동은 여기서만, 패드 대시보드는 사장님도 관리자 웹에서 바꿈)
  Future<void> _setFeature(Map<String, dynamic> s, String key, bool on) async {
    final id = s['id'] as String;
    if (key == 'tossPos') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$id — 토스 POS 연동을 ${on ? '켤' : '끌'}까요?'),
          content: Text(on
              ? '이 매장에 토스 POS 연동 기능이 열려요. (토스 쪽 연동 승인·매장 연결이 끝난 뒤에 켜 주세요)'
              : '이 매장의 패드 주문이 더 이상 토스 POS로 가지 않아요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('확인')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy.add(id));
    try {
      final f = await OpsService.setFeatures(id, {key: on});
      s['features'] = f;
      if (mounted) _toast(context, '$id: ${key == 'tossPos' ? '토스 POS 연동' : '패드 관리자 대시보드'} ${on ? '켬' : '끔'}');
    } on OpsException catch (e) {
      if (mounted) _toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Widget _featureSwitch(Map<String, dynamic> s, String key, String label, bool fallback, bool busy) {
    final f = s['features'] is Map ? s['features'] as Map : const {};
    final on = f[key] is bool ? f[key] as bool : fallback;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 32,
        child: FittedBox(
          child: Switch(value: on, activeTrackColor: _green, onChanged: busy ? null : (v) => _setFeature(s, key, v)),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 13, color: on ? Colors.black87 : Colors.black45, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _statusChip(String status) {
    const labels = {'pending': '승인 대기', 'active': '운영 중', 'suspended': '정지됨', 'rejected': '거절됨'};
    const colors = {'pending': _orange, 'active': _green, 'suspended': _red, 'rejected': Colors.black45};
    final c = colors[status] ?? Colors.black45;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(labels[status] ?? status, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _card(Map<String, dynamic> s) {
    final id = s['id'] as String;
    final status = s['status'] as String? ?? 'active';
    final busy = _busy.contains(id);
    final buttons = <Widget>[
      if (status == 'pending' || status == 'rejected' || status == 'suspended')
        FilledButton(
          onPressed: busy ? null : () => _act(s, 'active'),
          style: FilledButton.styleFrom(backgroundColor: _green),
          child: Text(status == 'suspended' ? '다시 열기' : '승인'),
        ),
      if (status == 'pending')
        OutlinedButton(onPressed: busy ? null : () => _act(s, 'rejected'), child: const Text('거절')),
      if (status == 'active')
        OutlinedButton(
          onPressed: busy ? null : () => _act(s, 'suspended'),
          style: OutlinedButton.styleFrom(foregroundColor: _red),
          child: const Text('정지'),
        ),
      if (status == 'pending' || status == 'rejected')
        TextButton(
          onPressed: busy ? null : () => _act(s, 'delete'),
          style: TextButton.styleFrom(foregroundColor: _red),
          child: const Text('삭제'),
        ),
    ];
    final owner = [s['ownerName'], s['phone']].where((v) => (v ?? '').toString().isNotEmpty).join(' · ');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text('${(s['name'] ?? '').toString().isEmpty ? '(이름 없음)' : s['name']}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 10),
                    _statusChip(status),
                  ]),
                  const SizedBox(height: 6),
                  SelectableText('아이디 $id${owner.isEmpty ? '' : '   ·   $owner'}', style: const TextStyle(color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text(
                    '가입 ${_date(s['signedUpAt'] ?? s['createdAt'])}'
                    '${s['statusChangedAt'] != null ? '  ·  상태 변경 ${_date(s['statusChangedAt'])}' : ''}'
                    '${s['migratedFromLegacy'] == true ? '  ·  예전 데이터에서 옮김' : ''}'
                    '  ·  룰 영상 ${_n(_num(s['r2Files']))}개 ${_gb(_num(s['r2Bytes']))}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 20, runSpacing: 4, children: [
                    _featureSwitch(s, 'tossPos', '토스 POS 연동', false, busy),
                    _featureSwitch(s, 'adminDashboard', '패드 관리자 대시보드(방 0)', true, busy),
                  ]),
                  if ((s['features'] as Map?)?['tossPos'] == true)
                    OpsTossRow(storeId: id, overview: _toss, onChanged: _loadToss),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (busy)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Wrap(spacing: 8, children: buttons),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return _ErrorBox(message: '${snap.error}', onRetry: _reload);
        final list = snap.data ?? const [];
        final count = <String, int>{};
        for (final s in list) {
          count[s['status'] as String? ?? 'active'] = (count[s['status'] as String? ?? 'active'] ?? 0) + 1;
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Text('매장 ${list.length}곳', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                Text('승인 대기 ${count['pending'] ?? 0} · 운영 중 ${count['active'] ?? 0} · 정지 ${count['suspended'] ?? 0} · 거절 ${count['rejected'] ?? 0}',
                    style: const TextStyle(color: Colors.black54)),
                const Spacer(),
                IconButton(onPressed: _reload, tooltip: '새로고침', icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 16),
            if (list.isEmpty) const Text('아직 가입한 매장이 없어요.'),
            for (final s in list) _card(s),
          ],
        );
      },
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _red)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
      ]),
    );
  }
}

// ───────────────────────── 이용 통계 ─────────────────────────

class _UsageTab extends StatefulWidget {
  const _UsageTab();

  @override
  State<_UsageTab> createState() => _UsageTabState();
}

class _UsageTabState extends State<_UsageTab> {
  int _days = 30;
  late Future<(Map<String, dynamic>, Map<String, dynamic>)> _future = _load();
  String? _recounting;

  Future<(Map<String, dynamic>, Map<String, dynamic>)> _load() async {
    final results = await Future.wait([OpsService.usage(_days), OpsService.projectUsage(_days)]);
    return (results[0], results[1]);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _recount(String id) async {
    setState(() => _recounting = id);
    try {
      final r = await OpsService.recountR2(id);
      if (mounted) _toast(context, '$id: 룰 영상 ${_n(_num(r['r2Files']))}개, ${_gb(_num(r['r2Bytes']))} (게임 ${_n(_num(r['games']))}개 읽음)');
      _reload();
    } on OpsException catch (e) {
      if (mounted) _toast(context, e.message);
    } finally {
      if (mounted) setState(() => _recounting = null);
    }
  }

  Widget _section(String title, String? sub, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (sub != null) ...[const SizedBox(height: 4), Text(sub, style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.5))],
        const SizedBox(height: 16),
        ...children,
      ]),
    );
  }

  Widget _tile(String label, String value, {String? note, Color? color}) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF6F7F9), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color ?? _ink)),
        if (note != null) ...[const SizedBox(height: 4), Text(note, style: const TextStyle(color: Colors.black45, fontSize: 12))],
      ]),
    );
  }

  /// 하루 무료 사용량을 빼고 날마다 계산해 더함
  double _dailyCost(List days, String key, int freePerDay, double per100k) {
    var cost = 0.0;
    for (final d in days) {
      final over = _num((d as Map)[key]) - freePerDay;
      if (over > 0) cost += over / 100000 * per100k;
    }
    return cost;
  }

  List<Widget> _project(Map<String, dynamic> p) {
    final totals = Map<String, dynamic>.from(p['totals'] as Map? ?? {});
    final errors = Map<String, dynamic>.from(p['errors'] as Map? ?? {});
    final days = (p['days'] as List?) ?? const [];
    final reads = _num(totals['firestoreReads']), writes = _num(totals['firestoreWrites']), deletes = _num(totals['firestoreDeletes']);
    final fsCost = _dailyCost(days, 'firestoreReads', OpsPricing.firestoreFreeReadsPerDay, OpsPricing.firestoreReadPer100k) +
        _dailyCost(days, 'firestoreWrites', OpsPricing.firestoreFreeWritesPerDay, OpsPricing.firestoreWritePer100k) +
        _dailyCost(days, 'firestoreDeletes', OpsPricing.firestoreFreeDeletesPerDay, OpsPricing.firestoreDeletePer100k);
    final req = _num(totals['functionRequests']);
    final freeReq = OpsPricing.runFreeRequestsPerMonth * _days / 30;
    final runCost = req > freeReq ? (req - freeReq) / 1e6 * OpsPricing.runPerMillion : 0.0;
    final sent = _num(totals['storageSentBytes']);
    final stCost = sent / (1024 * 1024 * 1024) * OpsPricing.storageEgressPerGb;
    return [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _tile('Firestore 읽기', _n(reads), note: '하루 평균 ${_n(days.isEmpty ? 0 : reads / days.length)} (무료 5만/일)'),
        _tile('Firestore 쓰기 · 삭제', '${_n(writes)} · ${_n(deletes)}', note: '무료 2만/일씩'),
        _tile('Firestore 예상 비용', _usd(fsCost), color: fsCost > 1 ? _red : _green, note: '무료 사용량 빼고 날마다 계산'),
        _tile('서버 함수 요청', _n(req), note: '예상 ${_usd(runCost.toDouble())} (CPU 시간 빠짐)'),
        _tile('Firebase Storage 전송', _gb(sent), note: '최대 ${_usd(stCost.toDouble())} (사진·예전 영상)'),
      ]),
      if (errors.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final e in errors.entries)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText('⚠ ${e.key}: ${e.value}', style: const TextStyle(color: _red, fontSize: 13)),
          ),
      ],
    ];
  }

  Widget _storeTable(List stores) {
    final rows = [for (final s in stores) Map<String, dynamic>.from(s as Map)];
    final appReadsAll = rows.fold<num>(0, (a, s) => a + _num((s['totals'] as Map? ?? {})['clientReads']));
    rows.sort((a, b) => _num((b['totals'] as Map? ?? {})['clientReads']).compareTo(_num((a['totals'] as Map? ?? {})['clientReads'])));
    DataCell c(String v) => DataCell(Text(v));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: _ink),
        columns: const [
          DataColumn(label: Text('매장')),
          DataColumn(label: Text('로그인'), numeric: true),
          DataColumn(label: Text('앱 읽기(추정)'), numeric: true),
          DataColumn(label: Text('읽기 비중'), numeric: true),
          DataColumn(label: Text('영상 재생'), numeric: true),
          DataColumn(label: Text('영상 전송(추정)'), numeric: true),
          DataColumn(label: Text('영상 올림'), numeric: true),
          DataColumn(label: Text('R2 저장'), numeric: true),
          DataColumn(label: Text('BGG'), numeric: true),
          DataColumn(label: Text('AI'), numeric: true),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final s in rows)
            () {
              final t = Map<String, dynamic>.from(s['totals'] as Map? ?? {});
              final reads = _num(t['clientReads']);
              final share = appReadsAll > 0 ? reads / appReadsAll * 100 : 0;
              final id = s['id'] as String;
              return DataRow(cells: [
                DataCell(Text('${s['name']}\n$id', style: const TextStyle(fontSize: 13))),
                c(_n(_num(t['logins']))),
                c(_n(reads)),
                c(appReadsAll > 0 ? '${share.toStringAsFixed(0)}%' : '-'),
                c(_n(_num(t['videoPlays']))),
                c(_gb(_num(t['videoBytesEst']))),
                c('${_n(_num(t['videoUploads']))}개'),
                c('${_gb(_num(s['r2Bytes']))} (${_n(_num(s['r2Files']))})'),
                c(_n(_num(t['bggCalls']))),
                c(_n(_num(t['aiCalls']))),
                DataCell(_recounting == id
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(onPressed: () => _recount(id), child: const Text('R2 다시 세기'))),
              ]);
            }(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Map<String, dynamic>, Map<String, dynamic>)>(
      future: _future,
      builder: (context, snap) {
        final header = Row(children: [
          const Text('이용 통계', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(width: 20),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7일')),
              ButtonSegment(value: 30, label: Text('30일')),
              ButtonSegment(value: 90, label: Text('90일')),
            ],
            selected: {_days},
            onSelectionChanged: (v) {
              _days = v.first;
              _reload();
            },
          ),
          const Spacer(),
          IconButton(onPressed: _reload, tooltip: '새로고침', icon: const Icon(Icons.refresh)),
        ]);
        if (snap.connectionState != ConnectionState.done) {
          return ListView(padding: const EdgeInsets.all(24), children: [header, const SizedBox(height: 60), const Center(child: CircularProgressIndicator())]);
        }
        if (snap.hasError) {
          return ListView(padding: const EdgeInsets.all(24), children: [header, const SizedBox(height: 40), _ErrorBox(message: '${snap.error}', onRetry: _reload)]);
        }
        final (usage, project) = snap.data!;
        final stores = (usage['stores'] as List?) ?? const [];
        final r2Bytes = stores.fold<num>(0, (a, s) => a + _num((s as Map)['r2Bytes']));
        final r2Gb = r2Bytes / (1024 * 1024 * 1024);
        final r2Cost = r2Gb > OpsPricing.r2FreeGb ? (r2Gb - OpsPricing.r2FreeGb) * OpsPricing.r2PerGbMonth : 0.0;
        final plays = stores.fold<num>(0, (a, s) => a + _num(((s as Map)['totals'] as Map? ?? {})['videoPlays']));
        final bgg = stores.fold<num>(0, (a, s) => a + _num(((s as Map)['totals'] as Map? ?? {})['bggCalls']));
        final ai = stores.fold<num>(0, (a, s) => a + _num(((s as Map)['totals'] as Map? ?? {})['aiCalls']));
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            header,
            const SizedBox(height: 20),
            _section(
              'Firebase 전체 (Google Cloud 집계)',
              '프로젝트 전체 실제 사용량이에요(매장별로는 안 나뉨, UTC 하루 기준, 몇 분 늦게 반영). 비용은 위 기준으로 계산한 추정치예요. '
                  '정확한 청구 금액은 Google Cloud 콘솔 → 결제에서 확인하세요.',
              _project(project),
            ),
            _section(
              '룰 영상 서버 (Cloudflare R2) · BGG · AI',
              'R2는 내보내기(재생 전송)가 무료라 저장 용량이 비용의 대부분이에요. 재생 요청 수(Class B)는 한 달 1천만 번까지 무료 — 정확한 값은 Cloudflare 대시보드 → R2 → Metrics.',
              [
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _tile('R2 저장 용량 (전체)', _gb(r2Bytes), note: '한 달 예상 ${_usd(r2Cost.toDouble())} (10GB 무료)', color: r2Cost > 0 ? _orange : _green),
                  _tile('영상 재생', _n(plays), note: '이 기간 전체 매장'),
                  _tile('BGG 조회', _n(bgg), note: '무료(Apps Script 중계) — 너무 잦으면 BGG가 막을 수 있음'),
                  _tile('AI 요청', _n(ai), note: '지금은 AI 추천을 꺼 둠 (켜면 Claude API 사용료)'),
                ]),
              ],
            ),
            _section(
              '매장별 (${usage['from'] ?? ''} ~ 오늘, 한국 날짜)',
              '앱 읽기 = 패드·관리자 웹이 게임 목록·메뉴·주문 화면에서 직접 센 Firestore 읽기(추정, 기기 캐시는 뺌). '
                  '읽기 비중으로 Firestore 비용을 매장별로 나눠 볼 수 있어요. 영상 전송은 재생할 때 처음 연 화질 파일 크기로 추정. '
                  'R2 저장 용량이 0인데 영상이 있으면(48차 전에 올린 영상) "R2 다시 세기"를 누르세요(게임 문서를 전부 한 번 읽음).',
              [_storeTable(stores)],
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────── 설정 ─────────────────────────

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = _pw.text.trim();
    if (a.length < 10) {
      _toast(context, '10자 이상으로 정해 주세요.');
      return;
    }
    if (a != _pw2.text.trim()) {
      _toast(context, '비밀번호 확인이 달라요.');
      return;
    }
    setState(() => _busy = true);
    try {
      await OpsService.changePassword(a);
      _pw.clear();
      _pw2.clear();
      if (mounted) _toast(context, '운영자 비밀번호를 바꿨어요.');
    } on OpsException catch (e) {
      if (mounted) _toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('운영자 비밀번호 바꾸기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('처음에 콘솔에서 글자로 넣은 비밀번호를 여기서 바꾸면 암호화된 값으로 저장돼요.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            TextField(controller: _pw, obscureText: true, enabled: !_busy, decoration: const InputDecoration(labelText: '새 비밀번호 (10자 이상)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _pw2, obscureText: true, enabled: !_busy, decoration: const InputDecoration(labelText: '한 번 더', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, style: FilledButton.styleFrom(backgroundColor: _ink), child: const Text('바꾸기')),
          ]),
        ),
      ],
    );
  }
}
