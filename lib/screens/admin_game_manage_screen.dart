import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'admin_menu_manage_screen.dart';
import 'admin_event_manage_screen.dart';
import 'admin_notice_manage_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';


class AdminGameManageScreen extends StatefulWidget {
  const AdminGameManageScreen({super.key});

  @override
  State<AdminGameManageScreen> createState() => _AdminGameManageScreenState();
}

class _AdminGameManageScreenState extends State<AdminGameManageScreen> {

  String searchQuery = '';
  int currentPage = 1;
  String selectedGenreFilter = '전체';
  final int itemsPerPage = 10;
  List<String> _genreList = [];
  StreamSubscription<DocumentSnapshot>? _genreSubscription;

  static const List<String> _difficultyValues = ['매우쉬움','쉬움','보통','어려움','매우어려움','전문'];

  // ── 장르 Firestore 헬퍼 ──
  Future<void> _addGenre(String name) async {
    if (name.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('settings').doc('genres').set(
      {'items': FieldValue.arrayUnion([name.trim()])},
      SetOptions(merge: true),
    );
  }

  Future<void> _deleteGenre(String name) async {
    await FirebaseFirestore.instance.collection('settings').doc('genres').update(
      {'items': FieldValue.arrayRemove([name])},
    );
  }

  Future<void> _editGenre(String oldName, String newName) async {
    if (newName.trim().isEmpty || newName.trim() == oldName) return;
    final genresRef = FirebaseFirestore.instance.collection('settings').doc('genres');

    // Transaction: 장르 목록 read-modify-write를 원자적으로 처리 (race condition 방지)
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final doc = await transaction.get(genresRef);
      final items = List<String>.from((doc.data() as Map? ?? {})['items'] ?? []);
      final idx = items.indexOf(oldName);
      if (idx == -1) return;
      items[idx] = newName.trim();
      transaction.update(genresRef, {'items': items});
    });

