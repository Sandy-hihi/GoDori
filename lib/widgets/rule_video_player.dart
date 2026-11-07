import 'package:boardpad/l10n/guest_language.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:boardpad/services/rule_video_service.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/pad_shell.dart';

/// 룰 설명 영상 — 앞에 있는 것부터:
///  1) 매장에서 만든 영상 (Cloudflare R2, games.ruleVideo) → 서버에서 임시 주소를 받아 앱 안에서 재생.
///     720p 파일도 있으면: 버퍼링이 잦으면 같은 위치에서 720p로 바꿈 + 화질 버튼.
///     한 번 느려서 바꾼 패드는 며칠 동안 720p로 시작 (SharedPreferences)
///  2) 예전 방식 매장 영상 (ruleVideoUrl, Firebase Storage)
///  3) 유튜브 링크 (videoUrl) → 브라우저/유튜브 앱으로 엶
/// 다 없으면 안내.
///
/// 웹(크롬에서 패드 시험)에서는 영상이 HTML <video> 요소라서 그 위의 버튼·탭이 영상에 먹힘
/// → 조작 영역을 PointerInterceptor로 감쌈 (안드로이드 앱에서는 아무 일도 안 함)

String _clean(dynamic v) => (v ?? '').toString().trim();

/// 게임 문서 ID (게임 목록 화면이 '_docId'로 넣어 줌)
String? gameIdOf(Map<String, dynamic> game) {
  final id = _clean(game['_docId']).isNotEmpty ? _clean(game['_docId']) : _clean(game['id']);
  return id.isEmpty ? null : id;
}

/// R2 영상이 있고 재생할 수 있는지 (문서 ID가 있어야 서버에 주소를 물어볼 수 있음)
bool _hasR2(Map<String, dynamic> game) => gameIdOf(game) != null && RuleVideoService.hasVideo(game);

/// 예전 방식 매장 영상 주소 (없으면 null)
String? ownRuleVideoOf(Map<String, dynamic> game) {
  final u = _clean(game['ruleVideoUrl']);
  return u.startsWith('http') ? u : null;
}

/// 유튜브 등 링크 (없으면 null)
String? youtubeLinkOf(Map<String, dynamic> game) {
  final u = _clean(game['videoUrl']);
  if (u.isEmpty) return null;
  return u.startsWith('http') ? u : 'https://$u';
}

/// 매장에서 만든 영상(앱 안 재생)이 있는지
bool hasStoreRuleVideo(Map<String, dynamic> game) => _hasR2(game) || ownRuleVideoOf(game) != null;

bool hasRuleVideo(Map<String, dynamic> game) => hasStoreRuleVideo(game) || youtubeLinkOf(game) != null;

Future<void> _openLink(BuildContext context, String url) async {
  try {
    final ok = await launchUrl(Uri.parse(url));
    if (!ok && context.mounted) padSnack(context, '영상을 열 수 없어요. 직원에게 알려 주세요.', error: true);
  } catch (_) {
    if (context.mounted) padSnack(context, '영상을 열 수 없어요. 직원에게 알려 주세요.', error: true);
  }
}

/// 게임의 룰 영상 열기
Future<void> openRuleVideo(BuildContext context, Map<String, dynamic> game) async {
  final yt = youtubeLinkOf(game);
  final r2 = _hasR2(game);
  final own = ownRuleVideoOf(game);
  if (r2 || own != null) {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => RuleVideoDialog(
        title: _clean(game['title']),
        gameId: r2 ? gameIdOf(game) : null,
        videoUrl: r2 ? null : own,
        fallbackLink: yt,
      ),
    );
    return;
  }
  if (yt != null) {
    await _openLink(context, yt);
    return;
  }
  padSnack(context, '등록된 룰 영상이 없어요. 직원에게 설명을 요청해 주세요.');
}

/// 매장 영상 재생 팝업 (가로 영상 기준)
/// gameId가 있으면 R2 영상(서버에서 주소 받기), 없으면 videoUrl을 그대로 재생
class RuleVideoDialog extends StatefulWidget {
  final String title;
  final String? gameId;
  final String? videoUrl;
  final String? fallbackLink; // 재생이 안 될 때 열 유튜브 링크
  const RuleVideoDialog({super.key, required this.title, this.gameId, this.videoUrl, this.fallbackLink})
      : assert(gameId != null || videoUrl != null);

