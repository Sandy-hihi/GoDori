import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'admin_menu_manage_screen.dart';
import 'admin_game_manage_screen.dart';
import 'admin_notice_manage_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';

class AdminEventManageScreen extends StatefulWidget {
  const AdminEventManageScreen({super.key});

  @override
  State<AdminEventManageScreen> createState() => _AdminEventManageScreenState();
}

class _AdminEventManageScreenState extends State<AdminEventManageScreen> {

  void _showEventDialog(BuildContext context, {Map<String, dynamic>? existing, int? index}) {
    String selectedType = existing?['type'] ?? 'text';
    final titleController = TextEditingController(text: existing?['title'] ?? '');
    final contentController = TextEditingController(
      text: existing?['type'] == 'text' ? (existing?['content'] ?? '') : '',
    );
    String currentImageUrl = existing?['type'] == 'image' ? (existing?['content'] ?? '') : '';
    Uint8List? selectedImageBytes;
    bool isUploading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing != null ? '이벤트 수정' : '이벤트 추가',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 타입 선택
                  const Text('표시 방식', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Radio<String>(
                        value: 'text',
                        groupValue: selectedType,
                        onChanged: (v) => setDialogState(() => selectedType = v!),
                        activeColor: const Color(0xFF00B37E),
                      ),
                      const Text('텍스트'),
                      const SizedBox(width: 24),
                      Radio<String>(
                        value: 'image',
                        groupValue: selectedType,
                        onChanged: (v) => setDialogState(() => selectedType = v!),
                        activeColor: const Color(0xFF00B37E),
                      ),
                      const Text('이미지'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 제목
                  const Text('제목', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '이벤트 제목 입력',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 내용 (타입에 따라 다르게)
                  if (selectedType == 'text') ...[
                    const Text('내용', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: contentController,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '이벤트 내용을 입력하세요',
                      ),
                    ),
                  ] else ...[
                    const Text('이미지', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
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
                                child: Image.memory(selectedImageBytes!, fit: BoxFit.contain),
                              )
                            : (currentImageUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(imageUrl: currentImageUrl, fit: BoxFit.contain,
                                        errorWidget: (c,u,e) =>
                                            const Icon(Icons.broken_image, size: 60, color: Colors.grey)),
                                  )
                                : const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_photo_alternate, size: 60, color: Colors.grey),
                                        SizedBox(height: 8),
                                        Text('클릭하여 이미지 선택', style: TextStyle(color: Colors.grey, fontSize: 16)),
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
            StatefulBuilder(
              builder: (context, setButtonState) => ElevatedButton(
                onPressed: isUploading
                    ? null
                    : () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('제목을 입력해주세요.'), backgroundColor: Colors.orange),
                          );
                          return;
                        }
                        setButtonState(() => isUploading = true);
                        try {
                          String content = '';
                          if (selectedType == 'text') {
                            content = contentController.text.trim();
                          } else {
                            if (selectedImageBytes != null) {
                              final ref = FirebaseStorage.instance
                                  .ref()
                                  .child('event_images/${DateTime.now().millisecondsSinceEpoch}.jpg');
                              final task = await ref.putData(selectedImageBytes!);
                              content = await task.ref.getDownloadURL();
                            } else {
                              content = currentImageUrl;
                            }
                          }

                          final newItem = {'type': selectedType, 'title': title, 'content': content};
                          final docRef = FirebaseFirestore.instance.collection('settings').doc('events');
                          final docSnap = await docRef.get();
                          List<dynamic> items =
                              docSnap.exists ? (docSnap.get('items') as List<dynamic>? ?? []) : [];

                          if (existing != null && index != null) {
                            items[index] = newItem;
                          } else {
                            items.add(newItem);
                          }
                          await docRef.set({'items': items});

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(existing != null ? '수정되었습니다.' : '등록되었습니다.'),
                              backgroundColor: const Color(0xFF00B37E),
                            ));
                          }
                        } catch (e) {
                          setButtonState(() => isUploading = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('에러: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B37E), foregroundColor: Colors.white),
                child: isUploading
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(existing != null ? '수정하기' : '추가하기',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEvent(BuildContext context, int index, List<dynamic> items) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('"${(items[index] as Map)['title']}" 이벤트를 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final newItems = List.from(items)..removeAt(index);
      await FirebaseFirestore.instance.collection('settings').doc('events').set({'items': newItems});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Row(
        children: [
          AdminSidebar(
            currentScreen: 'event',
            onNavigate: (screen) {
              final targets = <String, Widget>{
                'menu': const AdminMenuManageScreen(),
                'game': const AdminGameManageScreen(),
                'notice': const AdminNoticeManageScreen(),
              };
              final target = targets[screen];
              if (target != null) Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => target, transitionDuration: Duration.zero, reverseTransitionDuration: Duration.zero));
            },
          ),
          // 메인 영역
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('이벤트 관리', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        onPressed: () => _showEventDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('새 이벤트 추가', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00B37E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('앱의 이벤트 화면에 표시될 이벤트를 관리합니다.',
                      style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance.collection('settings').doc('events').snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          List<dynamic> items = [];
                          if (snapshot.hasData && snapshot.data!.exists) {
                            items = snapshot.data!.get('items') as List<dynamic>? ?? [];
                          }
                          if (items.isEmpty) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.campaign, size: 60, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text('등록된 이벤트가 없습니다.', style: TextStyle(color: Colors.grey, fontSize: 18)),
                                ],
                              ),
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = items[index] as Map<String, dynamic>;
                              final isImage = item['type'] == 'image';
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                leading: CircleAvatar(
                                  backgroundColor: isImage ? Colors.blue.shade50 : Colors.green.shade50,
                                  child: Icon(
                                    isImage ? Icons.image : Icons.text_fields,
                                    color: isImage ? Colors.blue : Colors.green,
                                  ),
                                ),
                                title: Text(item['title'] ?? '',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  isImage ? '[이미지 이벤트]' : (item['content'] ?? ''),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showEventDialog(context, existing: item, index: index),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                                      onPressed: () => _deleteEvent(context, index, items),
                                    ),
                                  ],
                                ),
                              );
                            },
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
}
