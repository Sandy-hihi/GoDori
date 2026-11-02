import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:boardpad/screens/game_list_screen.dart';
import 'package:boardpad/services/ai_service.dart';
import 'package:boardpad/utils/game_meta.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'home_theme.dart';

/// "우리 테이블 맞춤 추천" — 질문 → 결과
Future<void> showAiRecommendDialog(
  BuildContext context, {
  int? roomNumber,
  int count = 3,
  List<String> exclude = const [],
}) {
  return showDialog(
    context: context,
    barrierColor: const Color(0x8C1A1613),
    builder: (_) => AiRecommendDialog(roomNumber: roomNumber, count: count, exclude: exclude),
  );
}

class AiRecommendDialog extends StatefulWidget {
  final int? roomNumber;
  final int count;
  final List<String> exclude;

  const AiRecommendDialog({super.key, this.roomNumber, this.count = 3, this.exclude = const []});

  @override
  State<AiRecommendDialog> createState() => _AiRecommendDialogState();
}

class _AiRecommendDialogState extends State<AiRecommendDialog> {
  int _players = 4;
  String _experience = 'sometimes';
  final Set<String> _moods = {};
  String _time = 'any';

  bool _loading = false;
  AiAsk? _asked;
  AiResult? _result;

  Future<void> _submit() async {
    final ask = AiAsk(players: _players, experience: _experience, moods: {..._moods}, time: _time);
    setState(() {
      _loading = true;
      _asked = ask;
    });
    final result = await AiService.recommend(ask, count: widget.count, exclude: widget.exclude);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showResult = _result != null && !_loading;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: showResult ? 1040 : 780),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(34, 30, 34, 30),
          child: _loading
              ? _buildLoading()
              : showResult
                  ? _buildResult(_result!)
                  : _buildAsk(),
        ),
      ),
    );
  }

  Widget _header(String title, String? sub, {List<Widget> actions = const []}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.auto_awesome, color: kAmber, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              if (sub != null) Text(sub, style: const TextStyle(fontSize: 15, color: Color(0xFF6F665B))),
            ],
          ),
        ),
        ...actions,
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
          tooltip: '닫기',
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? kInk : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? kInk : kLine)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          child: Text(label,
              style: TextStyle(
                  fontSize: 16, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : kInk)),
        ),
      ),
    );
  }

  Widget _question(String title, List<Widget> chips, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (hint != null) TextSpan(text: '  $hint', style: const TextStyle(fontSize: 14, color: kMuted)),
        ])),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );
  }

  Widget _buildAsk() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header('우리 테이블 맞춤 추천', '몇 가지만 골라 주세요. 매장에 있는 게임 중에서 찾아 드려요.'),
          const SizedBox(height: 24),
          _question('몇 명이에요?', [
            for (final n in [2, 3, 4, 5, 6])
              _chip(n == 6 ? '6명 이상' : '$n명', _players == n, () => setState(() => _players = n)),
          ]),
          const SizedBox(height: 22),
          _question('보드게임 얼마나 해 보셨어요?', [
            for (final e in aiExperienceLabels.entries)
              _chip(e.value, _experience == e.key, () => setState(() => _experience = e.key)),
          ]),
          const SizedBox(height: 22),
          _question('어떤 분위기가 좋아요?', hint: '여러 개 골라도 돼요', [
            for (final e in aiMoodLabels.entries)
              _chip(e.value, _moods.contains(e.key), () {
                setState(() => _moods.contains(e.key) ? _moods.remove(e.key) : _moods.add(e.key));
              }),
          ]),
          const SizedBox(height: 22),
          _question('한 판에 얼마나 걸려도 괜찮아요?', [
            for (final e in aiTimeLabels.entries) _chip(e.value, _time == e.key, () => setState(() => _time = e.key)),
          ]),
          const SizedBox(height: 26),
          SizedBox(
            height: 60,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('추천받기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const SizedBox(
      height: 260,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: kOrange),
          SizedBox(height: 20),
          Text('이 테이블에 맞는 게임을 고르고 있어요…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildResult(AiResult result) {
    final picks = result.picks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          picks.isEmpty ? '조건에 맞는 게임을 못 찾았어요' : '이 테이블에 맞는 게임 ${picks.length}개를 골랐어요',
          null,
          actions: [
            OutlinedButton(
              onPressed: () => setState(() => _result = null),
              style: OutlinedButton.styleFrom(
                foregroundColor: kInk,
                side: const BorderSide(color: kLine),
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 44),
              ),
              child: const Text('다시 고르기', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final l in _asked?.labels ?? const <String>[])
              if (l.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
                  child: Text(l, style: const TextStyle(fontSize: 13)),
                ),
          ],
        ),
        const SizedBox(height: 20),
        if (picks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Text('조건을 조금 넓혀서 다시 골라 보세요. 직원에게 물어보셔도 좋아요.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: kBody)),
          )
        else
          SizedBox(
            height: 400,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < picks.length; i++) ...[
                  if (i > 0) const SizedBox(width: 18),
                  Expanded(child: _ResultCard(pick: picks[i], rank: i + 1, roomNumber: widget.roomNumber)),
                ],
              ],
            ),
          ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFFF7F4EE), borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: kMuted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.fromAi
                      ? '지금 매장에서 꺼낼 수 있는 게임 중에서만 골랐어요. 고르기 어려우면 직원에게 물어보세요.'
                      : '지금 매장에서 꺼낼 수 있는 게임 중 조건에 맞는 것을 골랐어요.',
                  style: const TextStyle(fontSize: 14, color: kBody),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('다른 게임 추천받기', style: TextStyle(fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(
                  backgroundColor: kOrange,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 44),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final AiPick pick;
  final int rank;
  final int? roomNumber;

  const _ResultCard({required this.pick, required this.rank, this.roomNumber});

  static const _rankColors = [kBlue, Color(0xFF23AC3A), kOrange, Color(0xFF6B3FC4)];

  Future<void> _openVideo(BuildContext context) async {
    final url = pick.videoUrl;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('등록된 룰 영상이 없어요. 직원에게 물어보세요.')),
      );
      return;
    }
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri != null) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final color = _rankColors[(rank - 1) % _rankColors.length];
    return Container(
      decoration: BoxDecoration(border: Border.all(color: kLine), borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: color,
                  child: hasValidImage(pick.imageUrl)
                      ? AppNetworkImage(
                          imageUrl: pick.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => const Icon(Icons.casino_outlined, color: Colors.white, size: 48),
                        )
                      : const Icon(Icons.casino_outlined, color: Colors.white, size: 48),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: rank == 1 ? kAmber : Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Text('$rank순위', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kInk)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pick.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (pick.players != null) Text(pick.players!, style: const TextStyle(fontSize: 13, color: Color(0xFF6F665B))),
                      if (pick.time != null) Text('· ${pick.time}', style: const TextStyle(fontSize: 13, color: Color(0xFF6F665B))),
                      if (pick.difficulty != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('· ', style: TextStyle(fontSize: 13, color: Color(0xFF6F665B))),
                            CircleAvatar(radius: 5, backgroundColor: difficultyColor(pick.difficulty)),
                            const SizedBox(width: 4),
                            Text(pick.difficulty!, style: const TextStyle(fontSize: 13, color: Color(0xFF6F665B))),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Text(pick.reason,
                        overflow: TextOverflow.fade,
                        style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF3D362F))),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _openVideo(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: kInk,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('룰 영상 보기', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            // 팝업을 닫은 뒤에는 이 context를 못 쓰므로 Navigator를 먼저 잡아 둠
                            final nav = Navigator.of(context);
                            nav.pop();
                            nav.push(MaterialPageRoute(
                              builder: (_) => GameListScreen(roomNumber: roomNumber, initialSearchQuery: pick.title),
                            ));
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kInk,
                            side: const BorderSide(color: kLine),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('게임 정보', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
