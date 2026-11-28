import 'package:flutter/material.dart';

import 'package:boardpad/services/p6_sync_service.dart';
import 'package:boardpad/widgets/admin_busy_dialog.dart';
import 'package:boardpad/widgets/admin_colors.dart';
import 'package:boardpad/widgets/admin_dialog_width.dart';

/// 보드게임 관리 [정액권 앱과 맞추기] 창 (149차)
/// 열면 미리보기(무엇이 바뀌는지) → [맞추기] → 끝나면 패드들이 게임 목록을 바로 다시 받음(서버가 appRefresh를 바꿈).
/// 맞추는 중에는 닫기·바깥 누르기를 막음.
Future<void> showP6SyncDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _P6SyncDialog(),
    );

class _P6SyncDialog extends StatefulWidget {
  const _P6SyncDialog();

  @override
  State<_P6SyncDialog> createState() => _P6SyncDialogState();
}

class _P6SyncDialogState extends State<_P6SyncDialog> {
  Map<String, dynamic>? _preview;
  String? _error;
  bool _loading = true;
  bool _running = false;
  int _applied = 0;
  int _rounds = 0;
  bool _finished = false;
  final List<String> _problems = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await P6SyncService.preview();
      if (!mounted) return;
      setState(() {
        _preview = p;
        _loading = false;
      });
    } on P6SyncException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _applied = 0;
      _rounds = 0;
      _problems.clear();
    });
    try {
      // 서버는 한 번에 80초까지만 일함 → 다 될 때까지(최대 10번) 다시 부름
      while (_rounds < 10) {
        _rounds++;
        final r = await P6SyncService.run();
        _applied += _int(r['applied']);
        for (final e in [...(r['errors'] as List? ?? const []), ...(r['warnings'] as List? ?? const [])]) {
          if (e is Map) _problems.add('${e['name']}: ${e['message']}');
        }
        if (mounted) setState(() {});
        if (r['done'] == true) break;
      }
      if (!mounted) return;
      setState(() {
        _running = false;
        _finished = true;
      });
    } on P6SyncException catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e.message;
      });
    }
  }

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  Map<String, dynamic> _section(String key) {
    final v = _preview?[key];
    return v is Map ? Map<String, dynamic>.from(v) : const {'count': 0, 'items': []};
  }

  String _when(Object? iso) {
    final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.month}월 ${t.day}일 ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final todo = _int(_preview?['todo']);
    final busy = _loading || _running;
    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        title: const Row(children: [
          Icon(Icons.sync, color: kAdminAccent),
          SizedBox(width: 8),
          Expanded(child: Text('월 정액권 앱과 맞추기')),
        ]),
        content: SizedBox(
          width: adminDialogWidth(context, 620),
          child: _body(todo),
        ),
        actions: [
          TextButton(
            onPressed: _running ? null : () => Navigator.of(context).pop(),
            child: Text(_finished ? '닫기' : '취소'),
          ),
          if (!_finished && _preview != null && todo > 0)
            ElevatedButton.icon(
              onPressed: busy ? null : _run,
              icon: const Icon(Icons.sync, size: 18),
              label: Text('맞추기 ($todo건)'),
              style: busyButtonStyle(kAdminAccent),
            ),
          if (!_finished && _preview == null && !_loading)
            ElevatedButton(onPressed: _load, style: busyButtonStyle(kAdminAccent), child: const Text('다시 보기')),
        ],
      ),
    );
  }

  Widget _body(int todo) {
    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('월 정액권 앱 게임 목록과 비교하는 중이에요…', style: TextStyle(color: Colors.black54)),
        ])),
      );
    }
    final children = <Widget>[];
    if (_error != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600))),
        ]),
      ));
    }
    final p = _preview;
    if (p == null) return Column(mainAxisSize: MainAxisSize.min, children: children);

    if (_finished) {
      children.add(Row(children: [
        const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
        const SizedBox(width: 8),
        Expanded(child: Text('맞추기 끝 · $_applied건 반영했어요. 패드들이 게임 목록을 바로 다시 받아요.',
            style: const TextStyle(fontWeight: FontWeight.bold))),
      ]));
      if (_problems.isNotEmpty) {
        children.add(const SizedBox(height: 12));
        children.add(Text('확인할 것 ${_problems.length}개', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)));
        for (final s in _problems.take(30)) {
          children.add(Text('· $s', style: const TextStyle(fontSize: 13, color: Colors.black87)));
        }
        children.add(const Text('사진을 못 받은 게임은 다음에 맞출 때 다시 받아요.', style: TextStyle(fontSize: 12, color: Colors.black54)));
      }
      return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children));
    }

    children.add(Text('정액권 앱 게임 ${_int(p['p6Count'])}개 · 고도리 게임 ${_int(p['godoriCount'])}개',
        style: const TextStyle(color: Colors.black54)));
    final last = p['last'] is Map ? p['last'] as Map : const {};
    final lastText = [
      if (_when(last['lastSyncAt']).isNotEmpty) '마지막으로 맞춘 때 ${_when(last['lastSyncAt'])}',
      if (_when(last['lastHookAt']).isNotEmpty) '마지막 자동 신호 ${_when(last['lastHookAt'])}',
    ].join(' · ');
    if (lastText.isNotEmpty) children.add(Text(lastText, style: const TextStyle(color: Colors.black54, fontSize: 13)));
    children.add(const SizedBox(height: 12));

    if (todo == 0) {
      children.add(const Row(children: [
        Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
        SizedBox(width: 8),
        Expanded(child: Text('바뀐 게 없어요. 정액권 앱과 같아요.', style: TextStyle(fontWeight: FontWeight.bold))),
      ]));
    }

    String plain(Object? e) => e is Map ? '${e['name']}' : '$e';
    String withFields(Object? e) {
      if (e is! Map) return '$e';
      final f = (e['fields'] as List?)?.join(', ') ?? '';
      return f.isEmpty ? '${e['name']}' : '${e['name']}  ·  $f';
    }

    children.addAll([
      _group(Icons.add_circle_outline, '새로 들어올 게임', _section('create'), plain, const Color(0xFF2E7D32)),
      _group(Icons.edit_outlined, '바뀔 게임', _section('update'), withFields, kAdminAccent),
      _group(Icons.category, '고도리에 직접 넣었던 게임과 짝지음', _section('link'),
          (e) => e is Map ? '${e['godoriName']} → ${e['name']}' : '$e', kAdminAccent),
      _group(Icons.visibility_off_outlined, '손님 화면에서 숨길 게임 (정액권 앱에서 빠짐)', _section('hide'), plain, Colors.deepOrange),
      _group(Icons.visibility_outlined, '다시 보일 게임', _section('restore'), plain, const Color(0xFF2E7D32)),
    ]);
    final newGenres = (p['newGenres'] as List?) ?? const [];
    if (newGenres.isNotEmpty) children.add(_line(Icons.category, '새 장르 추가: ${newGenres.join(', ')}'));
    if (_int(p['images']) > 0) children.add(_line(Icons.image_outlined, '사진을 새로 받을 게임 ${_int(p['images'])}개'));
    if (_int(p['baseline']) > 0) {
      children.add(_line(Icons.info_outline, '처음 맞추는 게임 ${_int(p['baseline'])}개는 지금 사진을 그대로 두고, 앞으로 정액권 앱 사진이 바뀔 때만 받아요.'));
    }
    if (_int(p['godoriOnly']) > 0) {
      children.add(_line(Icons.info_outline, '고도리에만 있는 게임 ${_int(p['godoriOnly'])}개는 그대로 둬요.'));
    }
    children.add(const SizedBox(height: 8));
    children.add(const Text(
      '정액권 앱 값으로 바뀌는 것: 이름·장르·인원·난이도·BGG 정보·확장판·매장 추천·NEW 표시·사진.\n'
      '그대로 두는 것: 소요시간·태그·룰 영상·유튜브 링크·이용 가능 스위치.',
      style: TextStyle(fontSize: 12, color: Colors.black54),
    ));
    if (_running) {
      children.add(const SizedBox(height: 12));
      children.add(Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Text('맞추는 중… $_applied / $todo건 (사진이 많으면 오래 걸려요)'),
      ]));
    }
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ]),
      );

  Widget _group(IconData icon, String title, Map<String, dynamic> sec, String Function(Object?) label, Color color) {
    final count = _int(sec['count']);
    if (count == 0) return const SizedBox.shrink();
    final items = (sec['items'] as List?) ?? const [];
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(icon, color: color),
        title: Text('$title  $count개', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        childrenPadding: const EdgeInsets.only(left: 40, bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in items) Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(label(e), style: const TextStyle(fontSize: 13)),
          ),
          if (count > items.length) Text('… 외 ${count - items.length}개', style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}
