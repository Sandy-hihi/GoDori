import 'package:flutter/material.dart';

import 'package:boardpad/services/bgg_service.dart';
import 'game_form.dart';

/// 월정액권 앱의 게임 목록으로 보드패드 게임을 전부 교체하는 팝업.
/// 1) 확인('교체' 입력) → 2) 서버가 기존 게임을 백업 컬렉션에 복사하고 비움 → 3) 15개씩 사진과 함께 가져옴
/// 월정액권 앱의 사진 요청 제한(5분에 300장)에 걸리지 않게 묶음 사이에 쉬어 가요. (전체 10~15분)
class P6ImportDialog extends StatefulWidget {
  const P6ImportDialog({super.key});

  @override
  State<P6ImportDialog> createState() => _P6ImportDialogState();
}

enum _Phase { confirm, running, paused, finished }

class _P6ImportDialogState extends State<P6ImportDialog> {
  static const int _chunk = 15;
  static const Duration _minBatchGap = Duration(seconds: 20); // 분당 약 45장

  final TextEditingController _confirmCtrl = TextEditingController();
  _Phase _phase = _Phase.confirm;
  String? _error;
  String? _backup;
  int _backedUp = 0;
  int _total = 0;
  int _offset = 0;
  int _ok = 0;
  int _noPhoto = 0;
  final List<String> _failed = [];
  bool _stopRequested = false;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.running;
      _error = null;
    });
    try {
      final r = await P6ImportService.start();
      if (!mounted) return;
      setState(() {
        _backup = r.backup;
        _backedUp = r.backedUp;
        _total = r.total;
        _offset = 0;
      });
      await _run();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.confirm;
        _error = e.toString();
      });
    }
  }

  Future<void> _run() async {
    setState(() {
      _phase = _Phase.running;
      _stopRequested = false;
      _error = null;
    });
    var failures = 0;
    while (mounted) {
      final began = DateTime.now();
      P6ImportBatchResult r;
      try {
        r = await P6ImportService.batch(_offset, _chunk);
        failures = 0;
      } catch (e) {
        failures++;
        if (failures >= 3) {
          if (!mounted) return;
          setState(() {
            _phase = _Phase.paused;
            _error = '$e\n"이어서 가져오기"를 누르면 멈춘 곳부터 다시 해요.';
          });
          return;
        }
        await Future.delayed(const Duration(seconds: 15));
        continue;
      }
      if (!mounted) return;
      setState(() {
        _total = r.total;
        _offset = r.next;
        for (final it in r.items) {
          if (it.ok) {
            _ok++;
            if (it.hadPhoto && !it.photo) _noPhoto++;
          } else {
            _failed.add(it.name);
          }
        }
      });
      if (r.done) {
        setState(() => _phase = _Phase.finished);
        return;
      }
      if (_stopRequested) {
        setState(() => _phase = _Phase.paused);
        return;
      }
      final spent = DateTime.now().difference(began);
      if (spent < _minBatchGap) await Future.delayed(_minBatchGap - spent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _phase == _Phase.running;
    final progress = _total == 0 ? null : (_offset / _total).clamp(0.0, 1.0).toDouble();

    Widget content;
    if (_phase == _Phase.confirm) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('월정액권 앱(플랫폼식스 고객 앱)의 게임 목록으로 보드패드 게임을 전부 바꿔요.', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
            '• 지금 보드패드 게임은 모두 지우고, 지우기 전에 Firestore에 백업 컬렉션(games_backup_날짜)으로 복사해 둬요. 기존 사진 파일도 지우지 않아요.\n'
            '• 월정액권 앱의 이름·인원·추천 인원·난이도·장르·매장 추천·확장판·사진을 가져와요.\n'
            '• 보드패드에만 있던 소요 시간·해시태그·룰 영상 링크는 새 목록에는 없어요. (백업에는 남아 있어요)\n'
            '• 장르 목록은 월정액권 앱의 8개(파티·가족·전략·추상전략·추리·머미·2인·협력)로 바뀌어요.\n'
            '• 사진까지 옮기느라 10~15분 걸려요. 끝날 때까지 이 창을 닫지 마세요.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmCtrl,
            decoration: adminInput("계속하려면 '교체'라고 입력하세요"),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        ],
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_backup != null) Text('기존 게임 $_backedUp개를 "$_backup" 컬렉션에 백업했어요.', style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress, color: kAdminGreen, backgroundColor: Colors.grey.shade200, minHeight: 8),
          const SizedBox(height: 8),
          Text(
            _phase == _Phase.finished
                ? '끝! $_ok개 가져왔어요.'
                : '${_phase == _Phase.paused ? '멈춤' : '가져오는 중…'}  $_offset / $_total',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (_noPhoto > 0) Text('사진을 못 가져온 게임 $_noPhoto개 — 게임 목록의 "BGG 정보·사진 다시 가져오기"로 채울 수 있어요.', style: const TextStyle(fontSize: 13)),
          if (_failed.isNotEmpty) Text('등록 실패 ${_failed.length}개: ${_failed.take(10).join(', ')}${_failed.length > 10 ? ' …' : ''}', style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          if (running) const Padding(padding: EdgeInsets.only(top: 8), child: Text('사진 요청 제한 때문에 묶음 사이에 잠깐씩 쉬어요. 창을 닫지 말고 기다려 주세요.', style: TextStyle(color: Colors.black54, fontSize: 12))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        ],
      );
    }

    final actions = <Widget>[];
    if (_phase == _Phase.confirm) {
      actions.add(TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')));
      actions.add(ElevatedButton(
        onPressed: _confirmCtrl.text.trim() == '교체' ? _start : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
        child: const Text('전부 교체 시작'),
      ));
    } else if (running) {
      actions.add(TextButton(
        onPressed: _stopRequested ? null : () => setState(() => _stopRequested = true),
        child: Text(_stopRequested ? '이번 묶음 끝나면 멈춰요…' : '잠시 멈추기'),
      ));
    } else if (_phase == _Phase.paused) {
      actions.add(TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('닫기')));
      actions.add(ElevatedButton(
        onPressed: _run,
        style: ElevatedButton.styleFrom(backgroundColor: kAdminGreen, foregroundColor: Colors.white),
        child: const Text('이어서 가져오기'),
      ));
    } else {
      actions.add(ElevatedButton(
        onPressed: () => Navigator.pop(context, true),
        style: ElevatedButton.styleFrom(backgroundColor: kAdminGreen, foregroundColor: Colors.white),
        child: const Text('닫기'),
      ));
    }

    return PopScope(
      canPop: !running,
      child: AlertDialog(
        title: const Text('월정액권 앱에서 게임 가져오기', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: content)),
        actions: actions,
      ),
    );
  }
}
