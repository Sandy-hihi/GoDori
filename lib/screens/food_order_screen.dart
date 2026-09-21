import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/services/staff_call_service.dart';

class FoodOrderScreen extends StatefulWidget {
  final int? roomNumber;

  const FoodOrderScreen({super.key, this.roomNumber});

  @override
  State<FoodOrderScreen> createState() => _FoodOrderScreenState();
}

class _FoodOrderScreenState extends State<FoodOrderScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _noteController = TextEditingController();

  bool _isSubmitting = false;

  // 💡 1. 장바구니 구조 확장 (메뉴명(옵션) : {단가, 수량})
  Map<String, Map<String, dynamic>> cart = {};

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // 💡 2. 장바구니 담기 (옵션 및 합산 가격 반영)
  void _addToCartWithOptions(Map<String, dynamic> menu, List<String> selectedOptions, int additionalPrice) {
    String baseName = menu['name'] ?? '이름 없음';
    int basePrice = menu['price'] is int ? menu['price'] : int.tryParse(menu['price'].toString()) ?? 0;
    
    int finalPrice = basePrice + additionalPrice;
    String optionsText = selectedOptions.isNotEmpty ? '(${selectedOptions.join(', ')})' : '';
    String cartKey = '$baseName $optionsText'.trim(); // 예: 아메리카노 (HOT, 샷 추가)

    setState(() {
      if (cart.containsKey(cartKey)) {
        cart[cartKey]!['quantity'] = (cart[cartKey]!['quantity'] as num).toInt() + 1;
      } else {
        cart[cartKey] = {'unitPrice': finalPrice, 'quantity': 1};
      }
    });
    
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$cartKey 담겼습니다.'), duration: const Duration(seconds: 1), backgroundColor: const Color(0xFF00B37E)),
    );
  }

  // 수량 조절 및 삭제
  void _updateQuantity(String cartKey, int delta) {
    setState(() {
      int current = cart[cartKey]?['quantity'] ?? 0;
      if (current + delta > 0) {
        cart[cartKey]!['quantity'] = current + delta;
      } else {
        cart.remove(cartKey);
      }
    });
  }

  // 💡 3. 총 결제 금액 계산 (장바구니 내부의 unitPrice 활용)
  int _getTotalPrice() {
    int total = 0;
    cart.forEach((key, item) {
      total += (item['unitPrice'] as num).toInt() * (item['quantity'] as num).toInt();
    });
    return total;
  }

  // 장바구니 총 수량 계산
  int _getTotalCount() => cart.values.fold(0, (sum, item) => sum + (item['quantity'] as num).toInt());

  // 💡 4. 옵션 선택 팝업창 (선택 옵션도 단일 선택으로 변경 완료)
  void _showMenuOptionDialog(BuildContext context, Map<String, dynamic> menu) {
    final List<dynamic> optionGroups = menu['optionGroups'] ?? [];
    
    // 옵션이 아예 없는 메뉴면 팝업 없이 바로 장바구니에 1개 담기
    if (optionGroups.isEmpty) {
      _addToCartWithOptions(menu, [], 0);
      return;
    }

    // 그룹별 선택된 옵션을 저장할 상태 변수 (필수는 첫 번째 항목 자동 선택)
    Map<int, List<Map<String, dynamic>>> selectedOptionsMap = {};
    for (int i = 0; i < optionGroups.length; i++) {
      if (optionGroups[i]['isRequired'] == true && (optionGroups[i]['options'] as List).isNotEmpty) {
        selectedOptionsMap[i] = [optionGroups[i]['options'][0]]; 
      } else {
        selectedOptionsMap[i] = [];
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            int basePrice = menu['price'] is int ? menu['price'] : int.tryParse(menu['price'].toString()) ?? 0;
            int additionalPrice = 0;
            
            selectedOptionsMap.values.forEach((list) {
              list.forEach((opt) => additionalPrice += (opt['price'] as int? ?? 0));
            });
            int totalPrice = basePrice + additionalPrice;

            return AlertDialog(
              title: Text('${menu['name']} 옵션 선택', style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: optionGroups.asMap().entries.map((entry) {
                      int gIndex = entry.key;
                      var group = entry.value;
                      bool isRequired = group['isRequired'] ?? false;
                      List<dynamic> opts = group['options'] ?? [];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('${group['groupName']} ${isRequired ? "(필수)" : "(선택)"}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent)),
                          ),
                          // 💡 여기서부터 수정됨! (체크박스를 없애고 모두 라디오 버튼으로 통일)
                          ...opts.map((opt) {
                            String titleText = '${opt['name']} (+${opt['price']}원)';

                            return RadioListTile<String>(
                              title: Text(titleText),
                              value: opt['name'],
                              groupValue: selectedOptionsMap[gIndex]?.isNotEmpty == true ? selectedOptionsMap[gIndex]!.first['name'] : null,
                              // 💡 핵심: 선택 옵션(!isRequired)은 한 번 더 누르면 취소할 수 있음!
                              toggleable: !isRequired,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == null) {
                                    selectedOptionsMap[gIndex] = []; // 선택 취소됨
                                  } else {
                                    selectedOptionsMap[gIndex] = [opt]; // 오직 1개만 덮어씌워서 선택됨
                                  }
                                });
                              },
                              activeColor: const Color(0xFF00B37E),
                            );
                          }).toList(),
                          const Divider(),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: () {
                    List<String> finalOptions = [];
                    selectedOptionsMap.values.forEach((list) => list.forEach((opt) => finalOptions.add(opt['name'])));
                    _addToCartWithOptions(menu, finalOptions, additionalPrice);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B37E), foregroundColor: Colors.white),
                  child: Text('$totalPrice원 담기', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF4F6F8),
      
      floatingActionButton: FloatingActionButton(
        onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        backgroundColor: const Color(0xFF007E5B),
        child: Badge(
          isLabelVisible: cart.isNotEmpty,
          label: Text('${_getTotalCount()}'),
          child: const Icon(Icons.shopping_cart, color: Colors.white, size: 28),
        ),
      ),
      
      // 장바구니 서랍 부분
      endDrawer: Drawer(
        width: MediaQuery.of(context).size.width * 0.4,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: const Color(0xFF00B37E),
                child: const Row(
                  children: [
                    Icon(Icons.shopping_cart_checkout, color: Colors.white),
                    SizedBox(width: 8),
                    Text('장바구니', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: cart.isEmpty
                    ? const Center(child: Text('장바구니가 비어있습니다.', style: TextStyle(fontSize: 18, color: Colors.grey)))
                    : ListView.builder(
                        itemCount: cart.length,
                        itemBuilder: (context, index) {
                          String cartKey = cart.keys.elementAt(index);
                          int quantity = cart[cartKey]!['quantity'];
                          int unitPrice = cart[cartKey]!['unitPrice'];
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              title: Text(cartKey, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text('${unitPrice * quantity}원', style: const TextStyle(color: Colors.blueAccent)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _updateQuantity(cartKey, -1)),
                                  Text('$quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _updateQuantity(cartKey, 1)),
                                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => cart.remove(cartKey))),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('총 결제금액', style: TextStyle(fontSize: 18)),
                        Text('${_getTotalPrice()}원', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _noteController,
                      decoration: InputDecoration(
                        hintText: '요청사항을 입력해주세요 (예: 얼음 적게)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: cart.isEmpty || _isSubmitting ? null : () async {
                          setState(() => _isSubmitting = true);
                          try {
                            List<String> orderItems = [];
                            cart.forEach((cartKey, item) => orderItems.add('$cartKey x ${item['quantity']}'));

                            final now = DateTime.now();
                            final timeString = '${now.hour}시 ${now.minute.toString().padLeft(2, '0')}분';

                            await FirebaseFirestore.instance.collection('orders').add({
                              'room': '#${widget.roomNumber ?? 1}',
                              'time': timeString,
                              'price': _getTotalPrice().toString(),
                              'items': orderItems,
                              'notes': _noteController.text.isEmpty ? '추가사항 없음' : _noteController.text,
                              'roomColor': 0xFFC2365A,
                              'status': 'pending',
                              'timestamp': FieldValue.serverTimestamp(),
                            });

                            if (mounted) setState(() { cart.clear(); _noteController.clear(); _isSubmitting = false; });
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('주문이 전송되었습니다! 🚀'), backgroundColor: Color(0xFF00B37E)),
                              );
                            }
                          } catch (e) {
                            debugPrint('Order error: $e');
                            if (mounted) setState(() => _isSubmitting = false);
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('주문 전송에 실패했습니다. 다시 시도해주세요.'), backgroundColor: Colors.red),
                            );
                          }
                        }, 
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007E5B), foregroundColor: Colors.white),
                        child: const Text('주문하기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // 메인 화면 (탭 + 메뉴 리스트)
      body: Row(
        children: [
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  // 상단 바
                  Container(
                    color: const Color(0xFF00B37E),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                        ClipOval(child: Image.asset('assets/images/logo.jpg', width: 40, height: 40, fit: BoxFit.cover)),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: () => StaffCallService.callStaff(context, widget.roomNumber ?? 0),
                          icon: const Icon(Icons.notifications_active),
                          label: const Text('직원 호출', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007E5B), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                        ),
                        const SizedBox(width: 16),
                        const Text('플랫폼6 보드카페', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  
                  // 카테고리 탭 & 메뉴 리스트
                  Expanded(
                    child: StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('settings').doc('categories').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                        
                        List<dynamic> categories = [];
                        if (snapshot.hasData && snapshot.data!.exists) {
                          categories = snapshot.data!.get('list') ?? [];
                        }
                        
                        if (categories.isEmpty) return const Center(child: Text('등록된 카테고리가 없습니다.'));

                        return DefaultTabController(
                          length: categories.length,
                          child: Builder(
                            builder: (BuildContext context) {
                              final TabController tabController = DefaultTabController.of(context);

                              // Fix #4: 단일 StreamBuilder로 전체 메뉴를 한 번에 구독 → N→1 구독으로 최적화
                              return StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('menus')
                                    .snapshots(),
                                builder: (context, menuSnapshot) {
                                  final allMenuDocs = menuSnapshot.data?.docs ?? [];

                              return Column(
                                children: [
                                  Container(
                                    color: const Color(0xFFE5E7EB),
                                    child: TabBar(
                                      isScrollable: true,
                                      indicatorColor: const Color(0xFF00B37E),
                                      labelColor: Colors.black,
                                      unselectedLabelColor: Colors.grey[700],
                                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      tabs: categories.map((title) => Tab(text: title.toString())).toList(),
                                    ),
                                  ),
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        // TabBarView는 AnimatedBuilder 밖에 두어 탭 전환 시 재빌드 방지
                                        // 각 탭은 단일 StreamBuilder에서 받은 allMenuDocs를 카테고리별로 클라이언트 사이드 필터링
                                        TabBarView(
                                          children: categories.map((category) {
                                            // 로딩 중이고 아직 데이터가 없는 경우
                                            if (menuSnapshot.connectionState == ConnectionState.waiting && allMenuDocs.isEmpty) {
                                              return const Center(child: CircularProgressIndicator());
                                            }

                                            // 해당 카테고리 + 품절 아닌 메뉴만 클라이언트 사이드 필터링
                                            final menus = allMenuDocs.where((doc) {
                                              final data = doc.data() as Map<String, dynamic>;
                                              final bool isSoldOut = data['isSoldOut'] == true || data['isSoldOut'] == 'true';
                                              return data['category'] == category && !isSoldOut;
                                            }).toList();

                                            if (menus.isEmpty) {
                                              return const Center(child: Text('이 카테고리에 등록된 메뉴가 없습니다.', style: TextStyle(fontSize: 16, color: Colors.grey)));
                                            }

                                            return Padding(
                                              padding: const EdgeInsets.all(16.0),
                                              child: GridView.builder(
                                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 4,
                                                  childAspectRatio: 0.75,
                                                  crossAxisSpacing: 16,
                                                  mainAxisSpacing: 16,
                                                ),
                                                itemCount: menus.length,
                                                itemBuilder: (context, index) {
                                                  final menuData = menus[index].data() as Map<String, dynamic>;
                                                  return _buildMenuCard(menuData);
                                                },
                                              ),
                                            );
                                          }).toList(),
                                        ),

                                        // 화살표 버튼만 AnimatedBuilder로 감싸 탭 인덱스 변화에만 반응
                                        AnimatedBuilder(
                                          animation: tabController,
                                          builder: (context, child) {
                                            return Stack(
                                              children: [
                                                // 좌측 화살표
                                                if (tabController.index > 0)
                                                  Align(
                                                    alignment: Alignment.centerLeft,
                                                    child: Padding(
                                                      padding: const EdgeInsets.only(left: 8.0),
                                                      child: FloatingActionButton(
                                                        heroTag: 'prev_btn',
                                                        backgroundColor: Colors.white.withValues(alpha: 0.9),
                                                        foregroundColor: const Color(0xFF00B37E),
                                                        elevation: 4,
                                                        onPressed: () => tabController.animateTo(tabController.index - 1),
                                                        child: const Icon(Icons.chevron_left, size: 36),
                                                      ),
                                                    ),
                                                  ),

                                                // 우측 화살표
                                                if (tabController.index < categories.length - 1)
                                                  Align(
                                                    alignment: Alignment.centerRight,
                                                    child: Padding(
                                                      padding: const EdgeInsets.only(right: 8.0),
                                                      child: FloatingActionButton(
                                                        heroTag: 'next_btn',
                                                        backgroundColor: Colors.white.withValues(alpha: 0.9),
                                                        foregroundColor: const Color(0xFF00B37E),
                                                        elevation: 4,
                                                        onPressed: () => tabController.animateTo(tabController.index + 1),
                                                        child: const Icon(Icons.chevron_right, size: 36),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                                }, // StreamBuilder builder 끝
                              ); // StreamBuilder 끝
                            }
                          ),
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

  // 💡 5. 카드 클릭 시 팝업창을 부르도록 수정된 메뉴 카드
  Widget _buildMenuCard(Map<String, dynamic> menuData) {
    final String name = menuData['name'] ?? '이름 없음';
    final int price = menuData['price'] is int ? menuData['price'] : int.tryParse(menuData['price'].toString()) ?? 0;
    final String? imageUrl = menuData['imageUrl']; 

    return GestureDetector(
      onTap: () => _showMenuOptionDialog(context, menuData), // 클릭 시 팝업 띄우기
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Container(
                  color: const Color(0xFFF8F9FA),
                  child: (hasValidImage(imageUrl))
                      ? CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover, errorWidget: (c,u,e) => const Icon(Icons.fastfood, color: Colors.grey))
                      : const Center(child: Icon(Icons.image_outlined, size: 48, color: Colors.grey)),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('$price 원', style: const TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}