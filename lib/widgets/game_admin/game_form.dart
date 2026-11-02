import 'dart:typed_data';

import 'package:boardpad/widgets/app_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:boardpad/services/bgg_service.dart';
import 'package:boardpad/utils/game_meta.dart';

const Color kAdminGreen = Color(0xFF00B37E);
const Color kAdminNavy = Color(0xFF1E2B3C);

class GameFormError implements Exception {
  final String message;
  GameFormError(this.message);
  @override
  String toString() => message;
}

// ── 사진 업로드/삭제 공통 ──
Future<String> uploadGameImage(Uint8List bytes, String folder, {String ext = 'jpg'}) async {
  final contentType = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
  final ref = FirebaseStorage.instance.ref().child('$folder/${DateTime.now().millisecondsSinceEpoch}.$ext');
  final task = await ref.putData(bytes, SettableMetadata(contentType: contentType));
  return task.ref.getDownloadURL();
}

Future<void> deleteStorageUrl(String? url) async {
  if (url == null || url.isEmpty) return;
  try {
    await FirebaseStorage.instance.refFromURL(url).delete();
  } catch (_) {}
}

Future<Uint8List?> pickImageBytes() async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 75);
  if (x == null) return null;
  return x.readAsBytes();
}

// ── 매장 룰 영상 (직접 만든 영상) ──
/// 손님 패드는 매장 영상(ruleVideoUrl)이 있으면 그걸 앱 안에서 틀고, 없으면 유튜브 링크(videoUrl)를 엶.
const int ruleVideoMaxMB = 300;

class PickedVideo {
  final Uint8List bytes;
  final String ext; // mp4 | webm | mov
  final String name;
  PickedVideo(this.bytes, this.ext, this.name);
  double get sizeMB => bytes.length / (1024 * 1024);
}

Future<PickedVideo?> pickVideoFile() async {
  final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
  if (x == null) return null;
  final name = x.name;
  final lower = name.toLowerCase();
  final ext = lower.endsWith('.webm') ? 'webm' : (lower.endsWith('.mov') ? 'mov' : 'mp4');
  return PickedVideo(await x.readAsBytes(), ext, name);
}

/// Storage rule_videos/에 올리고 주소를 돌려줌. onProgress: 0.0~1.0
Future<String> uploadRuleVideo(PickedVideo v, {void Function(double)? onProgress}) async {
  final contentType = v.ext == 'webm' ? 'video/webm' : (v.ext == 'mov' ? 'video/quicktime' : 'video/mp4');
  final ref = FirebaseStorage.instance.ref().child('rule_videos/${DateTime.now().millisecondsSinceEpoch}.${v.ext}');
  final task = ref.putData(v.bytes, SettableMetadata(contentType: contentType));
  final sub = task.snapshotEvents.listen((s) {
    if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
  });
  try {
    await task;
  } finally {
    await sub.cancel();
  }
  return ref.getDownloadURL();
}

