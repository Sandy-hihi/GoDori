import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/pad_shell.dart';

/// 룰 설명 영상 — 매장에서 만든 영상(ruleVideoUrl, Firebase Storage)이 있으면 앱 안에서 틀고,
/// 없으면 유튜브 링크(videoUrl)를 엶. 둘 다 없으면 안내.

String _clean(dynamic v) => (v ?? '').toString().trim();

/// 매장 영상 주소 (없으면 null)
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

bool hasRuleVideo(Map<String, dynamic> game) => ownRuleVideoOf(game) != null || youtubeLinkOf(game) != null;

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
  final own = ownRuleVideoOf(game);
  final yt = youtubeLinkOf(game);
  if (own != null) {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => RuleVideoDialog(
        title: _clean(game['title']),
        videoUrl: own,
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
class RuleVideoDialog extends StatefulWidget {
  final String title;
  final String videoUrl;
  final String? fallbackLink; // 재생이 안 될 때 열 유튜브 링크
  const RuleVideoDialog({super.key, required this.title, required this.videoUrl, this.fallbackLink});

  @override
  State<RuleVideoDialog> createState() => _RuleVideoDialogState();
}

class _RuleVideoDialogState extends State<RuleVideoDialog> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
  bool _ready = false;
  String? _error;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    _init();
  }

  Future<void> _init() async {
    try {
      await _c.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      await _c.play();
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _error = '영상을 재생하지 못했어요.');
    }
  }

  void _onTick() {
    if (!mounted) return;
    if (_c.value.hasError && _error == null) {
      setState(() => _error = '영상을 재생하지 못했어요.');
      return;
    }
    setState(() {}); // 재생 시간·버튼 갱신
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying) setState(() => _showControls = false);
    });
  }

  void _poke() {
    setState(() => _showControls = true);
    _scheduleHide();
  }

  void _togglePlay() {
    if (_c.value.isPlaying) {
      _c.pause();
      _hideTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      // 끝까지 봤으면 처음부터
      if (_c.value.position >= _c.value.duration - const Duration(milliseconds: 300)) {
        _c.seekTo(Duration.zero);
      }
      _c.play();
      _scheduleHide();
    }
  }

  void _skip(int seconds) {
    final d = _c.value.duration;
    var p = _c.value.position + Duration(seconds: seconds);
    if (p < Duration.zero) p = Duration.zero;
    if (p > d) p = d;
    _c.seekTo(p);
    _poke();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: _body()),
          // 위: 제목 + 닫기 (항상 보임)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
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
                    child: Text('${widget.title} 룰 설명',
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
            Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (widget.fallbackLink != null)
              FilledButton.icon(
                onPressed: () {
                  final link = widget.fallbackLink!;
                  Navigator.pop(context);
                  _openLink(context, link);
                },
                icon: const Icon(Icons.play_circle_fill),
                label: const Text('유튜브 영상으로 보기', style: TextStyle(fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(backgroundColor: kOrange, foregroundColor: Colors.white),
              )
            else
              const Text('직원에게 설명을 요청해 주세요.', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator(color: kOrange));
    }

    final v = _c.value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _poke,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
              child: VideoPlayer(_c),
            ),
          ),
          if (v.isBuffering)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
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
          // 아래: 진행 막대 + 시간
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
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
                    Text(_fmt(v.position), style: const TextStyle(color: Colors.white, fontSize: 14)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: VideoProgressIndicator(
                        _c,
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
                    Text(_fmt(v.duration), style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        ],
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
