import 'dart:async';
import 'dart:math' as math;

import 'package:boardpad/widgets/app_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_store_settings_screen.dart';
import 'admin_home_layout_screen.dart';

import 'package:boardpad/services/bgg_service.dart';
import 'package:boardpad/services/rule_video_service.dart';
import 'package:boardpad/utils/mp4_info.dart';
import 'package:boardpad/utils/game_meta.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';
import 'package:boardpad/widgets/admin_colors.dart';
import 'package:boardpad/widgets/game_admin/game_edit_dialog.dart';
import 'package:boardpad/widgets/game_admin/game_form.dart';
import 'admin_event_manage_screen.dart';
import 'admin_menu_manage_screen.dart';
import 'admin_notice_manage_screen.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/usage_meter.dart';

typedef GameDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// 보드게임 관리 (관리자 웹)
/// 월정액권 앱의 게임 관리 기능을 옮겨 온 화면:
///  - 1개 추가: BGG geek ID 조회 / 이름 검색으로 인원·추천 인원·weight·순위·사진 자동 채우기
///  - 대용량 추가: geek ID 목록(CSV/엑셀 붙여넣기)으로 한꺼번에 등록
///  - 매장 추천 순서 정하기, 장르 여러 개, 난이도 색 배지, NEW 배지, 확장판, 룰북 이미지
class AdminGameManageScreen extends StatefulWidget {
  const AdminGameManageScreen({super.key});

  @override
  State<AdminGameManageScreen> createState() => _AdminGameManageScreenState();
}

class _BulkResult {
  final String geekId;
  final bool ok;
  final String text;
  _BulkResult(this.geekId, this.ok, this.text);
}

class _AdminGameManageScreenState extends State<AdminGameManageScreen> {
  static const int _bulkMax = 300;
  static const int _bulkChunk = 20;
  static const int _itemsPerPage = 10;

  final CollectionReference<Map<String, dynamic>> _gamesRef = StoreScope.col('games');

  // 목록 필터
  String _searchQuery = '';
  String _genreFilter = '전체';
  bool _pickedOnly = false;
  int _currentPage = 1;

  // 장르
  List<String> _genreList = [];
  StreamSubscription<DocumentSnapshot>? _genreSubscription;

  // 1개 추가
  final GameForm _addForm = GameForm();
  bool _addBusy = false;
  String? _addError;
  String? _addNote;

  // 대용량 추가
  final TextEditingController _bulkCtrl = TextEditingController();
  bool _bulkMarkNew = false;
  bool _bulkRunning = false;

  // BGG 플레이 시간으로 소요시간 전체 채우기
  bool _timeFillRunning = false;
  String? _timeFillProgress;
  String? _timeFillResult;
  String? _bulkError;
  String? _bulkProgress;
  List<_BulkResult> _bulkResults = [];

  // 한 게임에 대한 작업이 진행 중인지 (BGG 갱신 등)
  final Set<String> _rowBusy = {};
  final Map<String, double> _videoProgress = {}; // 룰 영상 올리는 중 (문서 id → 0~1)
  final Map<String, int> _videoPlays = {}; // 룰 영상 재생 횟수 (videoStats, 서버가 기록)

  @override
  void initState() {
    super.initState();
    _genreSubscription = StoreScope.col('settings').doc('genres').snapshots().listen((snap) {
      if (mounted) {
        setState(() {
          _genreList = snap.exists ? List<String>.from((snap.data() as Map? ?? {})['items'] ?? []) : [];
        });
      }
    });
    _loadVideoPlays();
  }

  // 룰 영상 재생 횟수 (화면 열 때 한 번만 읽음)
  Future<void> _loadVideoPlays() async {
    try {
      final snap = await StoreScope.col('videoStats').get();
      if (!mounted) return;
      setState(() {
        for (final d in snap.docs) {
          _videoPlays[d.id] = asInt(d.data()['plays']) ?? 0;
        }
      });
    } catch (_) {
      // 보안 규칙(videoStats 읽기)을 배포하기 전이면 권한이 없음 → 횟수만 안 보임
    }
  }

