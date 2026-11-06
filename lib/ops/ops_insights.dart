import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ops_service.dart';

/// 운영자 페이지 '매장 통계' 탭 (65차) — 매장별로 손님이 많이 주문한 메뉴·많이 찾은 게임
///
/// 서버 GET /api/ops/insights (functions/src/insights.js). 데이터는 stores/{매장}/statsDaily(서버만)에 하루 단위로 쌓임:
///  - 메뉴: 손님 패드 주문이 들어올 때 셈 (lib/services/insight_service.dart countOrder) — 개수·금액·옵션·시간대
///  - 게임: 손님이 패드에서 게임 상세를 연 횟수 + 룰 영상 재생(videoStatsDaily, 48차부터 있던 기록)
/// '전체 매장'은 운영 중인 매장을 합친 것 — 매장마다 메뉴·게임 ID가 달라서 이름으로 합침 (매장 수 = 그 메뉴·게임이 나온 매장 수)
class OpsInsightsTab extends StatefulWidget {
  const OpsInsightsTab({super.key});

  @override
  State<OpsInsightsTab> createState() => _OpsInsightsTabState();
}

const _ink = Color(0xFF2B2D42);
const _orange = Color(0xFFE2711D);
const _red = Color(0xFFD64545);

num _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

String _n(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0 && s[i - 1] != '-') b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _won(num v) => '${_n(v)}원';

List<Map<String, dynamic>> _rows(Object? v) =>
    [for (final r in (v is List ? v : const [])) if (r is Map) Map<String, dynamic>.from(r)];

