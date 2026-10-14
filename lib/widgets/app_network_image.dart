import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// 인터넷 이미지 공용 위젯.
/// - 웹(관리자 웹·크롬 실행): 브라우저 기본 방식(Image.network)으로 불러옴.
///   CachedNetworkImage는 웹에서 페이지를 옮겼다가 돌아오면 이미 본 이미지를 다시 못 그리고
///   오류 아이콘으로 바뀌는 문제가 있었음. (브라우저가 알아서 캐시해 줌)
/// - 태블릿 앱(안드로이드 등): 기존처럼 CachedNetworkImage로 기기에 저장해 두고 씀.
/// 사용법은 CachedNetworkImage와 같음 (imageUrl, fit, width, height, placeholder, errorWidget).
class AppNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext context, String url)? placeholder;
  final Widget Function(BuildContext context, String url, Object error)? errorWidget;

  const AppNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        imageUrl,
        key: ValueKey(imageUrl),
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        loadingBuilder: placeholder == null
            ? null
            : (ctx, child, progress) => progress == null ? child : placeholder!(ctx, imageUrl),
        errorBuilder: errorWidget == null ? null : (ctx, error, stack) => errorWidget!(ctx, imageUrl, error),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }
}