/// "BGG #13 · 원래 이름 "CATAN" · weight 2.29 · 긱 순위 #600"
String bggInfoText(BggGameInfo g) {
  final parts = <String>['BGG #${g.geekId}'];
  if (g.bggName != null && g.bggName!.isNotEmpty) parts.add('원래 이름 "${g.bggName}"');
  parts.add('weight ${g.weight != null ? g.weight!.toStringAsFixed(2) : '정보 없음'}');
  parts.add('긱 순위 ${g.rank != null ? '#${g.rank}' : '정보 없음'}');
  return parts.join(' · ');
}

/// 게임 추가 폼과 수정 팝업이 같이 쓰는 입력값 묶음
class GameForm {
  final geekId = TextEditingController();
  final name = TextEditingController();
  final minPlayers = TextEditingController();
  final maxPlayers = TextEditingController();
  final recommended = TextEditingController();
  final weight = TextEditingController();
  final rank = TextEditingController();
  final time = TextEditingController();
  final tags = TextEditingController();
  final videoUrl = TextEditingController();
  final pickNote = TextEditingController();

  Set<String> genres = {};
  String? manualDifficulty; // weight가 없을 때만 직접 고름
  bool expansion = false;
  String? bggName;
  String? bggInfo; // 화면 안내용

  Uint8List? imageBytes;
  String imageExt = 'jpg';
  String? existingImageUrl;
  bool removeImage = false;

  Uint8List? rulebookBytes;
  String? existingRulebookUrl;
  bool removeRulebook = false;

  String? existingPlayersText; // 인원 숫자 없이 예전 방식으로 적힌 문자열(예: "2~4인") 보존용

  String? get autoDifficulty => difficultyFromWeight(asDouble(weight.text));
  String? get difficulty => autoDifficulty ?? manualDifficulty;

  void clear() {
    for (final c in [geekId, name, minPlayers, maxPlayers, recommended, weight, rank, time, tags, videoUrl, pickNote]) {
      c.clear();
    }
    genres = {};
    manualDifficulty = null;
    expansion = false;
    bggName = null;
    bggInfo = null;
    imageBytes = null;
    imageExt = 'jpg';
    existingImageUrl = null;
    removeImage = false;
    rulebookBytes = null;
    existingRulebookUrl = null;
    removeRulebook = false;
    existingPlayersText = null;
  }

  /// BGG 조회 결과로 채움 (이름은 keepName이 true면 그대로 둠)
  void fillFromBgg(BggGameInfo g, {bool keepName = false}) {
    geekId.text = g.geekId;
    if (!keepName || name.text.trim().isEmpty) name.text = g.name;
    minPlayers.text = '${g.minPlayers}';
    maxPlayers.text = '${g.maxPlayers}';
    recommended.text = g.recommendedPlayers ?? '';
    weight.text = g.weight != null ? g.weight!.toStringAsFixed(2) : '';
    rank.text = g.rank != null ? '${g.rank}' : '';
    final t = g.playTimeText;
    if (t != null) time.text = t; // BGG 플레이 시간 (없으면 적힌 값 그대로)
    bggName = g.bggName;
    bggInfo = bggInfoText(g);
  }

  void fillFromDoc(Map<String, dynamic> d) {
    clear();
    geekId.text = (d['geekId'] ?? '').toString();
    name.text = (d['title'] ?? '').toString();
    final mn = asInt(d['minPlayers']);
    final mx = asInt(d['maxPlayers']);
    minPlayers.text = mn != null ? '$mn' : '';
    maxPlayers.text = mx != null ? '$mx' : '';
    if (mn == null) existingPlayersText = (d['players'] ?? '').toString();
    recommended.text = (d['recommendedPlayers'] ?? '').toString();
    final w = asDouble(d['weight']);
    weight.text = w != null ? w.toStringAsFixed(2) : '';
    final r = asInt(d['rank']);
    rank.text = r != null ? '$r' : '';
    time.text = (d['time'] ?? '').toString();
    tags.text = (d['tags'] ?? '').toString();
    videoUrl.text = (d['videoUrl'] ?? '').toString();
    pickNote.text = (d['pickNote'] ?? '').toString();
    genres = gameGenres(d).toSet();
    final diff = (d['difficulty'] ?? '').toString();
    manualDifficulty = difficultyLabels.contains(diff) ? diff : null;
    expansion = d['expansion'] == true;
    bggName = d['bggName']?.toString();
    existingImageUrl = (d['imageUrl'] ?? '').toString();
    existingRulebookUrl = (d['rulebookImageUrl'] ?? '').toString();
  }

  List<String> orderedGenres(List<String> all) => [
        ...all.where(genres.contains),
        ...genres.where((g) => !all.contains(g)),
      ];

  /// 저장할 필드 (사진 주소 제외). 입력이 잘못됐으면 GameFormError.
  Map<String, dynamic> toFields(List<String> allGenres) {
    final nm = name.text.trim();
    if (nm.isEmpty) throw GameFormError('게임 이름을 입력해 주세요.');
    if (nm.length > 40) throw GameFormError('게임 이름은 40자까지 입력할 수 있어요.');
    final mnText = minPlayers.text.trim();
    final mxText = maxPlayers.text.trim();
    final mn = asInt(mnText);
    final mx = asInt(mxText);
    if ((mnText.isEmpty) != (mxText.isEmpty)) throw GameFormError('최소·최대 인원을 둘 다 입력해 주세요.');
    if (mnText.isNotEmpty && (mn == null || mx == null || mn < 1 || mx < mn || mx > 30)) {
      throw GameFormError('인원 수를 확인해 주세요. (최소 ≤ 최대, 최대 30명)');
    }
    final wText = weight.text.trim();
    final w = wText.isEmpty ? null : asDouble(wText);
    if (wText.isNotEmpty && (w == null || w < 0 || w > 5)) throw GameFormError('weight는 0~5 사이 숫자로 입력해 주세요.');
    final rText = rank.text.trim();
    final r = rText.isEmpty ? null : asInt(rText);
    if (rText.isNotEmpty && (r == null || r < 1)) throw GameFormError('긱 순위를 확인해 주세요.');
    final gid = geekId.text.trim();
    if (gid.isNotEmpty && !RegExp(r'^\d+$').hasMatch(gid)) throw GameFormError('BGG geek ID는 숫자로 입력해 주세요.');

    final legacy = legacyGameFields(
      genres: orderedGenres(allGenres),
      minPlayers: mn,
      maxPlayers: mx,
      difficulty: difficulty,
    );
    if (mn == null && existingPlayersText != null) legacy['players'] = existingPlayersText;

    return {
      'title': nm,
      ...legacy,
      'minPlayers': mn,
      'maxPlayers': mx,
      'recommendedPlayers': recommended.text.trim().isEmpty ? null : recommended.text.trim(),
      'weight': w,
      'rank': r,
      'geekId': gid.isEmpty ? null : gid,
      'bggName': bggName,
      'time': time.text.trim(),
      'tags': tags.text.trim(),
      'videoUrl': videoUrl.text.trim(),
      'pickNote': pickNote.text.trim(),
      'expansion': expansion,
    };
  }

  /// 사진·룰북을 올리고(또는 지우고) 저장할 주소 필드를 돌려줌. 예전 파일은 저장이 끝난 뒤 지우도록 목록으로 돌려줌.
  Future<(Map<String, dynamic>, List<String>)> uploadImages() async {
    final fields = <String, dynamic>{};
    final toDelete = <String>[];
    if (imageBytes != null) {
      fields['imageUrl'] = await uploadGameImage(imageBytes!, 'game_images', ext: imageExt);
      if ((existingImageUrl ?? '').isNotEmpty) toDelete.add(existingImageUrl!);
    } else if (removeImage) {
      fields['imageUrl'] = '';
      if ((existingImageUrl ?? '').isNotEmpty) toDelete.add(existingImageUrl!);
    }
    if (rulebookBytes != null) {
      fields['rulebookImageUrl'] = await uploadGameImage(rulebookBytes!, 'rulebook_images');
      if ((existingRulebookUrl ?? '').isNotEmpty) toDelete.add(existingRulebookUrl!);
    } else if (removeRulebook) {
      fields['rulebookImageUrl'] = '';
      if ((existingRulebookUrl ?? '').isNotEmpty) toDelete.add(existingRulebookUrl!);
    }
    return (fields, toDelete);
  }

  void dispose() {
    for (final c in [geekId, name, minPlayers, maxPlayers, recommended, weight, rank, time, tags, videoUrl, pickNote]) {
      c.dispose();
    }
  }
}

InputDecoration adminInput(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

/// 난이도 색 배지
class DifficultyBadge extends StatelessWidget {
  final String? label;
  final bool small;
  const DifficultyBadge({super.key, required this.label, this.small = false});

  @override
  Widget build(BuildContext context) {
    if (label == null || label!.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 10, vertical: small ? 2 : 6),
      decoration: BoxDecoration(color: difficultyColor(label), borderRadius: BorderRadius.circular(6)),
      child: Text(label!, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: small ? 11 : 13)),
    );
  }
}