  @override
  State<RuleVideoDialog> createState() => _RuleVideoDialogState();
}

class _RuleVideoDialogState extends State<RuleVideoDialog> {
  // 느려서 720p로 바꾼 패드는 이 시각(밀리초)까지 720p로 시작
  static const String _prefLowUntil = 'ruleVideoLowUntil';
  static const Duration _rememberLow = Duration(days: 3);
  // 버퍼링 판단: 한 번에 4초 이상 멈추거나, 1분 안에 0.7초 이상 멈춤이 3번
  static const Duration _longStall = Duration(seconds: 4);
  static const Duration _shortStall = Duration(milliseconds: 700);
  static const int _stallsPerMinute = 3;

  VideoPlayerController? _c;
  Map<String, String> _urls = {}; // '1080' / '720' → 주소 (예전 방식은 'src')
  String _quality = '';
  bool _ready = false;
  bool _switching = false;
  bool _manualChoice = false; // 손님이 화질을 직접 고르면 자동으로 안 바꿈
  bool _refetched = false; // 주소가 만료돼 다시 받았는지 (한 번만)
  String? _error;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _fullscreen = false; // 화면 꽉 채우기 (안드로이드는 위·아래 시스템 막대도 숨김)

  // 재생 속도 (배속 버튼 → 펼치는 메뉴에서 고름). 화질을 바꿔도 유지
  static const List<double> _speeds = [0.5, 1.0, 1.5, 2.0];
  double _speed = 1.0;
  bool _speedMenuOpen = false;

  // 두 번 톡톡: 왼쪽 절반 10초 뒤로, 오른쪽 절반 10초 앞으로 (유튜브처럼)
  Offset? _doubleTapAt;
  int? _seekFlashSide; // -1 왼쪽, 1 오른쪽 (잠깐 표시)
  int _seekFlashSeconds = 0; // 연달아 두 번 톡톡 하면 쌓여서 20초, 30초…
  Timer? _seekFlashTimer;

  // 버퍼링 감시
  DateTime? _stallStart;
  DateTime _graceUntil = DateTime(0); // 시작·이동 직후의 버퍼링은 세지 않음
  Duration _lastPos = Duration.zero;
  final List<DateTime> _stalls = [];
  Timer? _watchdog;

  String? _notice;
  Timer? _noticeTimer;

  bool get _hasBoth => _urls.containsKey('1080') && _urls.containsKey('720');

