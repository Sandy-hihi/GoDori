import 'package:boardpad/l10n/guest_language.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/models/order_flow.dart';
import 'package:boardpad/services/order_flow_service.dart';
import 'package:boardpad/services/store_features.dart';
import 'package:boardpad/services/toss_pos_service.dart';
import 'package:boardpad/services/insight_service.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/widgets/pad_shell.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/usage_meter.dart';

class FoodOrderScreen extends StatefulWidget {
  final int? roomNumber;
  final String? initialMenuId;

  const FoodOrderScreen({super.key, this.roomNumber, this.initialMenuId});

  @override
  State<FoodOrderScreen> createState() => _FoodOrderScreenState();
}

class _FoodOrderScreenState extends State<FoodOrderScreen> {
  final TextEditingController _noteController = TextEditingController();
  late final Stream<DocumentSnapshot> _categoryStream =
      StoreScope.col('settings').doc('categories').snapshots();
  // 전체 메뉴를 한 번에 구독 → 카테고리별로 화면에서 나눔 (구독 1개)
  late final Stream<QuerySnapshot> _menuStream = StoreScope.col('menus').snapshots().metered();

  bool _isSubmitting = false;
  String? _selectedCategory;

  // 음식 수령 방식 (매장 설정 — 방으로 가져다 드림 / 카운터 수령 / 카운터 결제 후 수령, 58차)
  OrderFlow _flow = OrderFlow.fallback;
  StreamSubscription<OrderFlow>? _flowSub;

  // 토스 POS 연동(59·64차)을 켠 매장이면 주문 직후 서버에 '포스로 보내기'를 부탁함
  bool _tossPos = false;
  StreamSubscription<StoreFeatures>? _featuresSub;

  // ── 인피니티 스크롤: 모든 카테고리를 한 목록에 이어 붙이고, 마지막 카테고리 다음에 다시 처음 카테고리가
  //    끝없이 반복됨. 위 버튼과 스크롤 위치를 서로 맞춤 ──
  final ScrollController _scroll = ScrollController();
  List<String> _sections = []; // 메뉴가 있는 카테고리 (화면 순서)
  List<double> _sectionTops = []; // 한 바퀴 안에서 각 카테고리 제목의 위치
  double _cycleH = 0; // 한 바퀴(모든 카테고리 한 번)의 높이
  bool _jumping = false; // 버튼을 눌러 이동하는 중에는 스크롤 감지로 버튼을 바꾸지 않음
  final Map<String, GlobalKey> _pillKeys = {};

  static const double _sectionHeaderH = 58;
  static const double _sectionGapBottom = 28;
  static const double _cardH = 250;
  static const double _cardMinW = 220;
  static const double _gridGap = 16;
  static const double _loopMarkH = 64; // 한 바퀴 끝 '처음으로' 표시

