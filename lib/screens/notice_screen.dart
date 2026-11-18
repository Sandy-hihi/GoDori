import 'package:boardpad/l10n/guest_language.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/pad_shell.dart';
import 'package:boardpad/services/store_scope.dart';

/// 이용안내 (settings/notices) — 관리자 웹 '공지 관리'에서 등록
class NoticeScreen extends StatelessWidget {
  final int? roomNumber;
  const NoticeScreen({super.key, this.roomNumber});

  @override
  Widget build(BuildContext context) {
    return PadShell(
      current: 'notice',
      roomNumber: roomNumber,
      title: '이용안내',
      subtitle: '매장 이용 방법과 요금을 확인하세요',
      body: const PadPostList(
        docId: 'notices',
        icon: Icons.article_outlined,
        accent: kBlue,
        emptyText: '등록된 안내가 없어요.',
      ),
    );
  }
}

/// 글/이미지 카드 목록 — 이용안내(settings/notices)·이벤트(settings/events)가 같이 씀
/// items: [{type: 'text'|'image', title, content}] (image면 content가 사진 주소)
/// 132차: 넓은 화면(폭 1000 이상)에 글이 2개 이상이면 왼쪽 제목 목록 + 오른쪽 크게 보기(오른쪽 빈 공간 없앰),
///   글이 하나면 화면 폭에 맞춰 크게, 좁은 화면은 예전처럼 카드 목록
class PadPostList extends StatefulWidget {
  final String docId;
  final IconData icon;
  final Color accent;
  final String emptyText;

  const PadPostList({
    super.key,
    required this.docId,
    required this.icon,
    required this.accent,
    required this.emptyText,
  });

  @override
  State<PadPostList> createState() => _PadPostListState();
}

class _PadPostListState extends State<PadPostList> {
  late final Stream<DocumentSnapshot> _stream = StoreScope.col('settings').doc(widget.docId).snapshots();
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: kOrange));
        }

        List<dynamic> items = [];
        if (snapshot.hasData && snapshot.data!.exists) {
          items = (snapshot.data!.data() as Map? ?? {})['items'] as List<dynamic>? ?? [];
        }
        if (items.isEmpty) return PadEmpty(icon: widget.icon, text: widget.emptyText);
        if (_selected >= items.length) _selected = 0;
        final posts = [for (final it in items) Map<String, dynamic>.from(it as Map)];

        return LayoutBuilder(builder: (context, box) {
          // 좁은 화면: 카드 목록
          if (box.maxWidth < 1000) {
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              itemCount: posts.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _PostCard(item: posts[index], icon: widget.icon, accent: widget.accent),
              ),
            );
          }
          // 글이 하나: 화면 폭에 맞춰 크게
          if (posts.length == 1) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: _PostCard(item: posts.first, icon: widget.icon, accent: widget.accent, large: true),
            );
          }
          // 넓은 화면 + 여러 개: 왼쪽 제목 목록 + 오른쪽 크게 보기
          return Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 340,
                  child: ListView.builder(
                    itemCount: posts.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PostTile(
                        item: posts[i],
                        icon: widget.icon,
                        accent: widget.accent,
                        selected: i == _selected,
                        onTap: () => setState(() => _selected = i),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey(_selected), // 고르면 맨 위부터
                    child: _PostCard(item: posts[_selected], icon: widget.icon, accent: widget.accent, large: true),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

/// 왼쪽 목록 한 줄 (132차) — 사진 글은 작은 사진, 글은 아이콘 + 첫 줄
class _PostTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  const _PostTile({required this.item, required this.icon, required this.accent, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isImage = item['type'] == 'image';
    final title = GuestLanguage.instance.translateExact(guestField(context, item, 'title').toString());
    final content = guestField(context, item, 'content').toString();
    return Material(
      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? accent : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: isImage && content.isNotEmpty
                      ? AppNetworkImage(
                          imageUrl: content,
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => ColoredBox(color: accent.withValues(alpha: 0.12), child: Icon(icon, color: accent)),
                        )
                      : ColoredBox(color: accent.withValues(alpha: 0.12), child: Icon(icon, color: accent)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GuestText(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: selected ? kInk : kBody)),
                    if (!isImage && content.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      GuestText(content.split('\n').first,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: kMuted)),
                    ],
                  ],
                ),
              ),
              if (selected) Icon(Icons.chevron_right, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final IconData icon;
  final Color accent;
  final bool large; // 132차: 오른쪽 크게 보기 — 글자 조금 크게
  const _PostCard({required this.item, required this.icon, required this.accent, this.large = false});

  @override
  Widget build(BuildContext context) {
    final isImage = item['type'] == 'image';
    // 매장 번역이 없으면 번역표에 같은 문장(예: '이용안내')이 있을 때만 바꿈 (81차)
    final title = GuestLanguage.instance.translateExact(guestField(context, item, 'title').toString());
    final content = (guestField(context, item, 'content')).toString();

    return HomeCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: GuestText(title,
                    style: TextStyle(fontSize: large ? 25 : 21, fontWeight: FontWeight.w800, color: kInk)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AppNetworkImage(
                imageUrl: content,
                width: double.infinity,
                fit: BoxFit.contain,
                placeholder: (context, url) => const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator(color: kOrange)),
                ),
                errorWidget: (c, u, e) => const SizedBox(
                  height: 160,
                  child: Center(child: Icon(Icons.broken_image_outlined, size: 48, color: kMuted)),
                ),
              ),
            )
          else
            GuestText(content, style: TextStyle(fontSize: large ? 19 : 17, height: 1.75, color: kBody)),
        ],
      ),
    );
  }
}
