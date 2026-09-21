import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/custom_app_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';

class NoticeScreen extends StatelessWidget {
  const NoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: SafeArea(
        child: Column(
          children: [
            CustomAppBar(
              showBackButton: true,
              centerWidget: const Text(
                '이용안내',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('settings').doc('notices').snapshots(),
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
                          Icon(Icons.info_outline, size: 80, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('등록된 공지가 없습니다.', style: TextStyle(fontSize: 20, color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index] as Map<String, dynamic>;
                      final isImage = item['type'] == 'image';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 제목 헤더
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2C3E50),
                                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline, color: Colors.white, size: 26),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item['title'] ?? '',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 내용
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: isImage
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CachedNetworkImage(
                                        imageUrl: item['content'] ?? '',
                                        width: double.infinity,
                                        fit: BoxFit.contain,
                                        placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                        errorWidget: (c, u, e) => const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(32),
                                            child: Icon(Icons.broken_image, size: 60, color: Colors.grey),
                                          ),
                                        ),
                                      ),
                                    )
                                  : Text(
                                      item['content'] ?? '',
                                      style: const TextStyle(fontSize: 18, height: 1.8, color: Colors.black87),
                                    ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