/// geek ID 입력 + 조회 + 이름으로 검색
class GeekIdRow extends StatelessWidget {
  final GameForm form;
  final bool busy;
  final VoidCallback onLookup;
  final VoidCallback onSearch;
  const GeekIdRow({super.key, required this.form, required this.busy, required this.onLookup, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: form.geekId,
            keyboardType: TextInputType.number,
            decoration: adminInput('BGG geek ID', hint: '예: 13'),
            onSubmitted: (_) {
              if (!busy) onLookup();
            },
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: busy ? null : onLookup, child: const Text('조회')),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : onSearch,
          icon: const Icon(Icons.search, size: 18),
          label: const Text('이름으로 검색'),
        ),
      ],
    );
  }
}

/// 게임 정보 입력 칸들 (추가 폼·수정 팝업 공통)
class GameFormFields extends StatefulWidget {
  final GameForm form;
  final List<String> genreList;
  const GameFormFields({super.key, required this.form, required this.genreList});

  @override
  State<GameFormFields> createState() => _GameFormFieldsState();
}

class _GameFormFieldsState extends State<GameFormFields> {
  GameForm get f => widget.form;

  Widget _imageBox({
    required String label,
    required Uint8List? bytes,
    required String? url,
    required bool removed,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final hasUrl = !removed && url != null && url.isNotEmpty;
    Widget preview;
    if (bytes != null) {
      preview = Image.memory(bytes, fit: BoxFit.cover);
    } else if (hasUrl) {
      preview = AppNetworkImage(imageUrl: url, fit: BoxFit.cover, errorWidget: (c, u, e) => const Icon(Icons.image, color: Colors.grey));
    } else {
      preview = const Icon(Icons.add_photo_alternate, color: Colors.grey);
    }
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.hardEdge,
          child: preview,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(onPressed: onPick, child: Text(bytes != null || hasUrl ? '바꾸기' : '고르기')),
                  if (bytes != null || hasUrl) TextButton(onPressed: onClear, child: const Text('삭제', style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auto = f.autoDifficulty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (f.bggInfo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(f.bggInfo!, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ),
        _imageBox(
          label: '게임 사진',
          bytes: f.imageBytes,
          url: f.existingImageUrl,
          removed: f.removeImage,
          onPick: () async {
            final b = await pickImageBytes();
            if (b != null) setState(() {
              f.imageBytes = b;
              f.imageExt = 'jpg';
            });
          },
          onClear: () => setState(() {
            if (f.imageBytes != null) {
              f.imageBytes = null;
            } else {
              f.removeImage = true;
            }
          }),
        ),
        const SizedBox(height: 16),
        TextField(controller: f.name, maxLength: 40, decoration: adminInput('게임 이름')),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: TextField(controller: f.minPlayers, keyboardType: TextInputType.number, decoration: adminInput('최소 인원'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: f.maxPlayers, keyboardType: TextInputType.number, decoration: adminInput('최대 인원'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: f.recommended, decoration: adminInput('추천 인원', hint: '예: 3, 4'))),
          ],
        ),
        if (f.existingPlayersText != null && f.existingPlayersText!.isNotEmpty && f.minPlayers.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('예전에 적힌 인원: "${f.existingPlayersText}" — 숫자로 다시 입력하면 바뀌어요.',
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: f.weight,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: adminInput('geek weight (0~5)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: f.rank, keyboardType: TextInputType.number, decoration: adminInput('긱 순위'))),
            const SizedBox(width: 8),
            Expanded(
              child: auto != null
                  ? InputDecorator(
                      decoration: adminInput('난이도 (weight 기준 자동)'),
                      child: Align(alignment: Alignment.centerLeft, child: DifficultyBadge(label: auto, small: true)),
                    )
                  : DropdownButtonFormField<String>(
                      value: f.manualDifficulty,
                      decoration: adminInput('난이도 (직접 선택)'),
                      items: difficultyLabels.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setState(() => f.manualDifficulty = v),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('장르 (여러 개 선택 가능)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        widget.genreList.isEmpty
            ? const Text('등록된 장르가 없어요. 위쪽 "장르 관리"에서 먼저 추가해 주세요.', style: TextStyle(color: Colors.grey))
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.genreList
                    .map((g) => FilterChip(
                          label: Text(g),
                          selected: f.genres.contains(g),
                          selectedColor: kAdminGreen.withValues(alpha: 0.2),
                          checkmarkColor: kAdminGreen,
                          onSelected: (on) => setState(() => on ? f.genres.add(g) : f.genres.remove(g)),
                        ))
                    .toList(),
              ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextField(controller: f.time, decoration: adminInput('소요 시간', hint: '예: 30분, 1시간'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: f.tags, decoration: adminInput('해시태그', hint: '예: #꿀잼 #입문용'))),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: f.videoUrl,
          decoration: adminInput('유튜브 룰 영상 링크 (선택)', hint: '매장에서 만든 영상이 있으면 그 영상이 먼저 나와요'),
        ),
        const SizedBox(height: 12),
        TextField(controller: f.pickNote, maxLength: 60, decoration: adminInput('매장 추천 한마디 (선택, 매장 추천 게임에만 쓰여요)')),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: f.expansion,
          onChanged: (v) => setState(() => f.expansion = v ?? false),
          title: const Text('확장판 (게임 추천에서 빼고, 목록에는 표시)'),
        ),
        const SizedBox(height: 4),
        _imageBox(
          label: '룰북 이미지 (선택)',
          bytes: f.rulebookBytes,
          url: f.existingRulebookUrl,
          removed: f.removeRulebook,
          onPick: () async {
            final b = await pickImageBytes();
            if (b != null) setState(() => f.rulebookBytes = b);
          },
          onClear: () => setState(() {
            if (f.rulebookBytes != null) {
              f.rulebookBytes = null;
            } else {
              f.removeRulebook = true;
            }
          }),
        ),
      ],
    );
  }
}

/// BGG 이름 검색 팝업. 고른 결과를 돌려줌 (닫으면 null)
class BggSearchDialog extends StatefulWidget {
  final String initialQuery;
  const BggSearchDialog({super.key, this.initialQuery = ''});

  @override
  State<BggSearchDialog> createState() => _BggSearchDialogState();
}

class _BggSearchDialogState extends State<BggSearchDialog> {
  late final TextEditingController _q = TextEditingController(text: widget.initialQuery);
  List<BggSearchResult>? _results;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() => _error = '검색어를 입력해 주세요.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await BggService.search(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('BGG에서 찾는 중… (조금 걸릴 수 있어요)')]));
    } else if (_error != null) {
      body = Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    } else if (_results == null) {
      body = const SizedBox.shrink();
    } else if (_results!.isEmpty) {
      body = const Center(child: Text('검색 결과가 없어요. 영어 이름으로도 찾아보거나 직접 입력해 주세요.'));
    } else {
      body = ListView.separated(
        itemCount: _results!.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _results![i];
          return ListTile(
            leading: SizedBox(
              width: 48,
              height: 48,
              child: r.thumbnail == null
                  ? const Icon(Icons.casino, color: Colors.grey)
                  : Image.network(r.thumbnail!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.casino, color: Colors.grey)),
            ),
            title: Text(r.name),
            subtitle: r.yearPublished != null ? Text('${r.yearPublished}년') : null,
            trailing: Text('#${r.id}', style: const TextStyle(color: Colors.grey)),
            onTap: () => Navigator.pop(context, r),
          );
        },
      );
    }
    return AlertDialog(
      title: const Text('BGG(보드게임긱)에서 찾기', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('이름이 비슷한 확장판·재판이 있을 수 있어요. 목록에서 정확한 게임을 골라 주세요.', style: TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _q,
                    autofocus: true,
                    decoration: adminInput('게임 이름'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _search,
                  icon: const Icon(Icons.search),
                  label: const Text('검색'),
                  style: ElevatedButton.styleFrom(backgroundColor: kAdminGreen, foregroundColor: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: body),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
    );
  }
}

/// geek ID로 BGG 정보·사진을 가져와 폼을 채움. 정보 조회 실패는 예외로, 사진만 실패하면 안내 문구를 돌려줌.
Future<String?> fillFormFromBgg(GameForm form, String geekId, {bool keepName = false, required VoidCallback refresh}) async {
  final info = await BggService.lookup(geekId);
  form.fillFromBgg(info, keepName: keepName);
  refresh();
  try {
    final img = await BggService.image(geekId);
    form.imageBytes = img.bytes;
    form.imageExt = img.extension;
    form.removeImage = false;
    refresh();
    return null;
  } catch (e) {
    return '게임 정보는 가져왔지만 사진은 못 가져왔어요. ($e)';
  }
}
