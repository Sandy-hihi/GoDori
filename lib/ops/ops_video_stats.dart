import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ops_service.dart';

/// 운영자 페이지 '룰 영상 통계' 탭 (112차) — 매장별·전체 매장 룰 영상 재생 횟수
///
/// 서버 GET /api/ops/video-stats (functions/src/insights.js videoStatsOf·mergeVideoStats).
/// 기록은 서버(/api/video/play-url)가 손님 패드에서 영상을 틀 때마다 stores/{매장}/videoStats(누적)·videoStatsDaily(하루)에 씀.
/// 112차에 관리자 웹(사장님)에서 빼고 여기로 옮김 — 보안 규칙상 두 기록은 이제 서버만 읽음.
/// '전체 매장'은 운영 중인 매장을 합친 것 — 매장마다 게임 ID가 달라서 게임 이름으로 합침(매장 수 = 그 게임을 본 매장 수).
class OpsVideoStatsTab extends StatefulWidget {
  const OpsVideoStatsTab({super.key});

  @override
  State<OpsVideoStatsTab> createState() => _OpsVideoStatsTabState();
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

List<Map<String, dynamic>> _rows(Object? v) =>
    [for (final r in (v is List ? v : const [])) if (r is Map) Map<String, dynamic>.from(r)];

String _md(String key) {
  final p = key.split('-');
  return p.length == 3 ? '${int.tryParse(p[1]) ?? p[1]}/${int.tryParse(p[2]) ?? p[2]}' : key;
}

String _last(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  final now = DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) return '오늘 $hm';
  return '${t.year == now.year ? '' : '${t.year}/'}${t.month}/${t.day} $hm';
}

class _OpsVideoStatsTabState extends State<OpsVideoStatsTab> {
  static const _periods = <(String, int)>[('오늘', 1), ('7일', 7), ('30일', 30), ('90일', 90), ('전체', 0)];