    // 해당 장르를 가진 게임들도 일괄 업데이트 (Transaction 밖 — Firestore는 transaction 내 쿼리 미지원)
    final games = await FirebaseFirestore.instance
        .collection('games')
        .where('genre', isEqualTo: oldName)
        .get();
    if (games.docs.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final g in games.docs) {
        batch.update(g.reference, {'genre': newName.trim()});
      }
      await batch.commit();
    }
  }

  void _showGenreManageDialog(BuildContext context, List<String> genreList) {
    final addCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
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
                          title: Text(g, style: const TextStyle(fontSize: 15)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 수정 버튼
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                tooltip: '수정',
                                onPressed: () async {
                                  final editCtrl = TextEditingController(text: g);
                                  await showDialog(
                                    context: ctx,
                                    builder: (ectx) => AlertDialog(
                                      title: const Text('장르 수정', style: TextStyle(fontWeight: FontWeight.bold)),
                                      content: TextField(
                                        controller: editCtrl,
                                        autofocus: true,
                                        decoration: const InputDecoration(labelText: '장르 이름', border: OutlineInputBorder()),
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ectx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                                        ElevatedButton(
                                          onPressed: () async {
                                            await _editGenre(g, editCtrl.text);
                                            if (ectx.mounted) Navigator.pop(ectx);
                                          },
                                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B37E), foregroundColor: Colors.white),
                                          child: const Text('저장'),
                                        ),
                                      ],
                                    ),
                                  );
                                  editCtrl.dispose();
                                },
                              ),
                              // 삭제 버튼
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                tooltip: '삭제',
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dctx) => AlertDialog(
                                      title: const Text('장르 삭제', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                                      content: Text("'$g' 장르를 삭제하시겠습니까? 해당 장르로 등록된 게임의 장르 정보는 유지됩니다."),
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
                                  if (confirmed == true) await _deleteGenre(g);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const Divider(height: 24),
                // 장르 추가 입력
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: addCtrl,
                        decoration: const InputDecoration(
                          hintText: '새 장르 이름 입력',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        onSubmitted: (val) async {
                          if (val.trim().isNotEmpty) {
                            await _addGenre(val);
                            addCtrl.clear();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        if (addCtrl.text.trim().isNotEmpty) {
                          await _addGenre(addCtrl.text);
                          addCtrl.clear();
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B37E), foregroundColor: Colors.white),
                      child: const Text('추가'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade200, foregroundColor: Colors.black87),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => addCtrl.dispose());
  }

  // ── 게임 등록/수정 다이얼로그 (genreList 파라미터 추가) ──
  void _showGameDialog(BuildContext context, List<String> genreList, {Map<String, dynamic>? existingGame, String? docId}) {
    final bool isEditMode = existingGame != null && docId != null;

    final titleController = TextEditingController(text: isEditMode ? existingGame!['title'] : '');
    final timeController = TextEditingController(text: isEditMode ? existingGame!['time'] : '');
    final playersController = TextEditingController(text: isEditMode ? existingGame!['players'] : '');
    final tagsController = TextEditingController(text: isEditMode ? existingGame!['tags'] : '');
    final videoUrlController = TextEditingController(text: isEditMode ? existingGame!['videoUrl'] : '');

    final String defaultGenre = genreList.isNotEmpty ? genreList[0] : '';
    String dbGenre = isEditMode ? (existingGame!['genre'] ?? defaultGenre) : defaultGenre;
    String selectedGenre = genreList.contains(dbGenre) ? dbGenre : (genreList.isNotEmpty ? genreList[0] : '');

    String dbDiff = isEditMode ? (existingGame!['difficulty'] ?? _difficultyValues[0]) : _difficultyValues[0];
    String selectedDifficulty = _difficultyValues.contains(dbDiff) ? dbDiff : _difficultyValues[0];

    String currentImageUrl = isEditMode ? (existingGame!['imageUrl'] ?? '') : '';

    Uint8List? selectedImageBytes;
    bool isUploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> pickImage() async {
              final ImagePicker picker = ImagePicker();
              final XFile? image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 70);
              if (image != null) {
                final bytes = await image.readAsBytes();
                setState(() => selectedImageBytes = bytes);
              }
            }

            return AlertDialog(
              title: Text(isEditMode ? '보드게임 정보 수정' : '새 보드게임 등록', style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 450,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: pickImage,
                        child: Container(
                          width: 120, height: 120,
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                          clipBehavior: Clip.hardEdge,
                          child: selectedImageBytes != null
                              ? Image.memory(selectedImageBytes!, fit: BoxFit.cover)
                              : (currentImageUrl.isNotEmpty
                                  ? CachedNetworkImage(imageUrl: currentImageUrl, fit: BoxFit.cover, errorWidget: (c,u,e) => const Icon(Icons.image, color: Colors.grey))
                                  : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate, color: Colors.grey, size: 32), SizedBox(height: 8), Text('사진 등록', style: TextStyle(color: Colors.grey))])),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(controller: titleController, decoration: const InputDecoration(labelText: '게임 이름', border: OutlineInputBorder())),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: genreList.isEmpty
                                ? const TextField(decoration: InputDecoration(labelText: '장르 (장르를 먼저 추가하세요)', border: OutlineInputBorder()), enabled: false)
                                : DropdownButtonFormField<String>(
                                    value: selectedGenre.isNotEmpty ? selectedGenre : null,
                                    decoration: const InputDecoration(labelText: '장르', border: OutlineInputBorder()),
                                    items: genreList.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                    onChanged: (val) => setState(() => selectedGenre = val ?? ''),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: DropdownButtonFormField<String>(value: selectedDifficulty, decoration: const InputDecoration(labelText: '난이도', border: OutlineInputBorder()), items: _difficultyValues.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (val) => setState(() => selectedDifficulty = val ?? _difficultyValues[0]))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: playersController, decoration: const InputDecoration(labelText: '추천 인원 (예: 2~4인)', border: OutlineInputBorder()))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: timeController, decoration: const InputDecoration(labelText: '소요 시간 (예: 30분)', border: OutlineInputBorder()))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(controller: tagsController, decoration: const InputDecoration(labelText: '해시태그 (예: #꿀잼 #입문용)', border: OutlineInputBorder())),
                      const SizedBox(height: 16),
                      TextField(controller: videoUrlController, decoration: const InputDecoration(labelText: '유튜브 룰 영상 링크 (선택)', border: OutlineInputBorder())),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: isUploading ? null : () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey, fontSize: 16))),
                ElevatedButton(
                  onPressed: isUploading ? null : () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;
                    setState(() => isUploading = true);

                    try {
                      String finalImageUrl = currentImageUrl;
                      if (selectedImageBytes != null) {
                        final storageRef = FirebaseStorage.instance.ref().child('game_images/${DateTime.now().millisecondsSinceEpoch}.jpg');
                        final uploadTask = await storageRef.putData(selectedImageBytes!);
                        finalImageUrl = await uploadTask.ref.getDownloadURL();
                      }

                      final Map<String, dynamic> gameData = {
                        'title': title, 'genre': selectedGenre, 'difficulty': selectedDifficulty,
                        'players': playersController.text.trim(), 'time': timeController.text.trim(),
                        'tags': tagsController.text.trim(), 'videoUrl': videoUrlController.text.trim(),
                        'imageUrl': finalImageUrl,
                      };

                      if (isEditMode) {
                        await FirebaseFirestore.instance.collection('games').doc(docId).update(gameData);
                      } else {
                        gameData['isAvailable'] = true;
                        gameData['timestamp'] = FieldValue.serverTimestamp();
                        await FirebaseFirestore.instance.collection('games').add(gameData);
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEditMode ? '수정되었습니다.' : '등록되었습니다.')));
                      }
                    } catch (e) {
        debugPrint('Error: \$e');
                      setState(() => isUploading = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장에 실패했습니다. 다시 시도해주세요.'), backgroundColor: Colors.red));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B37E), foregroundColor: Colors.white),
                  child: isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(isEditMode ? '수정하기' : '등록하기', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    ).whenComplete(() {
      titleController.dispose();
      timeController.dispose();
      playersController.dispose();
      tagsController.dispose();
      videoUrlController.dispose();
    });
  }

  Future<void> _deleteStorageImage(String url) async {
    if (url.isEmpty) return;
    try { await FirebaseStorage.instance.refFromURL(url).delete(); } catch (_) {}
  }

  void _confirmDeleteGame(BuildContext context, String docId, String gameTitle, String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('게임 삭제', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
          content: Text("'$gameTitle' 게임을 정말 삭제하시겠습니까?\n삭제된 데이터는 복구할 수 없습니다."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _deleteStorageImage(imageUrl);
                  await FirebaseFirestore.instance.collection('games').doc(docId).delete();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제가 완료되었습니다.')));
                  }
                } catch (e) {
        debugPrint('Error: \$e');
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장에 실패했습니다. 다시 시도해주세요.'), backgroundColor: Colors.red));
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              child: const Text('삭제하기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _genreSubscription = FirebaseFirestore.instance
        .collection('settings').doc('genres').snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() {
          _genreList = (snap.exists)
              ? List<String>.from((snap.data() as Map? ?? {})['items'] ?? [])
              : [];
        });
      }
    });
  }

  @override
  void dispose() {
    _genreSubscription?.cancel();
    super.dispose();
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
                'menu': const AdminMenuManageScreen(),
                'event': const AdminEventManageScreen(),
                'notice': const AdminNoticeManageScreen(),
                  };
                  final target = targets[screen];
                  if (target != null) Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => target, transitionDuration: Duration.zero, reverseTransitionDuration: Duration.zero));
                },
              ),

              // 우측 메인 콘텐츠
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 헤더
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('보드게임 관리', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              Container(
                                width: 250,
                                height: 48,
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                                child: TextField(
                                  onChanged: (value) {
                                    setState(() { searchQuery = value; currentPage = 1; });
                                  },
                                  decoration: const InputDecoration(hintText: '게임 이름 검색', prefixIcon: Icon(Icons.search), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 14)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                onPressed: () => _showGameDialog(context, _genreList),
                                icon: const Icon(Icons.add),
                                label: const Text('새 게임 등록', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B37E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await FirebaseFirestore.instance
                                      .collection('settings')
                                      .doc('appRefresh')
                                      .set({'gamesUpdatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('손님 앱 게임 목록이 새로고침됩니다.'), backgroundColor: Color(0xFF00B37E)),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.sync),
                                label: const Text('손님 앱 새로고침', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2B3C), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── 장르 필터 + 관리 섹션 ──
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                        child: Row(
                          children: [
                            const Text('장르 필터', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: ['전체', ..._genreList].map((g) {
                                    final isSelected = selectedGenreFilter == g;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(g),
                                        selected: isSelected,
                                        selectedColor: const Color(0xFF00B37E),
                                        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                                        onSelected: (_) => setState(() { selectedGenreFilter = g; currentPage = 1; }),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _showGenreManageDialog(context, _genreList),
                              icon: const Icon(Icons.settings, size: 18),
                              label: const Text('장르 관리'),
                              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF00B37E), side: const BorderSide(color: Color(0xFF00B37E))),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 게임 리스트
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance.collection('games').orderBy('timestamp', descending: true).snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('등록된 보드게임이 없습니다.'));

                              final allGames = snapshot.data!.docs;
                              final games = allGames.where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final title = (data['title'] ?? '').toString().toLowerCase();
                                final genre = (data['genre'] ?? '').toString();
                                final matchesSearch = searchQuery.isEmpty || title.contains(searchQuery.toLowerCase());
                                final matchesGenre = selectedGenreFilter == '전체' || genre == selectedGenreFilter;
                                return matchesSearch && matchesGenre;
                              }).toList();

                              if (games.isEmpty) return const Center(child: Text('해당하는 게임이 없습니다.', style: TextStyle(fontSize: 16, color: Colors.grey)));

                              final int totalPages = (games.length + itemsPerPage - 1) ~/ itemsPerPage;

                              if (totalPages > 0 && currentPage > totalPages) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) setState(() => currentPage = totalPages);
                                });
                                return const Center(child: CircularProgressIndicator());
                              }
                              final int startIndex = (currentPage - 1) * itemsPerPage;
                              final int endIndex = (startIndex + itemsPerPage > games.length) ? games.length : startIndex + itemsPerPage;
                              final paginatedGames = games.sublist(startIndex, endIndex);

                              return Column(
                                children: [
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: paginatedGames.length,
                                      separatorBuilder: (context, index) => const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final doc = paginatedGames[index];
                                        final game = doc.data() as Map<String, dynamic>;
                                        return ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                          leading: Container(
                                            width: 60, height: 60,
                                            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                                            clipBehavior: Clip.hardEdge,
                                            child: (hasValidImage(game['imageUrl']))
                                                ? CachedNetworkImage(imageUrl: game['imageUrl'], fit: BoxFit.cover, errorWidget: (c,u,e) => const Icon(Icons.image, color: Colors.grey, size: 32))
                                                : const Icon(Icons.image, color: Colors.grey, size: 32),
                                          ),
                                          title: Text(game['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: Row(
                                              children: [
                                                _buildInfoChip(Icons.theater_comedy, game['genre'] ?? ''),
                                                const SizedBox(width: 8),
                                                _buildInfoChip(Icons.people, game['players'] ?? ''),
                                                const SizedBox(width: 8),
                                                _buildInfoChip(Icons.timer, game['time'] ?? ''),
                                                const SizedBox(width: 8),
                                                _buildInfoChip(Icons.star, game['difficulty'] ?? ''),
                                                const SizedBox(width: 12),
                                                Text(game['tags'] ?? '', style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Switch(
                                                value: game['isAvailable'] ?? true,
                                                onChanged: (val) => FirebaseFirestore.instance.collection('games').doc(doc.id).update({'isAvailable': val}),
                                                activeColor: const Color(0xFF00B37E),
                                              ),
                                              Text((game['isAvailable'] ?? true) ? '이용 가능' : '숨김(분실 등)', style: TextStyle(color: (game['isAvailable'] ?? true) ? Colors.black87 : Colors.red, fontWeight: FontWeight.bold)),
                                              const SizedBox(width: 24),
                                              Switch(
                                                value: game['isRecommended'] ?? false,
                                                onChanged: (val) => FirebaseFirestore.instance.collection('games').doc(doc.id).update({'isRecommended': val}),
                                                activeColor: Colors.amber,
                                              ),
                                              Text('추천', style: TextStyle(color: (game['isRecommended'] ?? false) ? Colors.amber.shade700 : Colors.grey, fontWeight: FontWeight.bold)),
                                              const SizedBox(width: 24),
                                              IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showGameDialog(context, _genreList, existingGame: game, docId: doc.id)),
                                              IconButton(
                                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                                onPressed: () => _confirmDeleteGame(context, doc.id, game['title'] ?? '이 게임', (game['imageUrl'] ?? '').toString()),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  if (totalPages > 1)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                                      child: Builder(
                                        builder: (context) {
                                          const int pagesPerBlock = 10;
                                          final int currentBlock = (currentPage - 1) ~/ pagesPerBlock;
                                          final int startPage = currentBlock * pagesPerBlock + 1;
                                          final int endPage = (startPage + pagesPerBlock - 1 > totalPages) ? totalPages : startPage + pagesPerBlock - 1;
                                          return Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (startPage > 1)
                                                IconButton(icon: const Icon(Icons.chevron_left, color: Colors.black54), onPressed: () => setState(() => currentPage = startPage - 1)),
                                              Wrap(
                                                spacing: 4.0,
                                                children: List.generate(endPage - startPage + 1, (index) {
                                                  int page = startPage + index;
                                                  return ElevatedButton(
                                                    onPressed: () => setState(() => currentPage = page),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: currentPage == page ? const Color(0xFF00B37E) : Colors.transparent,
                                                      foregroundColor: currentPage == page ? Colors.white : Colors.black87,
                                                      elevation: 0,
                                                      minimumSize: const Size(40, 40),
                                                      padding: EdgeInsets.zero,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    child: Text('$page', style: TextStyle(fontWeight: currentPage == page ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
                                                  );
                                                }),
                                              ),
                                              if (endPage < totalPages)
                                                IconButton(icon: const Icon(Icons.chevron_right, color: Colors.black54), onPressed: () => setState(() => currentPage = endPage + 1)),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
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

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }
}