  // 장바구니 (메뉴명(옵션) : {단가, 수량, + 포스용 메뉴 ID·이름·카테고리·기본가·옵션 목록(64차)})
  Map<String, Map<String, dynamic>> cart = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _flowSub = OrderFlowService.watch().listen((f) {
      if (mounted) setState(() => _flow = f);
    });
    _featuresSub = StoreFeaturesService.watch().listen((f) => _tossPos = f.tossPos);
    if (widget.initialMenuId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialMenu());
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _scroll.dispose();
    _flowSub?.cancel();
    _featuresSub?.cancel();
    super.dispose();
  }

  // 메인 화면 '오늘의 추천 메뉴'에서 들어오면 그 메뉴의 옵션 창을 바로 띄움
  Future<void> _openInitialMenu() async {
    try {
      final doc = await StoreScope.col('menus').doc(widget.initialMenuId).get();
      if (!mounted) return;
      final menu = doc.data();
      if (menu == null || menu['isSoldOut'] == true || menu['isSoldOut'] == 'true') {
        padSnack(context, '선택한 메뉴가 없어졌거나 품절이에요. 다른 메뉴를 골라 주세요.');
        return;
      }
      menu['_id'] = doc.id; // 포스용 메뉴 ID (64차)
      _showMenuOptionDialog(context, menu);
    } catch (_) {
      if (!mounted) return;
      padSnack(context, '선택한 메뉴를 불러오지 못했어요. 목록에서 다시 골라 주세요.', error: true);
    }
  }

  static bool _isSoldOut(Map<String, dynamic> m) => m['isSoldOut'] == true || m['isSoldOut'] == 'true';

  static int _price(dynamic v) => v is int ? v : int.tryParse((v ?? '').toString()) ?? 0;

  static String _won(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$buf원';
  }

  // 장바구니 담기 (옵션 및 합산 가격 반영)
  // optionDetails: 고른 옵션 [{group: 옵션 그룹 이름, name, price}] — 토스 POS로 보낼 때 씀(64차)
  void _addToCartWithOptions(Map<String, dynamic> menu, List<String> selectedOptions, int additionalPrice,
      {List<Map<String, dynamic>> optionDetails = const []}) {
    String baseName = menu['name'] ?? '이름 없음';
    int finalPrice = _price(menu['price']) + additionalPrice;
    String optionsText = selectedOptions.isNotEmpty ? '(${selectedOptions.join(', ')})' : '';
    String cartKey = '$baseName $optionsText'.trim(); // 예: 아메리카노 (HOT, 샷 추가)

    setState(() {
      if (cart.containsKey(cartKey)) {
        cart[cartKey]!['quantity'] = (cart[cartKey]!['quantity'] as num).toInt() + 1;
      } else {
        cart[cartKey] = {
          'unitPrice': finalPrice,
          'quantity': 1,
          'menuId': (menu['_id'] ?? '').toString(),
          'name': baseName,
          'category': (menu['category'] ?? '').toString(),
          'basePrice': _price(menu['price']),
          'options': optionDetails,
        };
      }
    });
    padSnack(context, '$cartKey 담았어요');
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

  int _getTotalPrice() {
    int total = 0;
    cart.forEach((key, item) {
      total += (item['unitPrice'] as num).toInt() * (item['quantity'] as num).toInt();
    });
    return total;
  }

  int _getTotalCount() => cart.values.fold(0, (total, item) => total + (item['quantity'] as num).toInt());

  // 주문 보내기 (orders 컬렉션 — 관리자 대시보드가 실시간으로 받음)
  Future<void> _submitOrder() async {
    setState(() => _isSubmitting = true);
    try {
      List<String> orderItems = [];
      cart.forEach((cartKey, item) => orderItems.add('$cartKey x ${item['quantity']}'));
      // 메뉴별 구조 (64차) — 서버가 토스 POS 주문으로 바꿀 때 씀. 화면 표시는 위 items 그대로
      final lines = [
        for (final item in cart.values)
          {
            'menuId': item['menuId'] ?? '',
            'name': item['name'] ?? '',
            'category': item['category'] ?? '',
            'basePrice': item['basePrice'] ?? item['unitPrice'],
            'quantity': item['quantity'],
            'options': item['options'] ?? const [],
          },
      ];

      final now = DateTime.now();
      final timeString = '${now.hour}시 ${now.minute.toString().padLeft(2, '0')}분';

      await AdminSession.ensureSignedIn(); // 보안 규칙: 로그인한 그 방 패드만, 자기 방 번호로 주문 가능
      final ref = await StoreScope.col('orders').add({
        'room': '#${widget.roomNumber ?? 1}',
        'time': timeString,
        'price': _getTotalPrice().toString(),
        'items': orderItems,
        'notes': _noteController.text.isEmpty ? '추가사항 없음' : _noteController.text,
        'roomColor': 0xFFC2365A,
        'status': 'pending',
        'flow': _flow.id, // 이 주문의 수령 방식 — 주문현황 버튼 흐름·패드 준비 완료 알림이 이걸 따름
        'timestamp': FieldValue.serverTimestamp(),
        'lines': lines,
      });
      // 토스 POS로 보내기 — 기다리지 않음. 실패하면 서버가 주문에 적어 두고 관리자 화면에서 '다시 보내기'
      if (_tossPos) unawaited(TossPosService.sendOrder(ref.id).catchError((_) => <String, dynamic>{}));
      // 매장 통계(65차, 운영자 페이지 인기 메뉴) — 기다리지 않음, 실패해도 손님 화면엔 영향 없음
      unawaited(InsightService.countOrder(ref.id));

      if (!mounted) return;
      setState(() {
        cart.clear();
        _noteController.clear();
        _isSubmitting = false;
      });
      _showOrderDone();
    } catch (e) {
      debugPrint('Order error: $e');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      padSnack(context, '주문을 보내지 못했어요. 다시 눌러 주세요.', error: true);
    }
  }

  void _showOrderDone() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(32, 32, 32, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: kOrange, size: 64),
            const SizedBox(height: 12),
            const GuestText('주문이 접수됐어요', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
            const SizedBox(height: 6),
            GuestText(_flow.orderDoneText,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: kMuted, height: 1.4)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: kInk,
              minimumSize: const Size(160, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const GuestText('확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // 옵션 선택 팝업 (그룹마다 하나씩 선택, 선택 옵션은 다시 누르면 취소)
  void _showMenuOptionDialog(BuildContext context, Map<String, dynamic> menu) {
    final List<dynamic> optionGroups = menu['optionGroups'] ?? [];

    // 옵션이 아예 없는 메뉴면 팝업 없이 바로 장바구니에 1개 담기
    if (optionGroups.isEmpty) {
      _addToCartWithOptions(menu, [], 0);
      return;
    }

    // 그룹별 선택된 옵션 (필수는 첫 번째 항목 자동 선택)
    Map<int, List<Map<String, dynamic>>> selectedOptionsMap = {};
    for (int i = 0; i < optionGroups.length; i++) {
      if (optionGroups[i]['isRequired'] == true && (optionGroups[i]['options'] as List).isNotEmpty) {
        selectedOptionsMap[i] = [optionGroups[i]['options'][0]];
      } else {
        selectedOptionsMap[i] = [];
      }
    }

    final imageUrl = menu['imageUrl']?.toString();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            int basePrice = _price(menu['price']);
            int additionalPrice = 0;
            for (var list in selectedOptionsMap.values) {
              for (var opt in list) {
                additionalPrice += (opt['price'] as int? ?? 0);
              }
            }
            int totalPrice = basePrice + additionalPrice;

            return Dialog(
              backgroundColor: kBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 12, 6),
                      child: Row(
                        children: [
                          if (hasValidImage(imageUrl)) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: AppNetworkImage(imageUrl: imageUrl!, width: 64, height: 64, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 14),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GuestText(guestField(context, menu, 'name'),
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
                                GuestText(_won(basePrice), style: const TextStyle(fontSize: 15, color: kMuted)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: kMuted),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: optionGroups.asMap().entries.map((entry) {
                            int gIndex = entry.key;
                            var group = entry.value;
                            bool isRequired = group['isRequired'] ?? false;
                            List<dynamic> opts = group['options'] ?? [];
                            final selectedName = selectedOptionsMap[gIndex]?.isNotEmpty == true
                                ? selectedOptionsMap[gIndex]!.first['name']
                                : null;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      GuestText(guestField(context, group as Map, 'groupName'), // 83차: 자동 번역
                                          style: const TextStyle(
                                              fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isRequired ? kOrange : Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: isRequired ? kOrange : kLine),
                                        ),
                                        child: GuestText(isRequired ? '필수' : '선택',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: isRequired ? Colors.white : kMuted,
                                            )),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final opt in opts)
                                        _optionChip(
                                          name: guestField(context, opt, 'name'),
                                          price: (opt['price'] as int? ?? 0),
                                          selected: selectedName == opt['name'],
                                          onTap: () => setDialogState(() {
                                            if (selectedName == opt['name']) {
                                              // 선택 옵션은 다시 누르면 취소 (필수는 그대로)
                                              if (!isRequired) selectedOptionsMap[gIndex] = [];
                                            } else {
                                              selectedOptionsMap[gIndex] = [
                                                Map<String, dynamic>.from(opt as Map),
                                              ];
                                            }
                                          }),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: SizedBox(
                        height: 58,
                        child: FilledButton(
                          onPressed: () {
                            List<String> finalOptions = [];
                            final details = <Map<String, dynamic>>[];
                            for (final e in selectedOptionsMap.entries) {
                              for (var opt in e.value) {
                                finalOptions.add(opt['name']);
                                details.add({
                                  'group': '${optionGroups[e.key]['groupName'] ?? ''}',
                                  'name': '${opt['name'] ?? ''}',
                                  'price': (opt['price'] as int? ?? 0),
                                });
                              }
                            }
                            _addToCartWithOptions(menu, finalOptions, additionalPrice, optionDetails: details);
                            Navigator.pop(context);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: kOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: GuestText('${_won(totalPrice)} 담기',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _optionChip({required String name, required int price, required bool selected, required VoidCallback onTap}) {
    return Material(
      color: selected ? kInk : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 110),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? kInk : kLine),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GuestText(name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : kInk,
                  )),
              GuestText(price > 0 ? '+${_won(price)}' : '추가 금액 없음',
                  style: TextStyle(fontSize: 12, color: selected ? Colors.white70 : kMuted)),
            ],
          ),
        ),
      ),
    );
  }

  // 스크롤하면 지금 보고 있는 카테고리 버튼을 켬 (몇 바퀴째든 한 바퀴 안의 위치로 계산)
  void _onScroll() {
    if (_jumping || _sectionTops.isEmpty || _cycleH <= 0 || !_scroll.hasClients) return;
    final y = (_scroll.offset + 12) % _cycleH;
    var idx = 0;
    for (var i = 0; i < _sectionTops.length; i++) {
      if (_sectionTops[i] <= y) idx = i;
    }
    final c = _sections[idx];
    if (c != _selectedCategory) {
      setState(() => _selectedCategory = c);
      _revealPill(c);
    }
  }

  // 카테고리 버튼을 누르면 지금 바퀴 안의 그 카테고리로 스크롤
  void _jumpTo(String category) {
    final idx = _sections.indexOf(category);
    if (idx < 0 || _cycleH <= 0 || !_scroll.hasClients) return;
    setState(() => _selectedCategory = category);
    _revealPill(category);
    final base = (_scroll.offset / _cycleH).floor() * _cycleH;
    final target = base + _sectionTops[idx];
    _jumping = true;
    _scroll
        .animateTo(target, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic)
        .whenComplete(() => _jumping = false);
  }

  // 켜진 버튼이 버튼 줄 밖에 있으면 보이게 옆으로 밀어 줌
  void _revealPill(String category) {
    final ctx = _pillKeys[category]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _categoryStream,
      builder: (context, catSnap) {
        List<String> categories = [];
        if (catSnap.hasData && catSnap.data!.exists) {
          categories = List<dynamic>.from((catSnap.data!.data() as Map? ?? {})['list'] ?? [])
              .map((e) => e.toString())
              .toList();
        }
        return StreamBuilder<QuerySnapshot>(
          stream: _menuStream,
          builder: (context, menuSnap) {
            final loading = catSnap.connectionState == ConnectionState.waiting ||
                (menuSnap.connectionState == ConnectionState.waiting && !menuSnap.hasData);

            // 카테고리별 메뉴. 품절 메뉴도 보여 주되 '품절'로 표시하고 카테고리 맨 뒤로. 메뉴가 없는 카테고리는 건너뜀
            final byCategory = <String, List<Map<String, dynamic>>>{};
            for (final doc in menuSnap.data?.docs ?? const <QueryDocumentSnapshot>[]) {
              final data = doc.data() as Map<String, dynamic>;
              data['_id'] = doc.id; // 포스용 메뉴 ID (64차)
              byCategory.putIfAbsent((data['category'] ?? '').toString(), () => []).add(data);
            }
            for (final list in byCategory.values) {
              final open = list.where((m) => !_isSoldOut(m)).toList();
              final soldOut = list.where(_isSoldOut).toList();
              list
                ..clear()
                ..addAll(open)
                ..addAll(soldOut);
            }
            _sections = [for (final c in categories) if (byCategory[c]?.isNotEmpty == true) c];
            if (_selectedCategory == null || !_sections.contains(_selectedCategory)) {
              _selectedCategory = _sections.isEmpty ? null : _sections.first;
            }

            return PadShell(
              current: 'food',
              roomNumber: widget.roomNumber,
              title: '음식 주문',
              subtitle: '${widget.roomNumber ?? '-'}번 룸으로 가져다드려요',
              headerBottom: _sections.isEmpty ? null : _categoryBar(),
              rightPanel: _cartPanel(),
              body: loading
                  ? const Center(child: CircularProgressIndicator(color: kOrange))
                  : _sections.isEmpty
                      ? const PadEmpty(icon: Icons.restaurant_menu, text: '지금 주문할 수 있는 메뉴가 없어요.')
                      : _menuScroll(byCategory),
            );
          },
        );
      },
    );
  }

  // 위쪽 카테고리 버튼 줄 (모두 그려 두어야 버튼 위치로 밀어 줄 수 있음)
  Widget _categoryBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in _sections)
            Padding(
              key: _pillKeys.putIfAbsent(c, () => GlobalKey()),
              padding: const EdgeInsets.only(right: 8),
              child: PadPill(
                label: c,
                fontSize: 16,
                selected: c == _selectedCategory,
                onTap: () => _jumpTo(c),
              ),
            ),
        ],
      ),
    );
  }

  // 모든 카테고리를 이어 붙인 메뉴 목록 — 끝없이 반복 (한 바퀴 = 제목·카드 줄·'처음으로' 표시)
  Widget _menuScroll(Map<String, List<Map<String, dynamic>>> byCategory) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const padL = 32.0, padR = 24.0;
        final usable = constraints.maxWidth - padL - padR;
        final cols = ((usable + _gridGap) / (_cardMinW + _gridGap)).floor().clamp(2, 6).toInt();

        // 한 바퀴를 줄 단위로 펼침. 줄마다 높이가 정해져 있어 위치 계산·이동이 정확함
        final items = <({int kind, String cat, int row, double h})>[]; // kind 0 제목, 1 카드 줄, 2 처음으로
        final tops = <double>[];
        var y = 0.0;
        for (final c in _sections) {
          tops.add(y);
          items.add((kind: 0, cat: c, row: 0, h: _sectionHeaderH));
          y += _sectionHeaderH;
          final rows = (byCategory[c]!.length / cols).ceil();
          for (var r = 0; r < rows; r++) {
            final h = _cardH + (r == rows - 1 ? _sectionGapBottom : _gridGap);
            items.add((kind: 1, cat: c, row: r, h: h));
            y += h;
          }
        }
        items.add((kind: 2, cat: '', row: 0, h: _loopMarkH));
        y += _loopMarkH;
        _sectionTops = tops;
        _cycleH = y;
        final n = items.length;

        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(left: padL, right: padR),
          // itemCount 없음 → 끝없이 이어짐. 높이를 미리 알려 줘서 멀리 이동해도 정확·가벼움
          itemExtentBuilder: (index, _) => items[index % n].h,
          itemBuilder: (context, index) {
            final it = items[index % n];
            switch (it.kind) {
              case 0:
                return Align(
                  alignment: Alignment.topLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      GuestText(it.cat, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
                      const SizedBox(width: 8),
                      GuestText('${byCategory[it.cat]!.length}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kMuted)),
                    ],
                  ),
                );
              case 1:
                final menus = byCategory[it.cat]!;
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: _cardH,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var k = 0; k < cols; k++) ...[
                          if (k > 0) const SizedBox(width: _gridGap),
                          Expanded(
                            child: it.row * cols + k < menus.length
                                ? _buildMenuCard(menus[it.row * cols + k])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              default:
                return const Align(
                  alignment: Alignment.topCenter,
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: kLine, thickness: 1)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Icon(Icons.replay_rounded, size: 18, color: kMuted),
                            SizedBox(width: 6),
                            GuestText('메뉴 처음부터 다시',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kMuted)),
                          ],
                        ),
                      ),
                      Expanded(child: Divider(color: kLine, thickness: 1)),
                    ],
                  ),
                );
            }
          },
        );
      },
    );
  }

  Widget _buildMenuCard(Map<String, dynamic> menuData) {
    final String name = guestField(context, menuData, 'name');
    final int price = _price(menuData['price']);
    final String? imageUrl = menuData['imageUrl'];
    final bool hasOptions = (menuData['optionGroups'] as List?)?.isNotEmpty == true;
    final bool soldOut = _isSoldOut(menuData);

    final Widget photo = ColoredBox(
      color: const Color(0xFFF1ECE2),
      child: hasValidImage(imageUrl)
          ? AppNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              errorWidget: (c, u, e) => const Icon(Icons.fastfood, color: kMuted, size: 40),
            )
          : const Icon(Icons.fastfood, color: kMuted, size: 40),
    );

    return HomeCard(
      padding: EdgeInsets.zero,
      color: soldOut ? const Color(0xFFF7F5F1) : Colors.white,
      onTap: soldOut
          ? () => padSnack(context, '$name은(는) 지금 품절이에요.')
          : () => _showMenuOptionDialog(context, menuData),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: !soldOut
                ? photo
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      // 품절: 사진을 흑백으로 + 어둡게 + 가운데 '품절'
                      ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0, //
                          0.2126, 0.7152, 0.0722, 0, 0, //
                          0.2126, 0.7152, 0.0722, 0, 0, //
                          0, 0, 0, 1, 0, //
                        ]),
                        child: photo,
                      ),
                      ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: kInk.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const GuestText('품절',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GuestText(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: soldOut ? kMuted : kInk)),
                      const SizedBox(height: 2),
                      GuestText(_won(price),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: soldOut ? kMuted : kOrange,
                            decoration: soldOut ? TextDecoration.lineThrough : null,
                          )),
                    ],
                  ),
                ),
                if (soldOut)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(12)),
                    child: const GuestText('품절', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kMuted)),
                  )
                else
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(12)),
                    child: Icon(hasOptions ? Icons.tune : Icons.add, color: Colors.white, size: 20),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 오른쪽 장바구니
  Widget _cartPanel() {
    final keys = cart.keys.toList();
    return Container(
      width: 330,
      margin: const EdgeInsets.fromLTRB(0, 20, 20, 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_outlined, color: kInk),
                const SizedBox(width: 8),
                const GuestText('장바구니', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
                const SizedBox(width: 8),
                if (cart.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(color: kOrange, borderRadius: BorderRadius.circular(10)),
                    child: GuestText('${_getTotalCount()}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                const Spacer(),
                if (cart.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => cart.clear()),
                    style: TextButton.styleFrom(foregroundColor: kMuted),
                    child: const GuestText('비우기'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: kLine),
          Expanded(
            child: cart.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: GuestText('메뉴를 눌러 담아 주세요',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: kMuted)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    itemCount: keys.length,
                    separatorBuilder: (_, _) => const Divider(height: 18, color: kLine),
                    itemBuilder: (context, index) {
                      final cartKey = keys[index];
                      final int quantity = cart[cartKey]!['quantity'];
                      final int unitPrice = cart[cartKey]!['unitPrice'];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GuestText(cartKey,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              GuestText(_won(unitPrice * quantity),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kInk)),
                              const Spacer(),
                              _qtyButton(Icons.remove, () => _updateQuantity(cartKey, -1)),
                              SizedBox(
                                width: 34,
                                child: GuestText('$quantity',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
                              ),
                              _qtyButton(Icons.add, () => _updateQuantity(cartKey, 1)),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Container(
            color: kBg.withValues(alpha: 0.6),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _noteController,
                  style: const TextStyle(fontSize: 14, color: kInk),
                  decoration: InputDecoration(
                    hintText: guestTr(context, '요청사항 (예: 얼음 적게)'),
                    hintStyle: const TextStyle(color: kMuted),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kLine),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kOrange, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const GuestText('합계', style: TextStyle(fontSize: 16, color: kBody)),
                    const Spacer(),
                    GuestText(_won(_getTotalPrice()),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kInk)),
                  ],
                ),
                if (_flow.cartNotice != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: kOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_flow.payAtPickup ? Icons.payments_outlined : Icons.storefront_outlined,
                            size: 18, color: kOrange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GuestText(_flow.cartNotice!,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kBody, height: 1.35)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 58,
                  child: FilledButton(
                    onPressed: cart.isEmpty || _isSubmitting ? null : _submitOrder,
                    style: FilledButton.styleFrom(
                      backgroundColor: kOrange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kLine,
                      disabledForegroundColor: kMuted,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                        : const GuestText('주문하기', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: kBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 18, color: kInk)),
      ),
    );
  }
}
