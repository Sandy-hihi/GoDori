import 'package:flutter/material.dart';

import '../utils/mp4_info.dart';
import '../widgets/game_admin/game_form.dart' show pickVideoFile, ruleVideoMaxBytes, PickedVideo;
import 'ops_service.dart';

/// 운영자 페이지 '공용 룰 영상' 탭 (92차) — 서버 functions/src/video.js shared*
///
/// BGG 번호 기준으로 한 번만 올리면, 그 BGG 번호(geekId)의 게임이 있는 모든 매장 패드에서 재생됨.
/// 매장이 직접 올린 영상이 있으면 매장 영상이 먼저. R2 저장비가 매장 수와 상관없이 한 벌 값만 듦.
/// 패드는 게임 목록을 하루 1번만 받아서(game_catalog.dart), 새 공용 영상은 다음 날(또는 매장 '손님 앱 새로고침' 뒤)부터 보임.
class OpsSharedVideosTab extends StatefulWidget {
  const OpsSharedVideosTab({super.key});

  @override
  State<OpsSharedVideosTab> createState() => _OpsSharedVideosTabState();
}

class _OpsSharedVideosTabState extends State<OpsSharedVideosTab> {
  final _bggId = TextEditingController();
  final _title = TextEditingController();
  final _moveStore = TextEditingController(text: 'platform6'); // 93차: 매장 영상 → 공용 옮기기
  bool _moving = false;
  List<Map<String, dynamic>> _videos = [];
  int _totalBytes = 0;
  bool _loading = true;
  String? _error;
  String? _busyKey; // 올리는 중인 '<BGG 번호>:<화질>'
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bggId.dispose();
    _title.dispose();
    _moveStore.dispose();
    super.dispose();
  }

  // 93차: 매장이 올린 영상을 공용으로 옮기기 — 미리 보기 → 확인 → 옮기기 (파일은 R2에 그대로, 기록만 옮김)
  Future<void> _moveFromStore() async {
    final storeId = _moveStore.text.trim();
    if (storeId.isEmpty) return;
    setState(() => _moving = true);
    try {
      final preview = await OpsService.moveStoreVideosToShared(storeId, dryRun: true);
      final moved = [for (final m in (preview['moved'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
      final skipped = [for (final s in (preview['skipped'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
      if (!mounted) return;
      if (moved.isEmpty) {
        _snack(skipped.isEmpty ? '$storeId 매장에 옮길 영상이 없어요.' : '옮길 수 있는 영상이 없어요. (건너뜀 ${skipped.length}개 — BGG 번호 없음 또는 공용 영상이 이미 있음)');
        return;
      }
      String line(Map<String, dynamic> m) =>
          "${m['title']} (BGG #${m['bggId'] ?? '-'}) ${(m['qualities'] as List? ?? const []).map((q) => '${q}p').join('·')}";
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$storeId 매장 영상 ${moved.length}개를 공용으로 옮길까요?'),
          content: SizedBox(
            width: 520,
            height: 360,
            child: ListView(children: [
              const Text('옮기면 이 게임들은 같은 BGG 번호의 게임이 있는 모든 매장에서 재생돼요. '
                  '영상 파일은 그대로이고, 이 매장의 게임 목록에는 "공용 룰 영상"으로 표시돼요.',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              const Text('옮길 것', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final m in moved) Text('• ${line(m)}'),
              if (skipped.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('건너뛸 것 (매장 영상으로 남음)', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final s in skipped) Text('• ${line(s)} — ${s['reason']}', style: const TextStyle(color: Colors.black54)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('${moved.length}개 옮기기')),
          ],
        ),
      );
      if (go != true) return;
      final r = await OpsService.moveStoreVideosToShared(storeId, dryRun: false);
      _snack('${(r['moved'] as List? ?? const []).length}개를 공용으로 옮겼어요. '
          '패드에는 그 매장이 "손님 앱 새로고침"을 누르거나 다음 날부터 공용으로 보여요(그 전에도 재생은 돼요).');
      await _load();
    } catch (e) {
      _snack('옮기지 못했어요: $e', error: true);
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await OpsService.sharedVideos();
      if (!mounted) return;
      setState(() {
        _videos = [for (final v in (r['videos'] as List? ?? const [])) Map<String, dynamic>.from(v as Map)];
        _totalBytes = (r['totalBytes'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFD64545) : null,
    ));
  }

  Future<void> _upload(String bggId, String title, String quality) async {
    if (!RegExp(r'^\d{1,9}$').hasMatch(bggId)) {
      _snack('BGG 번호(숫자)를 넣어 주세요. 예: 카탄 13', error: true);
      return;
    }
    final PickedVideo? v = await pickVideoFile();
    if (v == null) return;
    final info = Mp4Info.parse(v.bytes);
    final check = checkRuleVideo(info, quality: quality, sizeBytes: v.bytes.length, maxBytes: ruleVideoMaxBytes);
    if (!check.ok || check.warnings.isNotEmpty) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(check.ok ? '영상 확인' : '올릴 수 없는 영상이에요'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (info.summary.isNotEmpty) Text(info.summary, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              for (final e in check.errors) Text('✕ $e', style: const TextStyle(color: Colors.redAccent)),
              for (final w in check.warnings) Text('• $w', style: TextStyle(color: Colors.orange.shade900)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(check.ok ? '취소' : '닫기')),
            if (check.ok) ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('그래도 올리기')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() {
      _busyKey = '$bggId:$quality';
      _progress = 0;
    });
    try {
      await OpsService.uploadSharedVideo(
        bggId: bggId,
        title: title,
        quality: quality,
        bytes: v.bytes,
        meta: {
          'width': info.width,
          'height': info.height,
          'fps': info.fps,
          'durationSec': info.durationSec,
          'videoCodec': info.videoCodec,
        },
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      _snack('BGG #$bggId ${quality}p 공용 영상을 올렸어요. (${v.sizeMB.toStringAsFixed(1)}MB) '
          '패드에는 다음 날부터, 또는 매장이 "손님 앱 새로고침"을 누르면 보여요.');
      _bggId.clear();
      _title.clear();
      await _load();
    } catch (e) {
      _snack('영상을 올리지 못했어요: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _delete(Map<String, dynamic> v) async {
    final bggId = v['bggId'].toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('공용 영상 지우기'),
        content: Text("'${v['title'] ?? ''}' (BGG #$bggId) 공용 영상(1080p·720p)을 지울까요?\n"
            '이 영상을 쓰던 모든 매장 패드에서 안 나와요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD64545), foregroundColor: Colors.white),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await OpsService.deleteSharedVideo(bggId);
      _snack('지웠어요.');
      await _load();
    } catch (e) {
      _snack('지우지 못했어요: $e', error: true);
    }
  }

  String _mb(num? bytes) => '${((bytes ?? 0) / 1048576).toStringAsFixed(0)}MB';

  String _qualityText(Map<String, dynamic> v, String q) {
    final x = v['q$q'];
    if (x is! Map) return '${q}p 없음';
    final d = (x['durationSec'] as num?)?.toDouble();
    return '${q}p ${_mb(x['sizeBytes'] as num?)}${d != null ? ' · ${d ~/ 60}분 ${(d % 60).round()}초' : ''}';
  }

  Widget _uploadButton(String bggId, String title, String quality, {String? label}) {
    final busy = _busyKey == '$bggId:$quality';
    if (busy) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('올리는 중 ${(_progress * 100).toStringAsFixed(0)}%'),
      );
    }
    return TextButton.icon(
      onPressed: _busyKey != null ? null : () => _upload(bggId, title, quality),
      icon: const Icon(Icons.upload, size: 18),
      label: Text(label ?? '${quality}p 올리기'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gb = _totalBytes / (1024 * 1024 * 1024);
    final monthly = (gb - 10).clamp(0, double.infinity) * 0.015; // R2 저장 $0.015/GB·월, 10GB 무료 (전송 무료)
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('공용 룰 영상', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          'BGG 번호 기준으로 한 번만 올리면, 그 게임이 있는 모든 매장 패드에서 재생돼요. 매장이 직접 올린 영상이 있으면 그게 먼저예요.\n'
          '패드는 게임 목록을 하루 1번만 받아서, 새 영상은 다음 날부터(또는 매장이 "손님 앱 새로고침"을 누르면 바로) 보여요.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Text('공용 영상 ${_videos.length}개 게임 · ${gb.toStringAsFixed(1)}GB · R2 저장비 약 \$${monthly.toStringAsFixed(2)}/월 (매장 영상 제외)',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _bggId,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'BGG 번호', hintText: '예: 13', border: OutlineInputBorder()),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: '게임 이름 (목록 표시용)', border: OutlineInputBorder()),
                  ),
                ),
                ListenableBuilder(
                  listenable: Listenable.merge([_bggId, _title]),
                  builder: (context, _) => Wrap(children: [
                    _uploadButton(_bggId.text.trim(), _title.text.trim(), '1080'),
                    _uploadButton(_bggId.text.trim(), _title.text.trim(), '720', label: '720p 올리기 (선택)'),
                  ]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('매장 영상을 공용으로 옮기기', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _moveStore,
                    decoration: const InputDecoration(labelText: '매장 아이디', border: OutlineInputBorder()),
                  ),
                ),
                _moving
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : OutlinedButton.icon(
                        onPressed: _busyKey != null ? null : _moveFromStore,
                        icon: const Icon(Icons.drive_file_move_outline, size: 18),
                        label: const Text('미리 보기'),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (_error != null)
          Row(children: [
            Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFD64545)))),
            TextButton(onPressed: _load, child: const Text('다시')),
          ])
        else if (_videos.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('아직 올린 공용 영상이 없어요.'))
        else
          Card(
            child: Column(children: [
              for (final v in _videos)
                ListTile(
                  title: Text("${(v['title'] ?? '').toString().isEmpty ? '(이름 없음)' : v['title']}  ·  BGG #${v['bggId']}"),
                  subtitle: Text('${_qualityText(v, '1080')}   /   ${_qualityText(v, '720')}'),
                  trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    _uploadButton(v['bggId'].toString(), (v['title'] ?? '').toString(), '1080', label: '1080p 바꾸기'),
                    _uploadButton(v['bggId'].toString(), (v['title'] ?? '').toString(), '720',
                        label: v['q720'] is Map ? '720p 바꾸기' : '720p 올리기'),
                    IconButton(
                      tooltip: '지우기',
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFD64545)),
                      onPressed: _busyKey != null ? null : () => _delete(v),
                    ),
                  ]),
                ),
            ]),
          ),
      ],
    );
  }
}