class _OpsInsightsTabState extends State<OpsInsightsTab> {
  List<Map<String, dynamic>> _stores = const [];
  String _storeId = 'all';
  int _days = 30;
  Future<Map<String, dynamic>>? _future;
  String? _storesError;
  bool _first = true;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    setState(() => _storesError = null);
    try {
      final list = await OpsService.stores();
      if (!mounted) return;
      setState(() {
        _stores = list;
        final active = list.where((s) => (s['status'] ?? 'active') == 'active').toList();
        // 처음엔 매장이 한 곳뿐이면 그 매장을 바로 보여 줌
        if (_first && active.length == 1) _storeId = active.first['id'] as String;
        if (_storeId != 'all' && !list.any((s) => s['id'] == _storeId)) _storeId = 'all';
        _first = false;
        _future = OpsService.insights(_storeId, _days);
      });
    } on OpsException catch (e) {
      if (mounted) setState(() => _storesError = e.message);
    } catch (e) {
      if (mounted) setState(() => _storesError = '매장 목록을 불러오지 못했어요. ($e)');
    }
  }

  void _reload() => setState(() => _future = OpsService.insights(_storeId, _days));

  // ── CSV (엑셀에 붙여 넣기) ──
  String _csv(Map<String, dynamic> d) {
    String esc(Object? v) {
      final s = '${v ?? ''}';
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final all = d['storeId'] == 'all';
    final b = StringBuffer();
    b.writeln('매장,${esc(d['name'])},기간,${esc('${d['from']} ~ 오늘 (${d['days']}일)')}');
    final s = Map<String, dynamic>.from((d['summary'] as Map?) ?? const {});
    b.writeln('주문 건수,${_num(s['orders'])},주문 금액,${_num(s['revenue'])},주문 메뉴 개수,${_num(s['items'])},'
        '게임 상세 조회,${_num(s['gameViews'])},룰 영상 재생,${_num(s['videoPlays'])}');
    b.writeln();
    b.writeln('인기 메뉴');
    b.writeln('순위,메뉴,분류,주문 개수,금액,주문 건수${all ? ',매장 수' : ''},많이 고른 옵션');
    final menus = _rows(d['menus']);
    for (var i = 0; i < menus.length; i++) {
      final m = menus[i];
      final opts = _rows(m['options']).map((o) => '${o['name']} ${_num(o['qty'])}').join(' / ');
      b.writeln([i + 1, esc(m['name']), esc(m['category']), _num(m['qty']), _num(m['revenue']), _num(m['orders']),
        if (all) _num(m['stores']), esc(opts)].join(','));
    }
    b.writeln();
    b.writeln('인기 게임');
    b.writeln('순위,게임,상세 조회,룰 영상 재생,합계${all ? ',매장 수' : ''}');
    final games = _rows(d['games']);
    for (var i = 0; i < games.length; i++) {
      final g = games[i];
      b.writeln([i + 1, esc(g['title']), _num(g['views']), _num(g['plays']), _num(g['total']), if (all) _num(g['stores'])].join(','));
    }
    b.writeln();
    b.writeln('시간대(시),주문 건수');
    final hours = (d['hours'] as List?) ?? const [];
    for (var i = 0; i < hours.length; i++) {
      b.writeln('$i,${_num(hours[i])}');
    }
    return b.toString();
  }

  Future<void> _copyCsv(Map<String, dynamic> d) async {
    await Clipboard.setData(ClipboardData(text: _csv(d)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV로 복사했어요. 엑셀·구글 시트에 붙여 넣으세요.')));
    }
  }

  // ── 화면 조각 ──
  Widget _box(String title, String? sub, List<Widget> children, {Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ?trailing,
        ]),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.5)),
        ],
        const SizedBox(height: 16),
        ...children,
      ]),
    );
  }

  Widget _tile(String label, String value, {String? note}) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF6F7F9), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink)),
        if (note != null) ...[const SizedBox(height: 4), Text(note, style: const TextStyle(color: Colors.black45, fontSize: 12))],
      ]),
    );
  }

  Widget _rank(int i) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: i < 3 ? _orange.withValues(alpha: 0.15) : const Color(0xFFF0F1F3),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text('${i + 1}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: i < 3 ? _orange : Colors.black54)),
      );

  Widget _menuTable(Map<String, dynamic> d) {
    final all = d['storeId'] == 'all';
    final menus = _rows(d['menus']);
    if (menus.isEmpty) return const Text('아직 주문 기록이 없어요.', style: TextStyle(color: Colors.black54));
    final totalItems = _num(((d['summary'] as Map?) ?? const {})['items']);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 22,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 58,
        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: _ink),
        columns: [
          const DataColumn(label: Text('순위')),
          const DataColumn(label: Text('메뉴')),
          const DataColumn(label: Text('개수'), numeric: true),
          const DataColumn(label: Text('비중'), numeric: true),
          const DataColumn(label: Text('금액'), numeric: true),
          if (all) const DataColumn(label: Text('매장 수'), numeric: true),
          const DataColumn(label: Text('많이 고른 옵션')),
        ],
        rows: [
          for (var i = 0; i < menus.length; i++)
            () {
              final m = menus[i];
              final qty = _num(m['qty']);
              final opts = _rows(m['options']).map((o) => '${o['name']} ${_n(_num(o['qty']))}').join(' · ');
              final cat = (m['category'] ?? '').toString();
              return DataRow(cells: [
                DataCell(_rank(i)),
                DataCell(Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (cat.isNotEmpty) Text(cat, style: const TextStyle(fontSize: 12, color: Colors.black45)),
                  ],
                )),
                DataCell(Text(_n(qty))),
                DataCell(Text(totalItems > 0 ? '${(qty / totalItems * 100).toStringAsFixed(1)}%' : '-')),
                DataCell(Text(_won(_num(m['revenue'])))),
                if (all) DataCell(Text(_n(_num(m['stores'])))),
                DataCell(Text(opts.isEmpty ? '-' : opts, style: const TextStyle(fontSize: 12, color: Colors.black54))),
              ]);
            }(),
        ],
      ),
    );
  }

  Widget _gameTable(Map<String, dynamic> d) {
    final all = d['storeId'] == 'all';
    final games = _rows(d['games']);
    if (games.isEmpty) return const Text('아직 게임 조회 기록이 없어요.', style: TextStyle(color: Colors.black54));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 22,
        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: _ink),
        columns: [
          const DataColumn(label: Text('순위')),
          const DataColumn(label: Text('게임')),
          const DataColumn(label: Text('상세 조회'), numeric: true),
          const DataColumn(label: Text('룰 영상'), numeric: true),
          const DataColumn(label: Text('합계'), numeric: true),
          if (all) const DataColumn(label: Text('매장 수'), numeric: true),
        ],
        rows: [
          for (var i = 0; i < games.length; i++)
            DataRow(cells: [
              DataCell(_rank(i)),
              DataCell(Text('${games[i]['title']}', style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text(_n(_num(games[i]['views'])))),
              DataCell(Text(_n(_num(games[i]['plays'])))),
              DataCell(Text(_n(_num(games[i]['total'])), style: const TextStyle(fontWeight: FontWeight.bold))),
              if (all) DataCell(Text(_n(_num(games[i]['stores'])))),
            ]),
        ],
      ),
    );
  }

  Widget _content(Map<String, dynamic> d) {
    final s = Map<String, dynamic>.from((d['summary'] as Map?) ?? const {});
    final orders = _num(s['orders']), revenue = _num(s['revenue']), items = _num(s['items']);
    final views = _num(s['gameViews']), plays = _num(s['videoPlays']), activeDays = _num(s['activeDays']);
    final hours = [for (final h in (d['hours'] as List?) ?? const []) _num(h)];
    final all = d['storeId'] == 'all';
    final empty = orders == 0 && views == 0 && plays == 0;

    final menuBox = _box(
      '인기 메뉴',
      '손님 패드 주문 기준 (카운터에서 받은 주문·할인·취소는 빠짐). 비중 = 전체 주문 개수 중 이 메뉴'
          '${all ? ' · 전체 매장은 메뉴 이름으로 합침' : ''}',
      [_menuTable(d)],
    );
    final gameBox = _box(
      '많이 찾는 게임',
      '상세 조회 = 손님이 패드에서 게임을 눌러 상세를 연 횟수(같은 패드에서 30초 안에 다시 연 건 1번) · '
          '룰 영상 = 패드에서 룰 영상을 튼 횟수${all ? ' · 전체 매장은 게임 이름으로 합침' : ''}',
      [_gameTable(d)],
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (empty)
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: const Text(
            '이 기간에는 아직 쌓인 통계가 없어요. 메뉴 통계는 서버 배포(배포.bat 4번) 뒤 새 패드 앱으로 들어온 주문부터, '
            '게임 상세 조회도 그때부터 쌓여요. 룰 영상 재생은 예전 기록도 보여요.',
            style: TextStyle(height: 1.5),
          ),
        ),
      _box(
        '요약',
        '${d['from']} ~ 오늘 (한국 날짜)${all ? ' · 운영 중인 매장 ${_n(_num(d['storeCount']))}곳 합계' : ''}',
        [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _tile('패드 주문', '${_n(orders)}건', note: activeDays > 0 ? '기록 있는 날 ${_n(activeDays)}일' : null),
            _tile('주문 금액', _won(revenue), note: orders > 0 ? '주문당 평균 ${_won(revenue / orders)}' : null),
            _tile('주문한 메뉴', '${_n(items)}개', note: orders > 0 ? '주문당 ${(items / orders).toStringAsFixed(1)}개' : null),
            _tile('게임 상세 조회', _n(views)),
            _tile('룰 영상 재생', _n(plays)),
          ]),
        ],
      ),
      _box('시간대별 주문', '패드 주문이 들어온 시각(한국 시간). 가장 많은 시간대는 주황색', [_HourBars(hours: hours)]),
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 1100) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [menuBox, gameBox]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 6, child: menuBox),
          const SizedBox(width: 20),
          Expanded(flex: 5, child: gameBox),
        ]);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final storeItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'all', child: Text('전체 매장 (운영 중)')),
      for (final s in _stores)
        DropdownMenuItem(
          value: s['id'] as String,
          child: Text('${(s['name'] ?? '').toString().isEmpty ? '(이름 없음)' : s['name']} · ${s['id']}'
              '${(s['status'] ?? 'active') == 'active' ? '' : ' (운영 중 아님)'}'),
        ),
    ];
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final data = snap.connectionState == ConnectionState.done && !snap.hasError ? snap.data : null;
        final header = Row(children: [
          const Text('매장 통계', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(width: 20),
          Flexible(
            child: DropdownButton<String>(
              value: storeItems.any((i) => i.value == _storeId) ? _storeId : 'all',
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: storeItems,
              onChanged: (v) {
                if (v == null) return;
                _storeId = v;
                _reload();
              },
            ),
          ),
          const SizedBox(width: 16),
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
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: data == null ? null : () => _copyCsv(data),
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('CSV 복사'),
          ),
          IconButton(onPressed: _loadStores, tooltip: '새로고침', icon: const Icon(Icons.refresh)),
        ]);

        Widget body;
        if (_storesError != null) {
          body = _Retry(message: _storesError!, onRetry: _loadStores);
        } else if (_future == null || snap.connectionState != ConnectionState.done) {
          body = const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator()));
        } else if (snap.hasError) {
          body = _Retry(message: '${snap.error}', onRetry: _reload);
        } else {
          body = _content(snap.data!);
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [header, const SizedBox(height: 20), body],
        );
      },
    );
  }
}

class _HourBars extends StatelessWidget {
  final List<num> hours;
  const _HourBars({required this.hours});

  @override
  Widget build(BuildContext context) {
    final h = List<num>.generate(24, (i) => i < hours.length ? hours[i] : 0);
    final max = h.fold<num>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 24; i++)
            Expanded(
              child: Tooltip(
                message: '$i시 ${_n(h[i])}건',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (h[i] > 0) Text(_n(h[i]), style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Container(
                      height: max > 0 ? (100 * h[i] / max).toDouble() : 0,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: max > 0 && h[i] == max ? _orange : _ink.withValues(alpha: 0.7),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('$i', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Retry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _red)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ]),
      ),
    );
  }
}
