import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/widgets/admin_colors.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/widgets/home/home_theme.dart';

/// 관리자 웹 공지 관리·이벤트 관리 목록 (132차 — 두 화면이 같이 씀)
///   - 왼쪽: 글 카드(순서 번호 · 사진 미리보기 또는 글 아이콘 · 제목 · '글'/'사진' 칩 · 내용 두 줄 · ↑↓ 순서 · 수정 · 삭제)
///     누르면 고른 카드(남색 테두리) → 오른쪽 미리보기
///   - 오른쪽(넓은 화면 ≥ 1100): '손님 패드 미리보기' — 패드 이용안내·이벤트 화면과 같은 카드 모양
///   - ↑↓: items 순서를 바꿔 저장 (번역 칸도 그 글과 같이 옮겨 감) — 손님 패드에도 이 순서로 보임
///   - 비어 있으면 가운데 [새 … 추가] 버튼
class AdminPostBoard extends StatefulWidget {
  final String docId; // 'notices' | 'events'
  final String kind; // '공지' | '이벤트'
  final IconData icon;
  final Color accent; // 손님 패드에서 쓰는 색 (이용안내 파랑 · 이벤트 주황)
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic> item, int index) onEdit;
  final Future<void> Function(int index, List<dynamic> items) onDelete;

  const AdminPostBoard({
    super.key,
    required this.docId,
    required this.kind,
    required this.icon,
    required this.accent,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<AdminPostBoard> createState() => _AdminPostBoardState();
}

class _AdminPostBoardState extends State<AdminPostBoard> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _stream =
      StoreScope.col('settings').doc(widget.docId).snapshots();
  int _selected = 0;
  bool _moving = false;

  Future<void> _move(List<dynamic> items, int from, int to) async {
    if (_moving || to < 0 || to >= items.length) return;
    setState(() => _moving = true);
    try {
      final next = List<dynamic>.from(items);
      final it = next.removeAt(from);
      next.insert(to, it);
      await StoreScope.col('settings').doc(widget.docId).set({'items': next});
      if (mounted) setState(() => _selected = to);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('순서를 바꾸지 못했어요: $e')));
      }
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = (snap.data?.data()?['items'] as List<dynamic>?) ?? const [];
        if (items.isEmpty) return _empty();
        if (_selected >= items.length) _selected = items.length - 1;
        final wide = MediaQuery.sizeOf(context).width >= 1100;
        final list = ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: items.length,
          itemBuilder: (context, i) => _card(items, i),
        );
        if (!wide) return list;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: list),
            const SizedBox(width: 24),
            SizedBox(width: 400, child: _preview(Map<String, dynamic>.from(items[_selected] as Map))),
          ],
        );
      },
    );
  }

  Widget _empty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 64),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: kAdminAccentSoft, shape: BoxShape.circle),
            child: Icon(widget.icon, size: 36, color: kAdminAccent),
          ),
          const SizedBox(height: 16),
          Text('아직 등록된 ${widget.kind}가 없어요', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('글이나 사진으로 올리면 손님 패드에 바로 보여요.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: widget.onAdd,
            icon: const Icon(Icons.add),
            label: Text('첫 ${widget.kind} 추가하기'),
            style: FilledButton.styleFrom(backgroundColor: kAdminAccent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
          ),
        ],
      ),
    );
  }

  Widget _thumb(Map<String, dynamic> item) {
    final isImage = item['type'] == 'image';
    final url = '${item['content'] ?? ''}';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 72,
        height: 72,
        child: isImage && url.isNotEmpty
            ? AppNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (c, u, e) => const ColoredBox(color: Color(0xFFF1F3F5), child: Icon(Icons.broken_image_outlined)),
              )
            : ColoredBox(color: widget.accent.withValues(alpha: 0.1), child: Icon(widget.icon, color: widget.accent, size: 30)),
      ),
    );
  }

  Widget _card(List<dynamic> items, int i) {
    final item = Map<String, dynamic>.from(items[i] as Map);
    final isImage = item['type'] == 'image';
    final selected = i == _selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? kAdminAccent : const Color(0xFFE5E7EB), width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selected = i),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text('${i + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black38)),
                ),
                const SizedBox(width: 8),
                _thumb(item),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text('${item['title'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: kAdminAccentSoft, borderRadius: BorderRadius.circular(10)),
                          child: Text(isImage ? '사진' : '글',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kAdminAccent)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        isImage ? '사진 한 장으로 보여요' : '${item['content'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '위로',
                  onPressed: i == 0 || _moving ? null : () => _move(items, i, i - 1),
                  icon: const Icon(Icons.arrow_upward, size: 20),
                ),
                IconButton(
                  tooltip: '아래로',
                  onPressed: i == items.length - 1 || _moving ? null : () => _move(items, i, i + 1),
                  icon: const Icon(Icons.arrow_downward, size: 20),
                ),
                IconButton(
                  tooltip: '수정',
                  onPressed: () => widget.onEdit(item, i),
                  icon: const Icon(Icons.edit_outlined, color: kAdminAccent),
                ),
                IconButton(
                  tooltip: '삭제',
                  onPressed: () => widget.onDelete(i, items),
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 손님 패드 이용안내·이벤트 카드와 같은 모양 (notice_screen.dart _PostCard)
  Widget _preview(Map<String, dynamic> item) {
    final isImage = item['type'] == 'image';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(children: [
            Icon(Icons.tablet_mac_outlined, size: 18, color: kMuted),
            SizedBox(width: 6),
            Text('손님 패드 미리보기', style: TextStyle(fontWeight: FontWeight.bold, color: kMuted)),
          ]),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: widget.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                        child: Icon(widget.icon, color: widget.accent, size: 19),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${item['title'] ?? ''}',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (isImage)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AppNetworkImage(imageUrl: '${item['content'] ?? ''}', width: double.infinity, fit: BoxFit.contain),
                      )
                    else
                      Text('${item['content'] ?? ''}', style: const TextStyle(fontSize: 14, height: 1.7, color: kBody)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text('영어·중국어·일본어는 저장하면 자동 번역돼요 (번역 관리에서 고칠 수 있어요).',
              style: TextStyle(fontSize: 12, color: kMuted)),
        ],
      ),
    );
  }
}