  List<Map<String, dynamic>> _stores = const [];
  String _storeId = 'all';
  int _days = 7;
  Future<Map<String, dynamic>>? _future;
  String? _storesError;
  bool _first = true;
  bool _showAll = false;
  bool _showUnwatched = false;

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
        if (_first && active.length == 1) _storeId = active.first['id'] as String;
        if (_storeId != 'all' && !list.any((s) => s['id'] == _storeId)) _storeId = 'all';
        _first = false;
        _future = OpsService.videoStats(_storeId, _days);
      });
    } on OpsException catch (e) {
      if (mounted) setState(() => _storesError = e.message);
    } catch (e) {
      if (mounted) setState(() => _storesError = '매장 목록을 불러오지 못했어요. ($e)');
    }
  }

  void _reload() => setState(() {
        _showAll = false;
        _showUnwatched = false;
        _future = OpsService.videoStats(_storeId, _days);
      });

  String _periodName(int days) => _periods.firstWhere((p) => p.$2 == days, orElse: () => ('$days일', days)).$1;

  // ── CSV (엑셀에 붙여 넣기) ──
  Future<void> _copyCsv(Map<String, dynamic> d) async {
    String esc(Object? v) {
      final s = '${v ?? ''}';
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final all = d['storeId'] == 'all';
    final b = StringBuffer();
    b.writeln('매장,${esc(d['name'])},기간,${esc(_num(d['days']) == 0 ? '전체(누적)' : '${d['from']} ~ 오늘 (${d['days']}일)')}');
    b.writeln('재생,${_num(d['total'])},재생된 게임,${_num(d['gamesPlayed'])},매장 영상 있는 게임,${_num(d['videoGames'])}');
    if (all) {
      b.writeln();
      b.writeln('매장,재생,재생된 게임,매장 영상 있는 게임');
      for (final s in _rows(d['perStore'])) {
        b.writeln([esc(s['name']), _num(s['total']), _num(s['gamesPlayed']), _num(s['videoGames'])].join(','));
      }
    }
    final daily = _rows(d['daily']);
    if (daily.isNotEmpty) {
      b.writeln();
      b.writeln('날짜,재생');
      for (final r in daily) {
        b.writeln('${r['date']},${_num(r['plays'])}');
      }
    }
    b.writeln();
    b.writeln('순위,게임,재생,누적${all ? ',매장 수' : ''},마지막 재생');
    final games = _rows(d['games']);
    for (var i = 0; i < games.length; i++) {
      final g = games[i];
      b.writeln([i + 1, esc(g['title']), _num(g['plays']), _num(g['allTime']), if (all) _num(g['stores']), esc(_last(g['lastPlayedAt']))]
          .join(','));
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('CSV로 복사했어요. 엑셀·구글 시트에 붙여 넣으세요.')));
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

  // 날짜별 막대 — 한 가지 색, 칸 전체에 마우스를 올리면 날짜·횟수
  Widget _dailyChart(List<Map<String, dynamic>> days) {
    final values = [for (final d in days) _num(d['plays'])];
    final maxV = values.fold<num>(0, (m, v) => v > m ? v : m);
    final top = maxV == 0 ? 1 : maxV;
    final labelEvery = days.length <= 7 ? 1 : days.length <= 30 ? 5 : 15;
    return SizedBox(
      height: 170,
      child: Column(children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [for (var i = 0; i < 3; i++) Container(height: 1, color: const Color(0xFFEDEEF0))],
              ),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Tooltip(
                    message: '${_md('${days[i]['date']}')}  ${_n(values[i])}회',
                    waitDuration: Duration.zero,
                    child: Container(
                      color: Colors.transparent,
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: FractionallySizedBox(
                        heightFactor: values[i] == 0 ? 0.0 : (values[i] / top).clamp(0.02, 1.0).toDouble(),
                        widthFactor: 0.7,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: _ink,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Text(
                (i % labelEvery == 0 || i == days.length - 1) ? _md('${days[i]['date']}') : '',
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _gameList(Map<String, dynamic> d) {
    final all = d['storeId'] == 'all';
    final games = _rows(d['games']);
    if (games.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('이 기간에 재생한 영상이 없어요.', style: TextStyle(color: Colors.black54)),
      );
    }
    final top = _num(games.first['plays']) == 0 ? 1 : _num(games.first['plays']);
    final shown = _showAll ? games : games.take(20).toList();
    final ever = _num(d['days']) == 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < shown.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            _rank(i),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${shown[i]['title']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (!ever) '누적 ${_n(_num(shown[i]['allTime']))}회',
                    if (all) '${_n(_num(shown[i]['stores']))}개 매장',
                    if (_last(shown[i]['lastPlayedAt']).isNotEmpty) '마지막 ${_last(shown[i]['lastPlayedAt'])}',
                  ].join(' · '),
                  style: const TextStyle(color: Colors.black45, fontSize: 12),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_num(shown[i]['plays']) / top).toDouble(),
                  minHeight: 8,
                  color: _ink,
                  backgroundColor: const Color(0xFFEDEEF0),
                ),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text('${_n(_num(shown[i]['plays']))}회',
                  textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      if (games.length > 20)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? '20개만 보기' : '전체 ${games.length}개 보기'),
          ),
        ),
    ]);
  }

  Widget _perStore(Map<String, dynamic> d) {
    final list = _rows(d['perStore']);
    if (list.isEmpty) return const Text('운영 중인 매장이 없어요.', style: TextStyle(color: Colors.black54));
    final top = list.fold<num>(0, (m, s) => _num(s['total']) > m ? _num(s['total']) : m);
    return Column(children: [
      for (final s in list)
        InkWell(
          onTap: () {
            _storeId = '${s['storeId']}';
            _reload();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Text('${(s['name'] ?? '').toString().isEmpty ? s['storeId'] : s['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                flex: 2,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: top == 0 ? 0 : (_num(s['total']) / top).toDouble(),
                    minHeight: 8,
                    color: _ink,
                    backgroundColor: const Color(0xFFEDEEF0),
                  ),
                ),
              ),
              SizedBox(
                width: 210,
                child: Text(
                  '${_n(_num(s['total']))}회 · 게임 ${_n(_num(s['gamesPlayed']))}개 · 영상 ${_n(_num(s['videoGames']))}개',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _content(Map<String, dynamic> d) {
    final all = d['storeId'] == 'all';
    final days = _num(d['days']).toInt();
    final total = _num(d['total']);
    final daily = _rows(d['daily']);
    final unwatched = [for (final t in (d['unwatched'] as List?) ?? const []) '$t'];
    final videoGames = _num(d['videoGames']);
    final period = days == 0 ? '전체(누적)' : '${d['from']} ~ 오늘';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _box(
        '요약',
        '$period (한국 날짜)${all ? ' · 운영 중인 매장 ${_n(_num(d['storeCount']))}곳 합계' : ''}',
        [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _tile('${_periodName(days)} 재생', '${_n(total)}회'),
            _tile('재생된 게임', '${_n(_num(d['gamesPlayed']))}개'),
            if (days > 1) _tile('하루 평균', '${(total / days).toStringAsFixed(total / days < 10 ? 1 : 0)}회'),
            _tile('매장 영상 있는 게임', '${_n(videoGames)}개', note: '공용 영상만 쓰는 게임은 빼고 셈'),
          ]),
        ],
      ),
      if (all) _box('매장별 재생', '누르면 그 매장만 봐요.', [_perStore(d)]),
      if (days > 1 && daily.isNotEmpty)
        _box('날짜별 재생', null, [_dailyChart(daily)],
            trailing: Text(
                '가장 많은 날 ${_n(daily.fold<num>(0, (m, r) => _num(r['plays']) > m ? _num(r['plays']) : m))}회',
                style: const TextStyle(color: Colors.black45, fontSize: 12))),
      _box(
        '많이 본 게임 (${_n(_num(d['gamesPlayed']))}개)',
        all ? '전체 매장은 게임 이름으로 합침 · 공용 영상 재생도 같이 셈' : '공용 영상 재생도 같이 셈',
        [_gameList(d)],
      ),
      if (!all && videoGames > 0)
        _box(
          unwatched.isEmpty
              ? '매장 영상이 있는 게임 ${_n(videoGames)}개를 모두 한 번 이상 봤어요'
              : '매장 영상이 있는데 이 기간에 안 본 게임 ${unwatched.length}개',
          unwatched.isEmpty ? null : '영상 있는 게임 ${_n(videoGames)}개 중',
          [
            if (unwatched.isNotEmpty) ...[
              TextButton(
                onPressed: () => setState(() => _showUnwatched = !_showUnwatched),
                child: Text(_showUnwatched ? '접기' : '이름 보기'),
              ),
              if (_showUnwatched)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final t in unwatched) Chip(label: Text(t, style: const TextStyle(fontSize: 12)))],
                ),
            ],
          ],
        ),
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
        final header = Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('룰 영상 통계', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(
              width: 320,
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
            SegmentedButton<int>(
              segments: [for (final (label, d) in _periods) ButtonSegment(value: d, label: Text(label))],
              selected: {_days},
              onSelectionChanged: (v) {
                _days = v.first;
                _reload();
              },
            ),
            OutlinedButton.icon(
              onPressed: data == null ? null : () => _copyCsv(data),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('CSV 복사'),
            ),
            IconButton(onPressed: _loadStores, tooltip: '새로고침', icon: const Icon(Icons.refresh)),
          ],
        );

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
          children: [
            header,
            const SizedBox(height: 6),
            const Text('손님 패드에서 룰 영상을 재생한 횟수예요.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),
            body,
          ],
        );
      },
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
