import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/pad_shell.dart';

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
class PadPostList extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc(docId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kOrange));
        }

        List<dynamic> items = [];
        if (snapshot.hasData && snapshot.data!.exists) {
          items = (snapshot.data!.data() as Map? ?? {})['items'] as List<dynamic>? ?? [];
        }
        if (items.isEmpty) return PadEmpty(icon: icon, text: emptyText);

        return Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = Map<String, dynamic>.from(items[index] as Map);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _PostCard(item: item, icon: icon, accent: accent),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final IconData icon;
  final Color accent;
  const _PostCard({required this.item, required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    final isImage = item['type'] == 'image';
    final title = (item['title'] ?? '').toString();
    final content = (item['content'] ?? '').toString();

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
                child: Text(title,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: kInk)),
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
            Text(content, style: const TextStyle(fontSize: 17, height: 1.75, color: kBody)),
        ],
      ),
    );
  }
}
