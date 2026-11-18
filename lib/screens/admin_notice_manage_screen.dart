import 'dart:typed_data';

import 'package:boardpad/services/translate_sync.dart';
import 'package:flutter/material.dart';
import 'package:boardpad/widgets/admin_dialog_width.dart';
import 'admin_store_settings_screen.dart';
import 'admin_home_layout_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'admin_menu_manage_screen.dart';
import 'admin_game_manage_screen.dart';
import 'admin_event_manage_screen.dart';

import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';
import 'package:boardpad/widgets/admin_post_board.dart';
import 'package:boardpad/widgets/admin_colors.dart';
import 'package:boardpad/widgets/home/home_theme.dart' show kBlue;
import 'package:boardpad/widgets/admin_busy_dialog.dart';
import 'package:boardpad/services/store_scope.dart';

class AdminNoticeManageScreen extends StatefulWidget {
  const AdminNoticeManageScreen({super.key});

  @override
  State<AdminNoticeManageScreen> createState() =>
      _AdminNoticeManageScreenState();
}

class _AdminNoticeManageScreenState extends State<AdminNoticeManageScreen> {
  void _showNoticeDialog(
    BuildContext context, {
    Map<String, dynamic>? existing,
    int? index,
  }) {
    String selectedType = existing?['type'] ?? 'text';
    final titleController = TextEditingController(
      text: existing?['title'] ?? '',
    );
    final contentController = TextEditingController(
      text: existing?['type'] == 'text' ? (existing?['content'] ?? '') : '',
    );
    String currentImageUrl = existing?['type'] == 'image'
        ? (existing?['content'] ?? '')
        : '';
    Uint8List? selectedImageBytes;
    bool isUploading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        // 112차: 저장 중엔 바깥 누르기·뒤로 가기로 안 닫힘(PopScope), [취소]도 흐리게
        builder: (context, setDialogState) => PopScope(
          canPop: !isUploading,
          child: AlertDialog(
          title: Text(
            existing != null ? '공지 수정' : '공지 추가',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: adminDialogWidth(context, 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '표시 방식',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  RadioGroup<String>(
                    groupValue: selectedType,
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedType = value);
                      }
                    },
                    child: Row(
                      children: [
                        Radio<String>(
                          value: 'text',
                          activeColor: kAdminAccent,
                        ),
                        const Text('텍스트'),
                        const SizedBox(width: 24),
                        Radio<String>(
                          value: 'image',
                          activeColor: kAdminAccent,
                        ),
                        const Text('이미지'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '제목',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '공지 제목 입력',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (selectedType == 'text') ...[
                    const Text(
                      '내용',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: contentController,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '공지 내용을 입력하세요',
                      ),
                    ),
                  ] else ...[
                    const Text(
                      '이미지',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 80,
                        );
                        if (picked != null) {
                          final bytes = await picked.readAsBytes();
                          setDialogState(() => selectedImageBytes = bytes);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 220,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade100,
                        ),
                        child: selectedImageBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  selectedImageBytes!,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : (currentImageUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: AppNetworkImage(
                                        imageUrl: currentImageUrl,
                                        fit: BoxFit.contain,
                                        errorWidget: (c, u, e) => const Icon(
                                          Icons.broken_image,
                                          size: 60,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    )
                                  : const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_photo_alternate,
                                            size: 60,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            '클릭하여 이미지 선택',
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: isUploading
                    ? null
                    : () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('제목을 입력해주세요.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }
                        setDialogState(() => isUploading = true);
                        try {
                          String content = '';
                          if (selectedType == 'text') {
                            content = contentController.text.trim();
                          } else {
                            if (selectedImageBytes != null) {
                              final ref = StoreScope.storage.child(
                                'notice_images/${DateTime.now().millisecondsSinceEpoch}.jpg',
                              );
                              final task = await ref.putData(
                                selectedImageBytes!,
                                SettableMetadata(contentType: 'image/jpeg'), // Storage 보안 규칙이 이미지 형식을 확인함
                              );
                              content = await task.ref.getDownloadURL();
                            } else {
                              content = currentImageUrl;
                            }
                          }

                          final newItem = {
                            'type': selectedType,
                            'title': title,
                            'content': content,
                          };
                          final docRef = StoreScope.col('settings')
                              .doc('notices');
                          final docSnap = await docRef.get();
                          List<dynamic> items = docSnap.exists
                              ? (docSnap.get('items') as List<dynamic>? ?? [])
                              : [];

                          if (existing != null && index != null) {
                            items[index] = newItem;
                          } else {
                            items.add(newItem);
                          }
                          await docRef.set({'items': items});
                          TranslateSync.kick(); // 83차: 손님 패드 자동 번역

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  existing != null ? '수정되었습니다.' : '등록되었습니다.',
                                ),
                                backgroundColor: kAdminAccent,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isUploading = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('에러: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                // 처리 중엔 글자는 그대로, 버튼만 흐리게 (100차)
                style: busyButtonStyle(kAdminAccent),
                child: Text(
                  existing != null ? '수정하기' : '추가하기',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  // 112차: 처리 중 버튼 잠그기(100차 규칙) — 지우는 동안 [삭제] 흐리게·[취소]·바깥 누르기 막음, 끝나면 한 번만 닫힘
  Future<void> _deleteNotice(
    BuildContext context,
    int index,
    List<dynamic> items,
  ) async {
    await showBusyConfirm(
      context,
      title: '삭제 확인',
      message: '"${(items[index] as Map)['title']}" 공지를 삭제할까요?',
      errorText: '삭제하지 못했어요',
      action: () async {
        final newItems = List.from(items)..removeAt(index);
        await StoreScope.col('settings').doc('notices').set({'items': newItems});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Row(
        children: [
          AdminSidebar(
            currentScreen: 'notice',
            onNavigate: (screen) {
              final targets = <String, Widget>{
                'store': const AdminStoreSettingsScreen(),
                'home': const AdminHomeLayoutScreen(),
                'menu': const AdminMenuManageScreen(),
                'game': const AdminGameManageScreen(),
                'event': const AdminEventManageScreen(),
              };
              final target = targets[screen];
              if (target != null) {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, _, _) => target,
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            },
          ),
          // 메인 영역
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 16.0 : 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 8,
                    children: [
                      const Text(
                        '공지 관리',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showNoticeDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text(
                          '새 공지 추가',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAdminAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '손님 패드 이용안내 화면에 이 순서대로 보여요. 카드를 누르면 오른쪽에서 패드 모양으로 미리 볼 수 있어요.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  // 132차: 카드 목록 + 순서 ↑↓ + 손님 패드 미리보기 (lib/widgets/admin_post_board.dart)
                  Expanded(
                    child: AdminPostBoard(
                      docId: 'notices',
                      kind: '공지',
                      icon: Icons.article_outlined,
                      accent: kBlue,
                      onAdd: () => _showNoticeDialog(context),
                      onEdit: (item, index) => _showNoticeDialog(context, existing: item, index: index),
                      onDelete: (index, items) => _deleteNotice(context, index, items),
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
