import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'admin_game_manage_screen.dart'; // 💡 추가!
import 'admin_event_manage_screen.dart';
import 'admin_notice_manage_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:boardpad/widgets/admin_sidebar.dart';

class AdminMenuManageScreen extends StatefulWidget {
  const AdminMenuManageScreen({super.key});

  @override
  State<AdminMenuManageScreen> createState() => _AdminMenuManageScreenState();
}

class _AdminMenuManageScreenState extends State<AdminMenuManageScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = '전체';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }


  void _editCategoryDialog(BuildContext context, List<dynamic> categories, int index) {
    final String oldName = categories[index];
    final TextEditingController editController = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('카테고리 수정'),
        content: TextField(controller: editController, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          ElevatedButton(
            onPressed: () async {
              final newName = editController.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                // 1. settings/categories 목록 업데이트
                categories[index] = newName;
                await FirebaseFirestore.instance
                    .collection('settings')
                    .doc('categories')
                    .set({'list': categories});

                // 2. 해당 카테고리를 가진 메뉴들도 일괄 업데이트
                final menus = await FirebaseFirestore.instance
                    .collection('menus')
                    .where('category', isEqualTo: oldName)
                    .get();
                final batch = FirebaseFirestore.instance.batch();
                for (final doc in menus.docs) {
                  batch.update(doc.reference, {'category': newName});
                }
                await batch.commit();
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('수정 완료'),
          )
        ],
      ),
    ).then((_) => editController.dispose());
  }

  // --- 1. 카테고리 관리 전용 팝업창 ---
  void _showCategoryManageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CategoryManageDialog(
        onEditCategory: (cats, idx) => _editCategoryDialog(context, cats, idx),
      ),
    );
  }
  // --- 💡 메뉴 삭제 확인 팝업창 ---
  Future<void> _deleteStorageImage(String url) async {
    if (url.isEmpty) return;
    try { await FirebaseStorage.instance.refFromURL(url).delete(); } catch (_) {}
  }

  void _confirmDeleteMenu(BuildContext context, String docId, String menuName, String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('메뉴 삭제', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
          content: Text('\'$menuName\' 메뉴를 정말 삭제하시겠습니까?\n삭제된 데이터는 복구할 수 없습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            ElevatedButton(
              onPressed: () async {
                // 💡 '삭제하기'를 누르면 Firestore에서 진짜로 삭제 후 팝업 닫기
                await _deleteStorageImage(imageUrl);
                await FirebaseFirestore.instance.collection('menus').doc(docId).delete();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              child: const Text('삭제하기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // --- 💡 1. 세부 옵션 '그룹'을 만드는 보조 팝업창 ---
  void _showAddOptionGroupDialog(BuildContext context, Function(Map<String, dynamic>) onGroupAdded) {
    final TextEditingController groupNameController = TextEditingController();
    final TextEditingController optNameController = TextEditingController();
    final TextEditingController optPriceController = TextEditingController();
    
    bool isRequired = false;
    List<Map<String, dynamic>> tempOptions = [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setGroupState) {
            return AlertDialog(
              title: const Text('옵션 카테고리 만들기', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: groupNameController,
                      decoration: const InputDecoration(labelText: '옵션 카테고리명 (예: 온도 선택, 당도 추가)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(value: isRequired, onChanged: (val) => setGroupState(() => isRequired = val ?? false), activeColor: const Color(0xFF00B37E)),
                        const Text('손님이 반드시 선택해야 하는 필수 옵션입니다.', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(height: 32),
                    const Text('세부 선택지 추가', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(flex: 2, child: TextField(controller: optNameController, decoration: const InputDecoration(labelText: '선택지명 (예: ICE)', border: OutlineInputBorder(), isDense: true))),
                        const SizedBox(width: 8),
                        Expanded(flex: 1, child: TextField(controller: optPriceController, decoration: const InputDecoration(labelText: '추가금(+)', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number)),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            if (optNameController.text.isNotEmpty) {
                              setGroupState(() {
                                tempOptions.add({'name': optNameController.text.trim(), 'price': int.tryParse(optPriceController.text.trim()) ?? 0});
                                optNameController.clear();
                                optPriceController.clear();
                              });
                            }
                          },
                          child: const Text('담기'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (tempOptions.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          children: tempOptions.asMap().entries.map((entry) => Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(' ✔️ ${entry.value['name']} (+${entry.value['price']}원)'),
                              IconButton(icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 16), onPressed: () => setGroupState(() => tempOptions.removeAt(entry.key))),
                            ],
                          )).toList(),
                        ),
                      )
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: () {
                    if (groupNameController.text.isEmpty || tempOptions.isEmpty) return;
                    onGroupAdded({
                      'groupName': groupNameController.text.trim(),
                      'isRequired': isRequired,
                      'options': tempOptions,
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B37E), foregroundColor: Colors.white),
                  child: const Text('그룹 완성하기', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- 💡 2. 새 메뉴 추가 & 기존 메뉴 수정 공용 팝업창 (옵션 그룹 로직 적용) ---
  void _showMenuDialog(BuildContext context, {Map<String, dynamic>? existingMenu, String? docId}) {
    final bool isEditMode = existingMenu != null && docId != null;

    final TextEditingController nameController = TextEditingController(text: isEditMode ? existingMenu['name'] : '');
    final TextEditingController priceController = TextEditingController(text: isEditMode ? existingMenu['price'].toString() : '');
    
    Uint8List? selectedImageBytes;
    String currentImageUrl = isEditMode ? (existingMenu['imageUrl'] ?? '') : '';
    bool isUploading = false;

    // 💡 단순 options 대신 optionGroups 배열을 사용하도록 변경!
    List<Map<String, dynamic>> optionGroups = isEditMode 
        ? List<Map<String, dynamic>>.from(existingMenu['optionGroups'] ?? []) 
        : [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        String? _dialogSelectedCategory;
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('settings').doc('categories').get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            List<String> categories = [];
            if (snapshot.data!.exists) {
              final list = snapshot.data!.get('list') as List<dynamic>? ?? [];
              categories = list.map((e) => e.toString()).toList();
            }
            if (categories.isEmpty) categories = ['기본 카테고리'];
            _dialogSelectedCategory ??= isEditMode && categories.contains(existingMenu['category']) ? existingMenu['category'] : categories.first;

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
                  title: Text(isEditMode ? '메뉴 수정' : '새 음식 메뉴 추가', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                                    ? CachedNetworkImage(imageUrl: currentImageUrl, fit: BoxFit.cover, errorWidget: (c,u,e) => const Icon(Icons.fastfood, color: Colors.grey))
                                    : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, color: Colors.grey, size: 32), SizedBox(height: 8), Text('사진 등록', style: TextStyle(color: Colors.grey))])),
                            ),
                          ),
                          const SizedBox(height: 24),
                          DropdownButtonFormField<String>(
                            value: _dialogSelectedCategory,
                            decoration: const InputDecoration(labelText: '카테고리', border: OutlineInputBorder()),
                            items: categories.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            onChanged: (value) => setState(() => _dialogSelectedCategory = value!),
                          ),
                          const SizedBox(height: 16),
                          TextField(controller: nameController, decoration: const InputDecoration(labelText: '메뉴 이름', border: OutlineInputBorder())),
                          const SizedBox(height: 16),
                          TextField(controller: priceController, decoration: const InputDecoration(labelText: '기본 가격 (원)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
                          const SizedBox(height: 24),
                          const Divider(height: 1),
                          const SizedBox(height: 16),

                          // 💡 그룹화된 세부 옵션 관리 영역
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('옵션 카테고리 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              OutlinedButton.icon(
                                onPressed: () {
                                  // 💡 버튼을 누르면 새로운 보조 팝업창이 열림
                                  _showAddOptionGroupDialog(context, (newGroup) {
                                    setState(() => optionGroups.add(newGroup));
                                  });
                                },
                                icon: const Icon(Icons.add_circle_outline, size: 18),
                                label: const Text('새 옵션 그룹 추가'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (optionGroups.isNotEmpty)
                            Column(
                              children: optionGroups.asMap().entries.map((entry) {
                                int idx = entry.key;
                                var group = entry.value;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('${group['groupName']} ${group['isRequired'] ? "(필수)" : "(선택)"}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                                            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => setState(() => optionGroups.removeAt(idx))),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          children: (group['options'] as List<dynamic>).map((opt) => Chip(
                                            label: Text('${opt['name']} (+${opt['price']}원)', style: const TextStyle(fontSize: 12)),
                                            backgroundColor: Colors.grey.shade100,
                                          )).toList(),
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: isUploading ? null : () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey, fontSize: 16))),
                    ElevatedButton(
                      onPressed: isUploading ? null : () async {
                        final name = nameController.text.trim();
                        final priceText = priceController.text.trim();
                        if (name.isEmpty || priceText.isEmpty) return;

                        setState(() => isUploading = true);
                        String finalImageUrl = currentImageUrl;
                        try {
                          if (selectedImageBytes != null) {
                            final storageRef = FirebaseStorage.instance.ref().child('menu_images/${DateTime.now().millisecondsSinceEpoch}.jpg');
                            final uploadTask = await storageRef.putData(selectedImageBytes!);
                            finalImageUrl = await uploadTask.ref.getDownloadURL();
                          }
                          final menuData = {
                            'category': _dialogSelectedCategory!, 
                            'name': name, 
                            'price': int.tryParse(priceText) ?? 0, 
                            'imageUrl': finalImageUrl, 
                            'optionGroups': optionGroups, // 💡 새로 업그레이드된 그룹 구조로 저장!
                          };

                          if (isEditMode) {
                            await FirebaseFirestore.instance.collection('menus').doc(docId).update(menuData);
                          } else {
                            menuData['isSoldOut'] = false;
                            menuData['timestamp'] = FieldValue.serverTimestamp();
                            await FirebaseFirestore.instance.collection('menus').add(menuData);
                          }
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEditMode ? '수정되었습니다.' : '등록되었습니다.')));
                          }
                        } catch (e) {
        debugPrint('Error: \$e');
                          setState(() => isUploading = false);
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장에 실패했습니다. 다시 시도해주세요.'), backgroundColor: Colors.red));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B37E), foregroundColor: Colors.white),
                      child: isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(isEditMode ? '수정하기' : '추가하기', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              },
            );
          }
        );
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
            currentScreen: 'menu',
            onNavigate: (screen) {
              final targets = <String, Widget>{
                'game': const AdminGameManageScreen(),
                'event': const AdminEventManageScreen(),
                'notice': const AdminNoticeManageScreen(),
              };
              final target = targets[screen];
              if (target != null) Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => target, transitionDuration: Duration.zero, reverseTransitionDuration: Duration.zero));
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('음식 메뉴 관리', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          SizedBox(
                            width: 260,
                            height: 44,
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: '메뉴 이름 또는 카테고리 검색',
                                prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey, size: 18), onPressed: () => setState(() { _searchController.clear(); _searchQuery = ''; }))
                                    : null,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              ),
                              onChanged: (val) => setState(() => _searchQuery = val),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 💡 카테고리 관리 버튼 추가!
                          OutlinedButton.icon(
                            onPressed: () => _showCategoryManageDialog(context),
                            icon: const Icon(Icons.category, color: Color(0xFF00B37E)),
                            label: const Text('카테고리 관리', style: TextStyle(color: Color(0xFF00B37E), fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF00B37E), width: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: () => _showMenuDialog(context),
                            icon: const Icon(Icons.add),
                            label: const Text('새 메뉴 추가', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B37E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('settings').doc('categories').snapshots(),
                    builder: (context, catSnap) {
                      final List<String> catList = (catSnap.hasData && catSnap.data!.exists)
                          ? List<String>.from((catSnap.data!.data() as Map? ?? {})['list'] ?? [])
                          : [];
                      final allCats = ['전체', ...catList];
                      if (!allCats.contains(_selectedCategory)) _selectedCategory = '전체';
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: allCats.map((cat) {
                            final isSelected = _selectedCategory == cat;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(cat),
                                selected: isSelected,
                                selectedColor: const Color(0xFF00B37E),
                                labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                                onSelected: (_) => setState(() => _selectedCategory = cat),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('menus').orderBy('timestamp').snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                          final allMenus = snapshot.data?.docs ?? [];
                          final menus = allMenus.where((doc) {
                                  final m = doc.data() as Map<String, dynamic>;
                                  final name = (m['name'] ?? '').toString().toLowerCase();
                                  final category = (m['category'] ?? '').toString();
                                  final q = _searchQuery.toLowerCase();
                                  final matchesSearch = _searchQuery.isEmpty || name.contains(q) || category.toLowerCase().contains(q);
                                  final matchesCat = _selectedCategory == '전체' || category == _selectedCategory;
                                  return matchesSearch && matchesCat;
                                }).toList();
                          if (menus.isEmpty) return const Center(child: Text('해당하는 메뉴가 없습니다.', style: TextStyle(color: Colors.grey)));

                          return ListView.separated(
                            itemCount: menus.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final doc = menus[index];
                              final menu = doc.data() as Map<String, dynamic>;
                              final options = menu['optionGroups'] as List<dynamic>? ?? [];
                              
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 56, height: 56, color: Colors.grey.shade200,
                                    child: (menu['imageUrl'] != null && menu['imageUrl'].toString().isNotEmpty)
                                        ? CachedNetworkImage(imageUrl: menu['imageUrl'], fit: BoxFit.cover, errorWidget: (c,u,e) => const Icon(Icons.fastfood, color: Colors.grey))
                                        : const Icon(Icons.fastfood, color: Colors.grey),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Text(menu['name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    if (options.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)), child: Text('옵션 ${options.length}개', style: const TextStyle(fontSize: 12, color: Colors.blue)))
                                    ]
                                  ],
                                ),
                                subtitle: Text('${menu['category']} | ${menu['price']}원'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(value: !(menu['isSoldOut'] ?? false), onChanged: (val) => FirebaseFirestore.instance.collection('menus').doc(doc.id).update({'isSoldOut': !val}), activeColor: const Color(0xFF00B37E)),
                                    Text((menu['isSoldOut'] ?? false) ? '품절' : '판매중', style: TextStyle(color: (menu['isSoldOut'] ?? false) ? Colors.red : Colors.black87, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 24),
                                    IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showMenuDialog(context, existingMenu: menu, docId: doc.id)),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () {
                                        // 💡 바로 지우지 않고 팝업창을 먼저 띄움
                                        _confirmDeleteMenu(
                                          context,
                                          doc.id,
                                          menu['name'] ?? '이 메뉴',
                                          (menu['imageUrl'] ?? '').toString(),
                                        );
                                      },
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

// ── 카테고리 관리 다이얼로그 전용 위젯 (컨트롤러·구독 lifecycle 보장) ─────────
class _CategoryManageDialog extends StatefulWidget {
  final void Function(List<dynamic> categories, int index) onEditCategory;

  const _CategoryManageDialog({required this.onEditCategory});

  @override
  State<_CategoryManageDialog> createState() => _CategoryManageDialogState();
}

class _CategoryManageDialogState extends State<_CategoryManageDialog> {
  final TextEditingController _newCategoryController = TextEditingController();

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('카테고리 관리', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('settings')
                  .doc('categories')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }

                List<dynamic> categories = [];
                if (snapshot.hasData && snapshot.data!.exists) {
                  categories = List<dynamic>.from(
                      (snapshot.data!.data() as Map? ?? {})['list'] ?? []);
                }

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newCategoryController,
                            decoration: const InputDecoration(
                              labelText: '새 카테고리명',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final text = _newCategoryController.text.trim();
                            if (text.isNotEmpty && !categories.contains(text)) {
                              categories.add(text);
                              await FirebaseFirestore.instance
                                  .collection('settings')
                                  .doc('categories')
                                  .set({'list': categories});
                              _newCategoryController.clear();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B37E),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('추가'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    categories.isEmpty
                        ? const Text('등록된 카테고리가 없습니다.',
                            style: TextStyle(color: Colors.grey))
                        : Container(
                            constraints: const BoxConstraints(maxHeight: 300),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: categories.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final cat = categories[index];
                                return ListTile(
                                  title: Text(cat),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit,
                                            color: Colors.blue),
                                        onPressed: () => widget.onEditCategory(
                                            categories, index),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: Colors.redAccent),
                                        onPressed: () async {
                                          categories.removeAt(index);
                                          await FirebaseFirestore.instance
                                              .collection('settings')
                                              .doc('categories')
                                              .set({'list': categories});
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기',
              style: TextStyle(color: Colors.grey, fontSize: 16)),
        ),
      ],
    );
  }
}
