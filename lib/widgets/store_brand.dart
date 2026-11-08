import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/services/store_scope.dart';

/// 매장 이름·로고 — 관리자 웹 "홈 화면 꾸미기 > 왼쪽 영역 > 로고 설정"에서 바꾼 값을
/// 앱의 모든 화면(상단 바, 주문 화면, 관리자 로그인 등)이 같이 씀.
/// 값은 settings/homeLayout 문서의 왼쪽 영역 logo 요소 options(name, imageUrl)에 저장됨.
/// 기본 이름·기본 로고는 없음 — 매장이 설정해야만 보임(빈 이름이면 화면에서 빠짐).
class StoreBrand {
  final String name;
  final String? logoUrl;
  const StoreBrand({this.name = '', this.logoUrl});

  static StoreBrand fromLayoutDoc(Map<String, dynamic>? data) {
    final sidebar = data?['sidebar'];
    final items = sidebar is Map ? sidebar['items'] : null;
    if (items is List) {
      for (final raw in items) {
        if (raw is Map && raw['type'] == 'logo' && raw['options'] is Map) {
          final o = raw['options'] as Map;
          final name = (o['name'] ?? '').toString().trim();
          final url = (o['imageUrl'] ?? '').toString().trim();
          return StoreBrand(name: name, logoUrl: url.isEmpty ? null : url);
        }
      }
    }
    return const StoreBrand();
  }

  /// 마지막으로 읽은 값 (화면을 새로 열 때 깜빡임 없이 바로 보여 주려고)
  static StoreBrand latest = const StoreBrand();

  static String? _streamStore;
  static Stream<StoreBrand>? _stream;

  /// 지금 매장의 이름·로고 (매장이 바뀌면 새로 읽음). 로그인 전(로그인 화면)에는 빈 값
  static Stream<StoreBrand> get stream {
    if (!StoreScope.isSet) return Stream.value(const StoreBrand());
    final store = StoreScope.id;
    if (_stream == null || _streamStore != store) {
      _streamStore = store;
      latest = const StoreBrand();
      _stream = StoreScope.col('settings')
          .doc('homeLayout')
          .snapshots()
          .map((s) => latest = fromLayoutDoc(s.data()))
          .handleError((_) {})
          .asBroadcastStream();
    }
    return _stream!;
  }
}

/// 매장 이름 글자 (설정 안 했으면 아무것도 안 그림)
class StoreName extends StatelessWidget {
  final TextStyle? style;
  final TextAlign? textAlign;
  const StoreName({super.key, this.style, this.textAlign});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StoreBrand>(
      stream: StoreBrand.stream,
      initialData: StoreBrand.latest,
      builder: (context, snap) {
        final name = (snap.data ?? StoreBrand.latest).name;
        if (name.isEmpty) return const SizedBox.shrink();
        return Text(
          name,
          style: style,
          textAlign: textAlign,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// 고도리 기본 브랜드: 제공된 SVG와 한글 워드마크를 가로로 표시한다.
class GodoriBrand extends StatelessWidget {
  static const assetPath = 'assets/images/godori_logo.svg';
  final double size;
  final Color? textColor;
  const GodoriBrand({super.key, this.size = 48, this.textColor});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(
        child: SvgPicture.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
      SizedBox(width: size * 0.22),
      Text(
        '고도리',
        style: TextStyle(
          fontSize: size * 0.52,
          fontWeight: FontWeight.w800,
          color: textColor,
          height: 1.1,
        ),
      ),
    ],
  );
}

/// 동그란 매장 로고. 매장이 관리자 웹에서 로고를 올렸으면 그 로고,
/// 안 올렸으면(또는 로그인 전) 고도리 기본 브랜드(SVG + '고도리')를 보여 줌 (80차).
class StoreLogo extends StatelessWidget {
  final double size;
  final EdgeInsetsGeometry padding;
  const StoreLogo({super.key, this.size = 40, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StoreBrand>(
      stream: StoreBrand.stream,
      initialData: StoreBrand.latest,
      builder: (context, snap) {
        final url = (snap.data ?? StoreBrand.latest).logoUrl;
        if (!hasValidImage(url)) {
          return Padding(padding: padding, child: GodoriBrand(size: size));
        }
        return Padding(
          padding: padding,
          child: ClipOval(
            child: AppNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorWidget: (c, u, e) => SizedBox(width: size, height: size),
            ),
          ),
        );
      },
    );
  }
}