  @override
  void initState() {
    super.initState();
    _start();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _checkLongStall());
  }

  Future<void> _start() async {
    try {
      if (widget.gameId != null) {
        final r = await RuleVideoService.playUrls(widget.gameId!);
        _urls = r.urls;
        _quality = await _initialQuality();
      } else {
        _urls = {'src': widget.videoUrl!};
        _quality = 'src';
      }
      try {
        await _open(_quality, Duration.zero, play: true);
      } catch (_) {
        // 1080p를 못 열면 720p로 (반대도)
        final other = _quality == '1080' ? '720' : (_quality == '720' ? '1080' : null);
        if (other == null || !_urls.containsKey(other)) rethrow;
        await _open(other, Duration.zero, play: true);
      }
    } on RuleVideoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '영상을 재생하지 못했어요.');
    }
  }

  Future<String> _initialQuality() async {
    if (!_urls.containsKey('1080')) return '720';
    if (!_urls.containsKey('720')) return '1080';
    try {
      final p = await SharedPreferences.getInstance();
      if ((p.getInt(_prefLowUntil) ?? 0) > DateTime.now().millisecondsSinceEpoch) return '720';
    } catch (_) {}
    return '1080';
  }

  Future<void> _rememberLowQuality(bool low) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (low) {
        await p.setInt(_prefLowUntil, DateTime.now().add(_rememberLow).millisecondsSinceEpoch);
      } else {
        await p.remove(_prefLowUntil);
      }
    } catch (_) {}
  }

  /// 영상 열기 (화질 바꿀 때는 같은 위치에서)
  Future<void> _open(String q, Duration at, {required bool play}) async {
    final c = VideoPlayerController.networkUrl(Uri.parse(_urls[q]!));
    try {
      await c.initialize();
      if (at > Duration.zero) await c.seekTo(at);
      if (_speed != 1.0) await c.setPlaybackSpeed(_speed);
    } catch (_) {
      await c.dispose();
      rethrow;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    final old = _c;
    old?.removeListener(_onTick);
    c.addListener(_onTick);
    _graceUntil = DateTime.now().add(const Duration(seconds: 3));
    _stallStart = null;
    _lastPos = at;
    setState(() {
      _c = c;
      _quality = q;
      _ready = true;
      _error = null;
    });
    // 새 영상으로 화면이 바뀐 뒤에 예전 컨트롤러 정리
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    if (play) {
      await c.play();
      _scheduleHide();
    }
  }

  void _onTick() {
    final c = _c;
    if (!mounted || c == null) return;
    final v = c.value;
    if (v.hasError && _error == null && !_switching) {
      _recover();
      return;
    }
    _trackStall(v);
    setState(() {}); // 재생 시간·버튼 갱신
  }

  // 재생 중 오류: 임시 주소가 만료됐을 수 있어서 한 번만 주소를 다시 받아 같은 위치에서 이어 틂
  Future<void> _recover() async {
    final c = _c;
    if (widget.gameId == null || _refetched || c == null) {
      setState(() => _error = '영상을 재생하지 못했어요.');
      return;
    }
    _refetched = true;
    final pos = c.value.position;
    setState(() => _switching = true);
    try {
      _urls = (await RuleVideoService.playUrls(widget.gameId!, countPlay: false)).urls;
      if (!_urls.containsKey(_quality)) _quality = _urls.keys.first;
      await _open(_quality, pos, play: true);
    } catch (_) {
      if (mounted) setState(() => _error = '영상을 재생하지 못했어요.');
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  void _trackStall(VideoPlayerValue v) {
    final now = DateTime.now();
    // 손님이 앞뒤로 옮기면(진행 막대 끌기 포함) 그 직후 버퍼링은 세지 않음
    if ((v.position - _lastPos).abs() > const Duration(seconds: 2)) {
      _graceUntil = now.add(const Duration(seconds: 3));
    }
    _lastPos = v.position;

    final stalled = v.isBuffering && v.isPlaying && !_switching && now.isAfter(_graceUntil);
    if (stalled) {
      _stallStart ??= now;
    } else if (_stallStart != null) {
      if (now.difference(_stallStart!) >= _shortStall) {
        _stalls.add(now);
        _stalls.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
        if (_stalls.length >= _stallsPerMinute) _autoLower();
      }
      _stallStart = null;
    }
  }

  // 멈춘 동안에는 영상 쪽 알림이 안 올 수 있어서 1초마다 따로 확인
  void _checkLongStall() {
    final s = _stallStart;
    if (s != null && DateTime.now().difference(s) >= _longStall) _autoLower();
  }

  void _autoLower() {
    if (_quality != '1080' || !_urls.containsKey('720') || _manualChoice || _switching) return;
    _stalls.clear();
    _stallStart = null;
    _rememberLowQuality(true);
    _switchQuality('720', notice: '인터넷이 느려서 720p로 바꿨어요');
  }

  Future<void> _switchQuality(String q, {String? notice}) async {
    final c = _c;
    if (c == null || _switching || q == _quality || !_urls.containsKey(q)) return;
    final pos = c.value.position;
    final wasPlaying = c.value.isPlaying;
    setState(() => _switching = true);
    await c.pause();
    try {
      await _open(q, pos, play: wasPlaying);
      _flash(notice ?? '${q}p로 바꿨어요');
    } catch (_) {
      _flash('화질을 바꾸지 못했어요');
      if (wasPlaying) await c.play();
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  void _onQualityTap() {
    final next = _quality == '1080' ? '720' : '1080';
    _manualChoice = true;
    _rememberLowQuality(next == '720');
    _switchQuality(next);
    _poke();
  }

  void _toggleSpeedMenu() {
    setState(() => _speedMenuOpen = !_speedMenuOpen);
    _poke();
  }

  void _setSpeed(double next) {
    final c = _c;
    if (c == null) return;
    setState(() {
      _speed = next;
      _speedMenuOpen = false;
    });
    c.setPlaybackSpeed(next);
    _flash('재생 속도 ${_speedText(next)}');
    _poke();
  }

  // 1.0 → "1", 1.5 → "1.5"
  static String _num(double s) => s == s.roundToDouble() ? s.toInt().toString() : s.toString();
  static String _speedText(double s) => s == 1.0 ? '보통(1배)' : '${_num(s)}배';

  void _onDoubleTap(double width) {
    final at = _doubleTapAt;
    if (at == null || width <= 0) return;
    final side = at.dx < width / 2 ? -1 : 1;
    _skip(10 * side, showControls: false);
    // 같은 쪽을 계속 두 번 톡톡 하면 초가 쌓여 보임
    _seekFlashSeconds = (_seekFlashSide == side ? _seekFlashSeconds : 0) + 10;
    _seekFlashTimer?.cancel();
    setState(() => _seekFlashSide = side);
    _seekFlashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekFlashSide = null);
    });
  }

  void _toggleFullscreen() {
    final on = !_fullscreen;
    setState(() => _fullscreen = on);
    _setSystemBars(hidden: on);
    _poke();
  }

  static void _setSystemBars({required bool hidden}) {
    try {
      if (hidden) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      }
    } catch (_) {}
  }

  void _flash(String msg) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    setState(() => _notice = msg);
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      // 배속 메뉴를 펼쳐 둔 동안은 숨기지 않음
      if (mounted && !_speedMenuOpen && (_c?.value.isPlaying ?? false)) setState(() => _showControls = false);
    });
  }

  void _poke() {
    setState(() => _showControls = true);
    _scheduleHide();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
      _hideTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      // 끝까지 봤으면 처음부터
      if (c.value.position >= c.value.duration - const Duration(milliseconds: 300)) {
        c.seekTo(Duration.zero);
      }
      c.play();
      _scheduleHide();
    }
  }

  void _skip(int seconds, {bool showControls = true}) {
    final c = _c;
    if (c == null) return;
    final d = c.value.duration;
    var p = c.value.position + Duration(seconds: seconds);
    if (p < Duration.zero) p = Duration.zero;
    if (p > d) p = d;
    _graceUntil = DateTime.now().add(const Duration(seconds: 3));
    c.seekTo(p);
    if (showControls) _poke();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _noticeTimer?.cancel();
    _watchdog?.cancel();
    _seekFlashTimer?.cancel();
    if (_fullscreen) _setSystemBars(hidden: false);
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 전체화면이면 제목 줄도 조작 버튼과 같이 숨김 (화면을 누르면 다시 나옴)
    final titleVisible = !_fullscreen || _showControls || !_ready || _error != null;
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: _fullscreen ? EdgeInsets.zero : const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_fullscreen ? 0 : 20)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: _body()),
          // 위: 제목 + 닫기
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AnimatedOpacity(
              opacity: titleVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !titleVisible,
                child: PointerInterceptor(
                  child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 10, 8, 24),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xAA000000), Color(0x00000000)],
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.smart_display_rounded, color: kOrange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GuestText('${widget.title} 룰 설명',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
                          ),
                        ],
                      ),
                  ),
                ),
              ),
            ),
          ),
          // 알림 (화질 바뀜 등)
          if (_notice != null)
            Positioned(
              top: 64,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(20)),
                  child: GuestText(_notice!, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 56),
            const SizedBox(height: 12),
            GuestText(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (widget.fallbackLink != null)
              FilledButton.icon(
                onPressed: () {
                  final link = widget.fallbackLink!;
                  Navigator.pop(context);
                  _openLink(context, link);
                },
                icon: const Icon(Icons.play_circle_fill),
                label: const GuestText('유튜브 영상으로 보기', style: TextStyle(fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(backgroundColor: kOrange, foregroundColor: Colors.white),
              )
            else
              const GuestText('직원에게 설명을 요청해 주세요.', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    final c = _c;
    if (!_ready || c == null) {
      return const Center(child: CircularProgressIndicator(color: kOrange));
    }

    final v = c.value;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
            child: VideoPlayer(c),
          ),
        ),
        // 조작 영역 전체 (화면 누르기·버튼·진행 막대). 웹에서 영상이 탭을 가로채지 않게 PointerInterceptor
        // 한 번 누르기 = 버튼 보이기, 두 번 톡톡 = 10초 이동(왼쪽 절반 뒤로 / 오른쪽 절반 앞으로)
        Positioned.fill(
          child: PointerInterceptor(
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // 메뉴 바깥을 누르면 메뉴만 닫힘
                  if (_speedMenuOpen) setState(() => _speedMenuOpen = false);
                  _poke();
                },
                onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                onDoubleTap: () => _onDoubleTap(box.maxWidth),
                child: _controls(c, v),
              ),
            ),
          ),
        ),
        if (_seekFlashSide != null) _seekFlash(),
      ],
    );
  }

  Widget _controls(VideoPlayerController c, VideoPlayerValue v) {
    return Stack(
        fit: StackFit.expand,
        children: [
          if (v.isBuffering || _switching) const Center(child: CircularProgressIndicator(color: Colors.white)),
          // 가운데: 10초 뒤로 · 재생/멈춤 · 10초 앞으로
          AnimatedOpacity(
            opacity: _showControls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _roundButton(Icons.replay_10_rounded, () => _skip(-10), 56),
                    const SizedBox(width: 28),
                    _roundButton(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, _togglePlay, 80),
                    const SizedBox(width: 28),
                    _roundButton(Icons.forward_10_rounded, () => _skip(10), 56),
                  ],
                ),
              ),
            ),
          ),
          // 아래: 진행 막대 + 시간 + 화질
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xAA000000), Color(0x00000000)],
                    ),
                  ),
                  child: Row(
                    children: [
                      GuestText(_fmt(v.position), style: const TextStyle(color: Colors.white, fontSize: 14)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: VideoProgressIndicator(
                          c,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          colors: const VideoProgressColors(
                            playedColor: kOrange,
                            bufferedColor: Color(0x66FFFFFF),
                            backgroundColor: Color(0x33FFFFFF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GuestText(_fmt(v.duration), style: const TextStyle(color: Colors.white, fontSize: 14)),
                      if (_hasBoth) ...[
                        const SizedBox(width: 12),
                        _qualityButton(),
                      ],
                      const SizedBox(width: 12),
                      _speedButton(),
                      const SizedBox(width: 8),
                      _iconPill(
                        _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                        _fullscreen ? '전체화면 끄기' : '전체화면',
                        _toggleFullscreen,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 배속 메뉴 (배속 버튼 바로 위, 오른쪽에 붙여서)
          if (_speedMenuOpen && _showControls)
            Positioned(right: 64, bottom: 66, child: _speedMenu()),
        ],
    );
  }

  Widget _speedMenu() {
    return Material(
      color: const Color(0xEE202020),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: GuestText('재생 속도', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            for (final sp in _speeds)
              InkWell(
                onTap: () => _setSpeed(sp),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 20, 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: sp == _speed ? const Icon(Icons.check_rounded, color: kOrange, size: 22) : null,
                      ),
                      GuestText(sp == 1.0 ? '1x (보통)' : '${_num(sp)}x',
                          style: TextStyle(
                            color: sp == _speed ? kOrange : Colors.white,
                            fontSize: 17,
                            fontWeight: sp == _speed ? FontWeight.w800 : FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  // 두 번 톡톡 했을 때 그쪽 절반에 잠깐 보이는 표시 ("« 10초" / "10초 »")
  Widget _seekFlash() {
    final left = _seekFlashSide == -1;
    return IgnorePointer(
      child: Align(
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        child: FractionallySizedBox(
          widthFactor: 0.5,
          heightFactor: 1,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: left ? Alignment.centerLeft : Alignment.centerRight,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: const [Color(0x55FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(left ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, color: Colors.white, size: 44),
                const SizedBox(height: 4),
                GuestText('$_seekFlashSeconds초',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 배속 버튼: 누르면 바로 위에 속도 메뉴가 펼쳐짐
  // (Flutter 기본 팝업 메뉴는 새 화면으로 떠서 웹에서 영상 위에 뜨면 눌리지 않음 → 같은 화면 안에 직접 그림)
  Widget _speedButton() {
    final label = '${_num(_speed)}x';
    return Tooltip(
      message: '재생 속도',
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _toggleSpeedMenu,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speed_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 4),
                GuestText(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconPill(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }

  // 화질 버튼: 누를 때마다 1080p ↔ 720p
  Widget _qualityButton() {
    final hd = _quality == '1080';
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _switching ? null : _onQualityTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hd ? Icons.hd_rounded : Icons.sd_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 4),
              GuestText(hd ? '1080p' : '720p', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap, double size) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: Icon(icon, color: Colors.white, size: size * 0.55)),
      ),
    );
  }
}
