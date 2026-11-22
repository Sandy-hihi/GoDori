import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/mp4_info.dart';
import '../widgets/game_admin/game_form.dart' show pickVideoFile, PickedVideo;
import 'ops_service.dart';

/// 운영자 페이지 '매장 인트로 영상' 탭 (146차) — 서버 functions/src/video.js intro*
///
/// 매장마다 3~10초짜리 짧은 영상을 하나 올리면, 그 매장 패드에서 룰 설명 영상을 틀 때마다
/// 인트로가 먼저 나오고 끝나는 순간 룰 영상으로 바로 이어짐 (패드가 룰 영상을 미리 열어 둠).
/// 패드는 재생할 때마다 서버에서 주소를 받아서, 올리거나 지우면 1분 안에 모든 패드에 반영됨 (새로고침 필요 없음).
class OpsIntroVideosTab extends StatefulWidget {
  const OpsIntroVideosTab({super.key});

  @override
  State<OpsIntroVideosTab> createState() => _OpsIntroVideosTabState();
}

class _OpsIntroVideosTabState extends State<OpsIntroVideosTab> {
  static const int _maxBytes = 50 * 1024 * 1024; // 서버 INTRO_MAX_BYTES와 같게
  static const double _minSec = 3;
  static const double _maxSec = 10;

  List<Map<String, dynamic>> _stores = [];
  Map<String, Map<String, dynamic>> _intros = {};
  bool _loading = true;
  String? _error;
  String? _busyStore; // 올리는 중인 매장
  double _progress = 0;

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
      final stores = await OpsService.stores();
      final r = await OpsService.introVideos();
      final intros = <String, Map<String, dynamic>>{};
      final m = r['intros'];
      if (m is Map) {
        m.forEach((k, v) {
          if (v is Map) intros[k.toString()] = Map<String, dynamic>.from(v);
        });
      }
      if (!mounted) return;
      setState(() {
        // 가입 대기·거절 매장은 빼고 (운영 중·정지 매장만)
        _stores = stores.where((s) => s['status'] == 'active' || s['status'] == 'suspended').toList();
        _intros = intros;
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

  /// 인트로 영상 검사: 룰 영상 규격(MP4·H.264·30fps·1080p 이하) + 3~10초 + 50MB 이하
  RuleVideoCheck _check(Mp4Info info, int size) {
    final base = checkRuleVideo(info, quality: '1080', sizeBytes: size, maxBytes: _maxBytes);
    final errors = [...base.errors];
    // 인트로는 1080p가 아니어도 됨, 소리 없어도 됨 → 그 두 경고는 뺌
    final warnings = base.warnings.where((w) => !w.contains('1080p 칸인데') && !w.contains('소리가 없는')).toList();
    final d = info.durationSec;
    if (info.isMp4) {
      if (d == null) {
        errors.add('영상 길이를 읽지 못했어요. HandBrake로 MP4(H.264)로 다시 만들어 주세요.');
      } else if (d < _minSec - 0.5 || d > _maxSec + 0.5) {
        errors.add('인트로 영상은 ${_minSec.toInt()}~${_maxSec.toInt()}초로 만들어 주세요 (지금 ${d.toStringAsFixed(1)}초).');
      }
    }
    return RuleVideoCheck(errors, warnings);
  }

  Future<void> _upload(Map<String, dynamic> store) async {
    final storeId = store['id'].toString();
    final PickedVideo? v = await pickVideoFile();
    if (v == null) return;
    final info = Mp4Info.parse(v.bytes);
    final check = _check(info, v.bytes.length);
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
      _busyStore = storeId;
      _progress = 0;
    });
    try {
      await OpsService.uploadIntroVideo(
        storeId: storeId,
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
      _snack("${store['name'] ?? storeId} 인트로 영상을 올렸어요 (${v.sizeMB.toStringAsFixed(1)}MB). 1분 안에 모든 패드에 반영돼요.");
      await _load();
    } catch (e) {
      _snack('영상을 올리지 못했어요: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyStore = null);
    }
  }

  Future<void> _delete(Map<String, dynamic> store) async {
    final storeId = store['id'].toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('인트로 영상 지우기'),
        content: Text("${store['name'] ?? storeId} 매장의 인트로 영상을 지울까요?\n지우면 룰 영상이 인트로 없이 바로 나와요."),
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
      await OpsService.deleteIntroVideo(storeId);
      _snack('지웠어요.');
      await _load();
    } catch (e) {
      _snack('지우지 못했어요: $e', error: true);
    }
  }

  Future<void> _preview(String url) async {
    try {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (_) {
      _snack('미리 보기를 열지 못했어요.', error: true);
    }
  }

  String _infoText(Map<String, dynamic> it) {
    final d = (it['durationSec'] as num?)?.toDouble();
    final w = it['width'];
    final h = it['height'];
    final mb = ((it['sizeBytes'] as num?) ?? 0) / 1048576;
    final at = DateTime.tryParse((it['uploadedAt'] ?? '').toString())?.toLocal();
    return [
      if (d != null) '${d.toStringAsFixed(1)}초',
      if (w != null && h != null) '$w×$h',
      '${mb.toStringAsFixed(1)}MB',
      if (at != null) '${at.year}.${at.month}.${at.day} 올림',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          const Expanded(child: Text('매장 인트로 영상', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          IconButton(tooltip: '새로고침', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 6),
        const Text(
          '매장마다 3~10초짜리 짧은 영상을 하나 올리면, 그 매장 패드에서 룰 설명 영상을 틀 때마다 인트로가 먼저 나오고 바로 룰 영상으로 이어져요.\n'
          '규격: MP4(H.264), 1920×1080 이하, 30fps, 50MB 이하, 가로 영상. 올리거나 지우면 1분 안에 모든 패드에 반영돼요.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (_error != null)
          Row(children: [
            Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFD64545)))),
            TextButton(onPressed: _load, child: const Text('다시')),
          ])
        else if (_stores.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('운영 중인 매장이 없어요.'))
        else
          Card(
            child: Column(children: [
              for (final s in _stores) _row(s),
            ]),
          ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final id = s['id'].toString();
    final it = _intros[id];
    final busy = _busyStore == id;
    return ListTile(
      leading: Icon(it != null ? Icons.movie_creation_rounded : Icons.movie_creation_outlined,
          color: it != null ? const Color(0xFFE8833A) : Colors.black26),
      title: Text("${s['name'] ?? id}  ·  $id${s['status'] == 'suspended' ? '  (정지)' : ''}"),
      subtitle: Text(it != null ? _infoText(it) : '인트로 없음 — 룰 영상이 바로 나와요'),
      trailing: busy
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('올리는 중 ${(_progress * 100).toStringAsFixed(0)}%'),
            )
          : Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (it != null && it['previewUrl'] is String)
                TextButton.icon(
                  onPressed: () => _preview(it['previewUrl'] as String),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('미리 보기'),
                ),
              TextButton.icon(
                onPressed: _busyStore != null ? null : () => _upload(s),
                icon: const Icon(Icons.upload, size: 18),
                label: Text(it != null ? '바꾸기' : '올리기'),
              ),
              if (it != null)
                IconButton(
                  tooltip: '지우기',
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFD64545)),
                  onPressed: _busyStore != null ? null : () => _delete(s),
                ),
            ]),
    );
  }
}