  @override
  void dispose() {
    _genreSubscription?.cancel();
    _addForm.dispose();
    _bulkCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : kAdminAccent,
    ));
  }

  // ───────────────────────── 장르 관리 ─────────────────────────
  Future<void> _addGenre(String name) async {
    if (name.trim().isEmpty) return;
    await StoreScope.col('settings').doc('genres').set(
      {'items': FieldValue.arrayUnion([name.trim()])},
      SetOptions(merge: true),
    );
  }

  Future<void> _deleteGenre(String name) async {
    await StoreScope.col('settings').doc('genres').update({'items': FieldValue.arrayRemove([name])});
  }

  Future<void> _editGenre(String oldName, String newName) async {
    final nn = newName.trim();
    if (nn.isEmpty || nn == oldName) return;
    final genresRef = StoreScope.col('settings').doc('genres');
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final doc = await transaction.get(genresRef);
      final items = List<String>.from((doc.data() as Map? ?? {})['items'] ?? []);
      final idx = items.indexOf(oldName);
      if (idx == -1) return;
      items[idx] = nn;
      transaction.update(genresRef, {'items': items});
    });

    // 그 장르를 가진 게임도 같이 바꿈 (새 방식 genres 목록 + 예전 방식 genre 하나 모두)
    final byList = await _gamesRef.where('genres', arrayContains: oldName).get();
    final byOld = await _gamesRef.where('genre', isEqualTo: oldName).get();
    final docs = <String, GameDoc>{for (final d in [...byList.docs, ...byOld.docs]) d.id: d};
    if (docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final d in docs.values) {
      final next = gameGenres(d.data()).map((g) => g == oldName ? nn : g).toSet().toList();
      batch.update(d.reference, {'genres': next, 'genre': next.isNotEmpty ? next.first : ''});
    }
    await batch.commit();
  }

  void _showGenreManageDialog() {
    final addCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final genreList = _genreList;
          return AlertDialog(
            title: const Text('장르 관리', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (genreList.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('등록된 장르가 없습니다.', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: genreList.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final g = genreList[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            title: Text(g),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                  tooltip: '수정',
                                  onPressed: () async {
                                    final editCtrl = TextEditingController(text: g);
                                    await showDialog(
                                      context: ctx,
                                      builder: (ectx) => AlertDialog(
                                        title: const Text('장르 수정', style: TextStyle(fontWeight: FontWeight.bold)),
                                        content: TextField(controller: editCtrl, autofocus: true, decoration: adminInput('장르 이름')),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ectx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                                          ElevatedButton(
                                            onPressed: () async {
                                              await _editGenre(g, editCtrl.text);
                                              if (ectx.mounted) Navigator.pop(ectx);
                                            },
                                            style: ElevatedButton.styleFrom(backgroundColor: kAdminAccent, foregroundColor: Colors.white),
                                            child: const Text('저장'),
                                          ),
                                        ],
                                      ),
                                    );
                                    editCtrl.dispose();
                                    setDlg(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  tooltip: '삭제',
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: ctx,
                                      builder: (dctx) => AlertDialog(
                                        title: const Text('장르 삭제', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                                        content: Text("'$g' 장르를 목록에서 지울까요? 이미 이 장르가 붙은 게임의 정보는 그대로 남아요."),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(dctx, true),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                            child: const Text('삭제'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) await _deleteGenre(g);
                                    setDlg(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: addCtrl,
                          decoration: adminInput('새 장르 이름'),
                          onSubmitted: (val) async {
                            if (val.trim().isEmpty) return;
                            await _addGenre(val);
                            addCtrl.clear();
                            setDlg(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          if (addCtrl.text.trim().isEmpty) return;
                          await _addGenre(addCtrl.text);
                          addCtrl.clear();
                          setDlg(() {});
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: kAdminAccent, foregroundColor: Colors.white),
                        child: const Text('추가'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))],
          );
        },
      ),
    ).whenComplete(addCtrl.dispose);
  }

  // ───────────────────────── 1개 추가 ─────────────────────────
  Future<void> _addLookup(String geekId) async {
    if (!RegExp(r'^\d+$').hasMatch(geekId)) {
      setState(() => _addError = 'BGG geek ID는 숫자로 입력해 주세요.');
      return;
    }
    setState(() {
      _addBusy = true;
      _addError = null;
      _addNote = 'BGG에서 가져오는 중… (조금 걸릴 수 있어요)';
    });
    try {
      final warn = await fillFormFromBgg(_addForm, geekId, refresh: () {
        if (mounted) setState(() {});
      });
      if (!mounted) return;
      setState(() => _addNote = warn ?? 'BGG 정보를 가져왔어요. 확인 후 "추가" 버튼을 눌러야 저장돼요.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addError = e.toString();
        _addNote = null;
      });
    } finally {
      if (mounted) setState(() => _addBusy = false);
    }
  }

  Future<void> _addSearch() async {
    final picked = await showDialog<BggSearchResult>(
      context: context,
      builder: (_) => BggSearchDialog(initialQuery: _addForm.name.text),
    );
    if (picked != null) await _addLookup(picked.id);
  }

  Future<void> _addGame(Set<String> registeredGeekIds) async {
    Map<String, dynamic> fields;
    try {
      fields = _addForm.toFields(_genreList);
    } on GameFormError catch (e) {
      setState(() => _addError = e.message);
      return;
    }
    final gid = fields['geekId'] as String?;
    if (gid != null && registeredGeekIds.contains(gid)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('이미 등록된 게임'),
          content: Text('BGG #$gid 게임이 이미 목록에 있어요. 그래도 하나 더 추가할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('추가')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _addBusy = true;
      _addError = null;
    });
    try {
      final (imageFields, _) = await _addForm.uploadImages();
      await _gamesRef.add({
        ...fields,
        'imageUrl': '',
        'rulebookImageUrl': '',
        ...imageFields,
        'isAvailable': true,
        'isRecommended': false,
        'newHidden': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _addForm.clear();
      if (!mounted) return;
      setState(() {
        _addBusy = false;
        _addNote = null;
      });
      _toast("'${fields['title']}' 게임을 추가했어요.");
    } catch (e) {
      debugPrint('Game add error: $e');
      if (!mounted) return;
      setState(() {
        _addBusy = false;
        _addError = '저장에 실패했어요. 다시 시도해 주세요.';
      });
    }
  }

  // ───────────────────────── 대용량 추가 ─────────────────────────
  /// CSV/엑셀 붙여넣기에서 geek ID를 뽑음. 첫 줄에 geekId 열 이름이 있으면 그 열, 없으면 각 줄의 첫 칸.
  List<String> _parseGeekIds(String text) {
    final lines = text.split(RegExp(r'\r\n|\n|\r')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return [];
    final sep = RegExp(r'[,\t;]');
    final header = lines.first.split(sep).map((h) => h.trim().replaceAll('"', '').toLowerCase()).toList();
    var col = header.indexOf('geekid');
    var start = 1;
    if (col == -1) {
      col = 0;
      start = 0;
    }
    final ids = <String>[];
    for (var i = start; i < lines.length; i++) {
      final cells = lines[i].split(sep);
      if (col < cells.length) {
        final raw = cells[col].trim().replaceAll('"', '');
        if (raw.isNotEmpty) ids.add(raw);
      }
    }
    return ids;
  }

  Future<void> _runBulk(Set<String> registeredGeekIds) async {
    final all = _parseGeekIds(_bulkCtrl.text);
    if (all.isEmpty) {
      setState(() => _bulkError = 'geek ID를 찾지 못했어요. 한 줄에 하나씩 붙여넣거나, 첫 줄에 geekId 열이 있는 CSV를 붙여넣어 주세요.');
      return;
    }
    final results = <_BulkResult>[];
    final seen = <String>{};
    final ids = <String>[];
    for (final id in all) {
      if (id.toLowerCase() == 'geekid') continue;
      if (!RegExp(r'^\d+$').hasMatch(id)) {
        results.add(_BulkResult(id, false, '숫자가 아니라서 건너뛰었어요.'));
        continue;
      }
      if (!seen.add(id)) continue;
      if (registeredGeekIds.contains(id)) {
        results.add(_BulkResult(id, false, '이미 등록된 게임이라 건너뛰었어요.'));
        continue;
      }
      ids.add(id);
    }
    if (ids.length > _bulkMax) {
      for (final id in ids.sublist(_bulkMax)) {
        results.add(_BulkResult(id, false, '한 번에 $_bulkMax개까지만 등록해요. 다음에 다시 올려 주세요.'));
      }
      ids.removeRange(_bulkMax, ids.length);
    }
    setState(() {
      _bulkRunning = true;
      _bulkError = null;
      _bulkResults = results;
      _bulkProgress = ids.isEmpty ? null : '0 / ${ids.length}';
    });

    var done = 0;
    void progress() {
      if (mounted) setState(() => _bulkProgress = '$done / ${ids.length}');
    }

    for (var i = 0; i < ids.length; i += _bulkChunk) {
      final chunk = ids.sublist(i, math.min(i + _bulkChunk, ids.length));
      BggDetailsResult r;
      try {
        r = await BggService.details(chunk);
      } catch (e) {
        for (final id in chunk) {
          results.add(_BulkResult(id, false, e.toString()));
        }
        done += chunk.length;
        progress();
        // 다시 해도 안 되는 오류(비밀번호·서버 미배포·설정 없음)면 멈춤
        if (e is BggException && (e.status == 401 || e.status == 404 || e.status == 503)) break;
        continue;
      }
      for (final id in r.missing) {
        results.add(_BulkResult(id, false, 'BGG에서 게임 정보를 찾지 못했어요.'));
        done++;
      }
      progress();
      for (final g in r.games) {
        try {
          final doc = await _gamesRef.add({
            'title': g.name,
            ...legacyGameFields(genres: const [], minPlayers: g.minPlayers, maxPlayers: g.maxPlayers, difficulty: difficultyFromWeight(g.weight)),
            'minPlayers': g.minPlayers,
            'maxPlayers': g.maxPlayers,
            'recommendedPlayers': g.recommendedPlayers,
            'weight': g.weight,
            'rank': g.rank,
            'geekId': g.geekId,
            'bggName': g.bggName,
            'time': g.playTimeText ?? '',
            'tags': '',
            'videoUrl': '',
            'pickNote': '',
            'expansion': false,
            'imageUrl': '',
            'rulebookImageUrl': '',
            'isAvailable': true,
            'isRecommended': false,
            'newHidden': !_bulkMarkNew,
            'timestamp': FieldValue.serverTimestamp(),
          });
          var photoNote = '';
          try {
            final img = await BggService.image(g.geekId);
            final url = await uploadGameImage(img.bytes, 'game_images', ext: img.extension);
            await doc.update({'imageUrl': url});
          } catch (_) {
            photoNote = ' (사진은 직접 올려 주세요)';
          }
          results.add(_BulkResult(g.geekId, true, '${g.name}$photoNote'));
        } catch (e) {
          debugPrint('Bulk add error: $e');
          results.add(_BulkResult(g.geekId, false, '등록에 실패했어요.'));
        }
        done++;
        progress();
      }
    }
    if (!mounted) return;
    final okCount = results.where((r) => r.ok).length;
    setState(() {
      _bulkRunning = false;
      _bulkResults = List.of(results);
    });
    _toast('대용량 추가 끝: $okCount개 등록, ${results.length - okCount}개 건너뜀/실패');
  }

  // ───────────────────────── 목록 행 동작 ─────────────────────────
  Future<void> _toggleGenre(GameDoc doc, String genre) async {
    final cur = gameGenres(doc.data());
    final next = cur.contains(genre) ? cur.where((x) => x != genre).toList() : [...cur, genre];
    final ordered = [..._genreList.where(next.contains), ...next.where((x) => !_genreList.contains(x))];
    await doc.reference.update({'genres': ordered, 'genre': ordered.isNotEmpty ? ordered.first : ''});
  }

  Future<void> _togglePick(GameDoc doc) async {
    final picked = doc.data()['isRecommended'] == true;
    await doc.reference.update({
      'isRecommended': !picked,
      'pickedAt': picked ? null : FieldValue.serverTimestamp(),
      'pickRank': null,
    });
    _toast(picked ? '매장 추천에서 뺐어요.' : '매장 추천에 올렸어요. 왼쪽 "매장 추천 순서"에서 순서를 바꿀 수 있어요.');
  }

  Future<void> _toggleNew(GameDoc doc) async {
    final hidden = doc.data()['newHidden'] == true;
    await doc.reference.update({'newHidden': !hidden});
  }

  Future<void> _refreshFromBgg(GameDoc doc) async {
    final data = doc.data();
    var geekId = (data['geekId'] ?? '').toString();
    if (geekId.isEmpty) {
      final picked = await showDialog<BggSearchResult>(
        context: context,
        builder: (_) => BggSearchDialog(initialQuery: (data['title'] ?? '').toString()),
      );
      if (picked == null) return;
      geekId = picked.id;
    }
    setState(() => _rowBusy.add(doc.id));
    try {
      final info = await BggService.lookup(geekId);
      final genres = gameGenres(data);
      final update = <String, dynamic>{
        'geekId': info.geekId,
        'bggName': info.bggName,
        'minPlayers': info.minPlayers,
        'maxPlayers': info.maxPlayers,
        'recommendedPlayers': info.recommendedPlayers,
        'weight': info.weight,
        'rank': info.rank,
        if (info.playTimeText != null) 'time': info.playTimeText,
        ...legacyGameFields(
          genres: genres,
          minPlayers: info.minPlayers,
          maxPlayers: info.maxPlayers,
          difficulty: difficultyFromWeight(info.weight) ?? (data['difficulty'] ?? '').toString(),
        ),
      };
      var photo = '사진도 바꿨어요.';
      try {
        final img = await BggService.image(geekId);
        final url = await uploadGameImage(img.bytes, 'game_images', ext: img.extension);
        update['imageUrl'] = url;
        await deleteStorageUrl((data['imageUrl'] ?? '').toString());
      } catch (_) {
        photo = '사진은 BGG에서 못 가져와서 그대로 두었어요.';
      }
      await doc.reference.update(update);
      _toast('BGG 정보로 갱신했어요. (게임 이름은 그대로) $photo');
    } catch (e) {
      _toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _rowBusy.remove(doc.id));
    }
  }

  Future<void> _uploadRulebook(GameDoc doc) async {
    final bytes = await pickImageBytes();
    if (bytes == null) return;
    setState(() => _rowBusy.add(doc.id));
    try {
      final url = await uploadGameImage(bytes, 'rulebook_images');
      final old = (doc.data()['rulebookImageUrl'] ?? '').toString();
      await doc.reference.update({'rulebookImageUrl': url});
      await deleteStorageUrl(old);
      _toast('룰북 이미지를 올렸어요.');
    } catch (e) {
      _toast('룰북 이미지를 올리지 못했어요.', error: true);
    } finally {
      if (mounted) setState(() => _rowBusy.remove(doc.id));
    }
  }

  // ── 룰 영상 (Cloudflare R2) ──
  /// quality: '1080'(기본) 또는 '720'(느린 인터넷용, 선택). 41차 규격: 1080p 30fps H.264 MP4
  Future<void> _uploadRuleVideo(GameDoc doc, String quality) async {
    final v = await pickVideoFile();
    if (v == null) return;
    final info = Mp4Info.parse(v.bytes);
    final check = checkRuleVideo(info, quality: quality, sizeBytes: v.bytes.length, maxBytes: ruleVideoMaxBytes);
    if (!check.ok || check.warnings.isNotEmpty) {
      final go = await _showVideoCheck(v.name, info, check);
      if (go != true) return;
    }
    setState(() {
      _rowBusy.add(doc.id);
      _videoProgress[doc.id] = 0;
    });
    try {
      await RuleVideoService.upload(
        gameId: doc.id,
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
          if (mounted) setState(() => _videoProgress[doc.id] = p);
        },
      );
      _toast('${quality}p 룰 영상을 올렸어요. (${v.sizeMB.toStringAsFixed(1)}MB · ${info.summary}) '
          '패드에 바로 보이게 하려면 "손님 앱 새로고침"');
    } catch (e) {
      _toast('영상을 올리지 못했어요: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _rowBusy.remove(doc.id);
          _videoProgress.remove(doc.id);
        });
      }
    }
  }

  /// 규격 검사 결과 보여 주기. 문제(errors)가 있으면 닫기만, 확인할 것(warnings)만 있으면 "그래도 올리기"
  Future<bool?> _showVideoCheck(String name, Mp4Info info, RuleVideoCheck check) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(check.ok ? '영상 확인' : '올릴 수 없는 영상이에요',
            style: TextStyle(fontWeight: FontWeight.bold, color: check.ok ? Colors.orange.shade800 : Colors.redAccent)),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (info.summary.isNotEmpty) Text(info.summary, style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 12),
              for (final e in check.errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('✕ $e', style: const TextStyle(color: Colors.redAccent)),
                ),
              for (final w in check.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $w', style: TextStyle(color: Colors.orange.shade900)),
                ),
              const SizedBox(height: 4),
              const Text('규격: 1920×1080 · 30fps · H.264 · AAC · MP4 (HandBrake "Fast 1080p30" + Web Optimized)',
                  style: TextStyle(color: Colors.black45, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(check.ok ? '취소' : '닫기')),
          if (check.ok)
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: kAdminAccent, foregroundColor: Colors.white),
              child: const Text('그래도 올리기'),
            ),
        ],
      ),
    );
  }

  /// quality: '1080' / '720' / 'all'
  Future<void> _removeRuleVideo(GameDoc doc, String quality) async {
    final title = (doc.data()['title'] ?? '이 게임').toString();
    final what = quality == 'all' ? '룰 영상(전부)' : '${quality}p 영상';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('룰 영상 삭제', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text("'$title'의 $what을 지울까요?\n저장소의 파일도 함께 지워져요."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _rowBusy.add(doc.id));
    try {
      await RuleVideoService.remove(doc.id, quality: quality);
      _toast('$what을 지웠어요.');
    } catch (e) {
      _toast('영상을 지우지 못했어요: $e', error: true);
    } finally {
      if (mounted) setState(() => _rowBusy.remove(doc.id));
    }
  }

  // 예전 방식(Firebase Storage, ruleVideoUrl)으로 올린 영상 지우기 — 41차 기준 0개지만 남아 있을 때를 위해
  Future<void> _removeLegacyVideo(GameDoc doc) async {
    final old = (doc.data()['ruleVideoUrl'] ?? '').toString();
    await doc.reference.update({'ruleVideoUrl': ''});
    await deleteStorageUrl(old);
    _toast('예전 매장 영상(Firebase)을 지웠어요.');
  }

  Future<void> _removeRulebook(GameDoc doc) async {
    final old = (doc.data()['rulebookImageUrl'] ?? '').toString();
    await doc.reference.update({'rulebookImageUrl': ''});
    await deleteStorageUrl(old);
    _toast('룰북 이미지를 지웠어요.');
  }

  Future<void> _confirmDelete(GameDoc doc) async {
    final data = doc.data();
    final title = (data['title'] ?? '이 게임').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게임 삭제', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
        content: Text("'$title' 게임을 정말 삭제할까요?\n삭제하면 되돌릴 수 없어요."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // 저장소(R2)의 룰 영상 파일부터 지움. 실패하면 파일이 주인 없이 남지 않게 게임 삭제를 멈춤
    if (RuleVideoService.hasVideo(data)) {
      try {
        await RuleVideoService.remove(doc.id);
      } catch (e) {
        _toast('룰 영상 파일을 지우지 못해서 게임 삭제를 멈췄어요: $e', error: true);
        return;
      }
    }
    try {
      await deleteStorageUrl((data['imageUrl'] ?? '').toString());
      await deleteStorageUrl((data['rulebookImageUrl'] ?? '').toString());
      await deleteStorageUrl((data['ruleVideoUrl'] ?? '').toString());
      await doc.reference.delete();
      _toast('삭제했어요.');
    } catch (e) {
      _toast('삭제에 실패했어요. 다시 시도해 주세요.', error: true);
    }
  }

  Future<void> _openEdit(GameDoc doc) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GameEditDialog(docId: doc.id, data: doc.data(), genreList: _genreList),
    );
    if (saved == true) _toast('수정했어요.');
  }

  // ───────────────────────── 매장 추천 순서 ─────────────────────────
  List<GameDoc> _sortedPicks(List<GameDoc> all) {
    final picks = all.where((d) => d.data()['isRecommended'] == true).toList();
    picks.sort((a, b) {
      final ra = asInt(a.data()['pickRank']);
      final rb = asInt(b.data()['pickRank']);
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      final ta = a.data()['pickedAt'];
      final tb = b.data()['pickedAt'];
      if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
      return 0;
    });
    return picks;
  }

  Future<void> _movePick(List<GameDoc> picks, int index, int delta) async {
    final j = index + delta;
    if (j < 0 || j >= picks.length) return;
    final list = List<GameDoc>.of(picks);
    final tmp = list[index];
    list[index] = list[j];
    list[j] = tmp;
    final batch = FirebaseFirestore.instance.batch();
    for (var i = 0; i < list.length; i++) {
      batch.update(list[i].reference, {'pickRank': i + 1});
    }
    await batch.commit();
  }

  // ───────────────────────── 화면 ─────────────────────────
  Widget _card({required String title, String? subtitle, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 13))),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildAddCard(Set<String> registeredGeekIds) {
    return _card(
      title: '게임 추가 (1개)',
      subtitle: 'BGG geek ID를 알면 바로 조회하고, 모르면 이름으로 검색해서 골라 주세요. 인원·추천 인원·난이도·사진이 자동으로 채워져요. (직접 입력해도 돼요)',
      children: [
        GeekIdRow(
          form: _addForm,
          busy: _addBusy,
          onLookup: () => _addLookup(_addForm.geekId.text.trim()),
          onSearch: _addSearch,
        ),
        if (_addNote != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_addNote!, style: const TextStyle(color: Colors.black54, fontSize: 12))),
        const SizedBox(height: 16),
        GameFormFields(form: _addForm, genreList: _genreList),
        if (_addError != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_addError!, style: const TextStyle(color: Colors.redAccent))),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: _addBusy
                  ? null
                  : () => setState(() {
                        _addForm.clear();
                        _addError = null;
                        _addNote = null;
                      }),
              child: const Text('입력 지우기', style: TextStyle(color: Colors.grey)),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _addBusy ? null : () => _addGame(registeredGeekIds),
              style: ElevatedButton.styleFrom(backgroundColor: kAdminAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
              child: _addBusy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('추가', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }

  // ───────────────────────── 소요시간 전체 채우기 ─────────────────────────

  /// geek ID가 있는 모든 게임의 소요시간을 BGG 플레이 시간으로 덮어씀.
  /// geek ID가 없거나 BGG에 시간이 없는 게임은 그대로 둠.
  Future<void> _fillAllTimes(List<GameDoc> all) async {
    String idOf(GameDoc d) => (d.data()['geekId'] ?? '').toString().trim();
    final targets = all.where((d) => RegExp(r'^\d+$').hasMatch(idOf(d))).toList();
    final noId = all.length - targets.length;
    final rounds = (targets.length / _bulkChunk).ceil();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('소요시간을 BGG 시간으로 바꿀까요?'),
        content: Text('geek ID가 있는 게임 ${targets.length}개의 소요시간을 BGG 플레이 시간(박스 기준)으로 바꿔요.\n'
            '지금 적힌 소요시간은 덮어써요. geek ID가 없는 $noId개와 BGG에 시간이 없는 게임은 그대로 둬요.\n\n'
            '약 ${(rounds * 5 / 60).ceil()}분 걸려요. 그동안 이 화면을 닫지 마세요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kAdminNavy, foregroundColor: Colors.white),
            child: const Text('바꾸기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _timeFillRunning = true;
      _timeFillResult = null;
      _timeFillProgress = '0 / ${targets.length}';
    });
    var updated = 0, noTime = 0, failed = 0, done = 0;
    String? stopReason;
    for (var i = 0; i < targets.length; i += _bulkChunk) {
      final chunk = targets.sublist(i, math.min(i + _bulkChunk, targets.length));
      final ids = chunk.map(idOf).toSet().toList();
      BggDetailsResult? r;
      for (var attempt = 0; attempt < 3 && r == null; attempt++) {
        try {
          r = await BggService.details(ids);
        } catch (e) {
          // 너무 자주 불러서 막혔으면(429) 잠깐 쉬고 다시
          if (e is BggException && e.status == 429 && attempt < 2) {
            await Future.delayed(const Duration(seconds: 30));
            continue;
          }
          if (e is BggException && (e.status == 401 || e.status == 404 || e.status == 503)) stopReason = e.toString();
          break;
        }
      }
      if (r == null) {
        failed += chunk.length;
      } else {
        final byId = {for (final g in r.games) g.geekId: g};
        final batch = FirebaseFirestore.instance.batch();
        var writes = 0;
        for (final d in chunk) {
          final t = byId[idOf(d)]?.playTimeText;
          if (t == null) {
            noTime++;
            continue;
          }
          batch.update(d.reference, {'time': t});
          writes++;
        }
        try {
          if (writes > 0) await batch.commit();
          updated += writes;
        } catch (_) {
          failed += writes;
        }
      }
      done += chunk.length;
      if (mounted) setState(() => _timeFillProgress = '$done / ${targets.length}');
      if (stopReason != null) break;
      // 서버 제한(1분에 15번)에 걸리지 않게 조금씩 쉬면서
      if (i + _bulkChunk < targets.length) await Future.delayed(const Duration(milliseconds: 4500));
    }

    // 손님 앱 게임 목록 새로고침
    if (updated > 0) {
      await StoreScope.col('settings')
          .doc('appRefresh')
          .set({'gamesUpdatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
    final summary = '$updated개 바꿈 · BGG에 시간 없음 $noTime개 · 실패 $failed개 · geek ID 없음 $noId개'
        '${stopReason != null ? '\n멈춘 이유: $stopReason' : ''}';
    if (!mounted) return;
    setState(() {
      _timeFillRunning = false;
      _timeFillResult = summary;
    });
    _toast('소요시간 채우기 끝: $updated개 바꿈', error: failed > 0 || stopReason != null);
  }

  Widget _buildTimeFillCard(List<GameDoc> all) {
    return _card(
      title: '소요시간 BGG로 채우기',
      subtitle: 'geek ID가 있는 모든 게임의 소요시간을 BGG 플레이 시간(박스 기준, 예: 30~60분)으로 바꿔요. '
          '새로 추가하거나 BGG로 다시 불러온 게임은 자동으로 채워져요.',
      children: [
        Row(
          children: [
            if (_timeFillRunning && _timeFillProgress != null)
              Text('바꾸는 중… $_timeFillProgress', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton(
              onPressed: _timeFillRunning ? null : () => _fillAllTimes(all),
              style: ElevatedButton.styleFrom(backgroundColor: kAdminNavy, foregroundColor: Colors.white),
              child: _timeFillRunning
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('전체 채우기'),
            ),
          ],
        ),
        if (_timeFillResult != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_timeFillResult!, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
      ],
    );
  }

  Widget _buildBulkCard(Set<String> registeredGeekIds) {
    final okCount = _bulkResults.where((r) => r.ok).length;
    return _card(
      title: '게임 대용량 추가',
      subtitle: '엑셀에서 geekId 열을 복사해 붙여넣거나, CSV 내용을 그대로 붙여넣어 주세요. (첫 줄에 geekId 열 이름이 있으면 그 열을, 없으면 각 줄의 첫 칸을 써요. 한 번에 최대 $_bulkMax개)',
      children: [
        TextField(
          controller: _bulkCtrl,
          enabled: !_bulkRunning,
          minLines: 4,
          maxLines: 8,
          decoration: adminInput('geek ID 목록', hint: '13\n822\n30549'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _bulkMarkNew,
          onChanged: _bulkRunning ? null : (v) => setState(() => _bulkMarkNew = v ?? false),
          title: const Text('새로 들어온 게임으로 표시 (30일간 NEW 배지)'),
        ),
        if (_bulkError != null) Text(_bulkError!, style: const TextStyle(color: Colors.redAccent)),
        Row(
          children: [
            if (_bulkProgress != null) Text(_bulkRunning ? '등록 중… $_bulkProgress' : '끝: $okCount개 등록', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton(
              onPressed: _bulkRunning ? null : () => _runBulk(registeredGeekIds),
              style: ElevatedButton.styleFrom(backgroundColor: kAdminNavy, foregroundColor: Colors.white),
              child: _bulkRunning
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('일괄 등록'),
            ),
          ],
        ),
        if (_bulkRunning)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('BGG 조회가 느려서 시간이 걸려요. 이 화면을 닫지 말고 기다려 주세요.', style: TextStyle(color: Colors.black54, fontSize: 12)),
          ),
        if (_bulkResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 10),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              children: _bulkResults
                  .map((r) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('${r.ok ? '✓' : '✗'} #${r.geekId}  ${r.text}',
                            style: TextStyle(fontSize: 12, color: r.ok ? Colors.black87 : Colors.redAccent)),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildPicksCard(List<GameDoc> picks) {
    return _card(
      title: '매장 추천 순서',
      subtitle: picks.isEmpty
          ? '오른쪽 목록에서 ★ 버튼을 누르면 매장 추천에 올라가요. (손님 앱 "추천" 탭)'
          : '위에 있을수록 먼저 보여요. 화살표로 순서를 바꿔 주세요.',
      children: [
        for (var i = 0; i < picks.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
            child: Row(
              children: [
                SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: kAdminAccent))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((picks[i].data()['title'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                      if ((picks[i].data()['pickNote'] ?? '').toString().isNotEmpty)
                        Text(picks[i].data()['pickNote'].toString(), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: '위로',
                  onPressed: i == 0 ? null : () => _movePick(picks, i, -1),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  tooltip: '아래로',
                  onPressed: i == picks.length - 1 ? null : () => _movePick(picks, i, 1),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _badge(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      );

  Widget _buildGameRow(GameDoc doc) {
    final g = doc.data();
    final title = (g['title'] ?? '').toString();
    final genres = gameGenres(g);
    final bool available = g['isAvailable'] != false;
    final picked = g['isRecommended'] == true;
    final busy = _rowBusy.contains(doc.id);
    final mn = asInt(g['minPlayers']);
    final mx = asInt(g['maxPlayers']);
    final w = asDouble(g['weight']);
    final rank = asInt(g['rank']);
    final geekId = (g['geekId'] ?? '').toString();
    final difficulty = difficultyFromWeight(w) ?? (g['difficulty'] ?? '').toString();
    final hasRulebook = (g['rulebookImageUrl'] ?? '').toString().isNotEmpty;
    final hasLegacyVideo = (g['ruleVideoUrl'] ?? '').toString().isNotEmpty;
    final r2Videos = RuleVideoService.videosOf(g);
    final plays = _videoPlays[doc.id] ?? 0;
    final hasYoutube = (g['videoUrl'] ?? '').toString().trim().isNotEmpty;
    final videoProgress = _videoProgress[doc.id];
    final imageUrl = (g['imageUrl'] ?? '').toString();

    final sub = <String>[
      if (mn != null) playersText(mn, mx) else if ((g['players'] ?? '').toString().isNotEmpty) g['players'].toString(),
      if ((g['recommendedPlayers'] ?? '').toString().isNotEmpty) '추천 ${g['recommendedPlayers']}명',
      if (w != null) 'weight ${w.toStringAsFixed(2)}',
      if (rank != null) '긱 순위 #$rank',
      if (geekId.isNotEmpty) 'BGG #$geekId',
      if ((g['time'] ?? '').toString().isNotEmpty) g['time'].toString(),
      if (hasRulebook) '룰북 있음',
      if (videoProgress != null)
        '영상 올리는 중 ${(videoProgress * 100).toStringAsFixed(0)}%'
      else if (r2Videos.isNotEmpty)
        '룰 영상 ${r2Videos.keys.map((q) => '${q}p').join('·')}${plays > 0 ? ' · 재생 $plays회' : ''}'
      else if (hasLegacyVideo)
        '매장 영상 있음 (예전 방식)'
      else if (hasYoutube)
        '유튜브 영상',
    ];

    return Opacity(
      opacity: available ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.hardEdge,
              child: hasValidImage(imageUrl)
                  ? AppNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover, errorWidget: (c, u, e) => const Icon(Icons.image, color: Colors.grey))
                  : const Icon(Icons.casino, color: Colors.grey),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                      if (picked) _badge('매장 추천', Colors.amber.shade700),
                      if (isNewGame(g)) _badge('NEW', Colors.redAccent),
                      if (g['expansion'] == true) _badge('확장판', Colors.blueGrey),
                      if (!available) _badge('숨김', Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(sub.join(' · '), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      ..._genreList.map((x) {
                        final on = genres.contains(x);
                        return InkWell(
                          onTap: () => _toggleGenre(doc, x),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: on ? kAdminAccent : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: on ? kAdminAccent : Colors.grey.shade300),
                            ),
                            child: Text(x, style: TextStyle(fontSize: 11, color: on ? Colors.white : Colors.black54)),
                          ),
                        );
                      }),
                      // 장르 목록에서는 지워졌지만 게임에 남아 있는 장르
                      ...genres.where((x) => !_genreList.contains(x)).map((x) => Chip(
                            label: Text(x, style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          )),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            DifficultyBadge(label: difficulty),
            const SizedBox(width: 12),
            if (busy)
              const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            else ...[
              Tooltip(
                message: available ? '이용 가능 (끄면 손님 앱에서 숨김)' : '숨김 (분실·수리 등)',
                child: Switch(
                  value: available,
                  activeTrackColor: kAdminAccent,
                  onChanged: (v) => doc.reference.update({'isAvailable': v}),
                ),
              ),
              IconButton(
                icon: Icon(picked ? Icons.star : Icons.star_border, color: picked ? Colors.amber.shade700 : Colors.grey),
                tooltip: picked ? '매장 추천 해제' : '매장 추천',
                onPressed: () => _togglePick(doc),
              ),
              IconButton(icon: const Icon(Icons.edit, color: Colors.blue), tooltip: '수정', onPressed: () => _openEdit(doc)),
              PopupMenuButton<String>(
                tooltip: '더 보기',
                onSelected: (v) {
                  switch (v) {
                    case 'bgg':
                      _refreshFromBgg(doc);
                      break;
                    case 'rulebook':
                      _uploadRulebook(doc);
                      break;
                    case 'rulebook-del':
                      _removeRulebook(doc);
                      break;
                    case 'video1080':
                      _uploadRuleVideo(doc, '1080');
                      break;
                    case 'video720':
                      _uploadRuleVideo(doc, '720');
                      break;
                    case 'video720-del':
                      _removeRuleVideo(doc, '720');
                      break;
                    case 'video-del':
                      _removeRuleVideo(doc, 'all');
                      break;
                    case 'legacy-video-del':
                      _removeLegacyVideo(doc);
                      break;
                    case 'new':
                      _toggleNew(doc);
                      break;
                    case 'delete':
                      _confirmDelete(doc);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'bgg', child: Text(geekId.isEmpty ? 'BGG에서 찾아 정보·사진 채우기' : 'BGG 정보·사진 다시 가져오기')),
                  PopupMenuItem(value: 'rulebook', child: Text(hasRulebook ? '룰북 이미지 바꾸기' : '룰북 이미지 올리기')),
                  if (hasRulebook) const PopupMenuItem(value: 'rulebook-del', child: Text('룰북 이미지 삭제')),
                  PopupMenuItem(value: 'video1080', child: Text(r2Videos.containsKey('1080') ? '룰 영상 바꾸기 (1080p)' : '룰 영상 올리기 (1080p)')),
                  PopupMenuItem(
                      value: 'video720',
                      child: Text(r2Videos.containsKey('720') ? '720p 영상 바꾸기 (느린 인터넷용)' : '720p 영상 추가 (느린 인터넷용, 선택)')),
                  if (r2Videos.containsKey('720')) const PopupMenuItem(value: 'video720-del', child: Text('720p 영상 삭제')),
                  if (r2Videos.isNotEmpty) const PopupMenuItem(value: 'video-del', child: Text('룰 영상 삭제 (전부)')),
                  if (hasLegacyVideo) const PopupMenuItem(value: 'legacy-video-del', child: Text('예전 매장 영상(Firebase) 삭제')),
                  if (isNewEligible(g)) PopupMenuItem(value: 'new', child: Text(g['newHidden'] == true ? 'NEW 배지 다시 켜기' : 'NEW 배지 끄기')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'delete', child: Text('삭제', style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          selectedColor: kAdminAccent,
          labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
          onSelected: (_) => onTap(),
        ),
      );

  Widget _buildListCard(List<GameDoc> all) {
    final q = _searchQuery.trim().toLowerCase();
    final games = all.where((d) {
      final g = d.data();
      final title = (g['title'] ?? '').toString().toLowerCase();
      final bggName = (g['bggName'] ?? '').toString().toLowerCase();
      if (q.isNotEmpty && !title.contains(q) && !bggName.contains(q)) return false;
      if (_genreFilter != '전체' && !gameGenres(g).contains(_genreFilter)) return false;
      if (_pickedOnly && g['isRecommended'] != true) return false;
      return true;
    }).toList();

    final totalPages = math.max(1, (games.length + _itemsPerPage - 1) ~/ _itemsPerPage);
    final page = math.min(_currentPage, totalPages);
    final start = (page - 1) * _itemsPerPage;
    final pageGames = games.sublist(start, math.min(start + _itemsPerPage, games.length));
    final countText = games.length == all.length ? '${all.length}개' : '${games.length} / ${all.length}개';

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('등록된 게임 $countText', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        decoration: adminInput('게임 이름 검색').copyWith(prefixIcon: const Icon(Icons.search)),
                        onChanged: (v) => setState(() {
                          _searchQuery = v;
                          _currentPage = 1;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('전체', _genreFilter == '전체', () => setState(() {
                            _genreFilter = '전체';
                            _currentPage = 1;
                          })),
                      ..._genreList.map((x) => _filterChip(x, _genreFilter == x, () => setState(() {
                            _genreFilter = x;
                            _currentPage = 1;
                          }))),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('★ 매장 추천만'),
                        selected: _pickedOnly,
                        onSelected: (v) => setState(() {
                          _pickedOnly = v;
                          _currentPage = 1;
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: pageGames.isEmpty
                ? Center(child: Text(all.isEmpty ? '등록된 보드게임이 없어요. 왼쪽에서 추가해 주세요.' : '해당하는 게임이 없어요.', style: const TextStyle(color: Colors.grey)))
                : ListView.separated(
                    itemCount: pageGames.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _buildGameRow(pageGames[i]),
                  ),
          ),
          if (totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: page > 1 ? () => setState(() => _currentPage = page - 1) : null),
                  Text('$page / $totalPages', style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: page < totalPages ? () => setState(() => _currentPage = page + 1) : null),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Row(
        children: [
          AdminSidebar(
            currentScreen: 'game',
            onNavigate: (screen) {
              final targets = <String, Widget>{
                'store': const AdminStoreSettingsScreen(),
                'home': const AdminHomeLayoutScreen(),
                'menu': const AdminMenuManageScreen(),
                'event': const AdminEventManageScreen(),
                'notice': const AdminNoticeManageScreen(),
              };
              final target = targets[screen];
              if (target != null) {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(pageBuilder: (_, __, ___) => target, transitionDuration: Duration.zero, reverseTransitionDuration: Duration.zero),
                );
              }
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('보드게임 관리', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _showGenreManageDialog,
                        icon: const Icon(Icons.settings, size: 18),
                        label: const Text('장르 관리'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kAdminAccent,
                          side: const BorderSide(color: kAdminAccent),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await StoreScope.col('settings')
                              .doc('appRefresh')
                              .set({'gamesUpdatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                          _toast('손님 앱 게임 목록이 새로고침됩니다.');
                        },
                        icon: const Icon(Icons.sync),
                        label: const Text('손님 앱 새로고침', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAdminNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _gamesRef.orderBy('timestamp', descending: true).snapshots().metered(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(child: Text('게임 목록을 불러오지 못했어요: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
                        }
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                        final all = snapshot.data!.docs;
                        final registeredGeekIds = all.map((d) => (d.data()['geekId'] ?? '').toString()).where((x) => x.isNotEmpty).toSet();
                        final picks = _sortedPicks(all);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 460,
                              child: ListView(
                                children: [
                                  _buildAddCard(registeredGeekIds),
                                  _buildBulkCard(registeredGeekIds),
                                  _buildTimeFillCard(all),
                                  _buildPicksCard(picks),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: _buildListCard(all)),
                          ],
                        );
                      },
                    ),
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
