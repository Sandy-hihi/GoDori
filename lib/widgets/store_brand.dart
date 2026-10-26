import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/widgets/app_network_image.dart';

/// 매장 이름·로고 — 관리자 웹 "홈 화면 꾸미기 > 왼쪽 영역 > 로고 설정"에서 바꾼 값을
/// 앱의 모든 화면(상단 바, 주문 화면, 관리자 로그인 등)이 같이 씀.
/// 값은 settings/homeLayout 문서의 왼쪽 영역 logo 요소 options(name, imageUrl)에 저장됨.
class StoreBrand {
  static const String defaultName = '플랫폼6 보드카페';

  final String name;
  final String? logoUrl;
  const StoreBrand({this.name = defaultName, this.logoUrl});

  static StoreBrand fromLayoutDoc(Map<String, dynamic>? data) {
    final sidebar = data?['sidebar'];
    final items = sidebar is Map ? sidebar['items'] : null;
    if (items is List) {
      for (final raw in items) {
        if (raw is Map && raw['type'] == 'logo' && raw['options'] is Map) {
          final o = raw['options'] as Map;
          final name = (o['name'] ?? '').toString().trim();
          final url = (o['imageUrl'] ?? '').toString().trim();
          return StoreBrand(name: name.isEmpty ? defaultName : name, logoUrl: url.isEmpty ? null : url);
        }
      }
    }
    return const StoreBrand();
  }

  /// 마지막으로 읽은 값 (화면을 새로 열 때 깜빡임 없이 바로 보여 주려고)
  static StoreBrand latest = const StoreBrand();

  static final Stream<StoreBrand> stream = FirebaseFirestore.instance
      .collection('settings')
      .doc('homeLayout')
      .snapshots()
      .map((s) => latest = fromLayoutDoc(s.data()))
      .handleError((_) {})
      .asBroadcastStream();
}

/// 매장 이름 글자
class StoreName extends StatelessWidget {
  final TextStyle? style;
  final TextAlign? textAlign;
  const StoreName({super.key, this.style, this.textAlign});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StoreBrand>(
      stream: StoreBrand.stream,
      initialData: StoreBrand.latest,
      builder: (context, snap) => Text(
        (snap.data ?? StoreBrand.latest).name,
        style: style,
        textAlign: textAlign,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 동그란 매장 로고 (올린 사진이 없으면 기본 로고)
class StoreLogo extends StatelessWidget {
  final double size;
  const StoreLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset('assets/images/logo.jpg', width: size, height: size, fit: BoxFit.cover);
    return StreamBuilder<StoreBrand>(
      stream: StoreBrand.stream,
      initialData: StoreBrand.latest,
      builder: (context, snap) {
        final url = (snap.data ?? StoreBrand.latest).logoUrl;
        return ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: hasValidImage(url)
                ? AppNetworkImage(
                    imageUrl: url!,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorWidget: (c, u, e) => fallback,
                  )
                : fallback,
          ),
        );
      },
    );
  }
}
