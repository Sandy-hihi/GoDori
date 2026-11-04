import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'r2_upload_common.dart';

export 'r2_upload_common.dart';

/// 안드로이드·윈도우용: 조금씩 나눠 보내면서 보낸 양으로 진행률 표시
Future<void> putToStorage(
  String url,
  Uint8List bytes, {
  required String contentType,
  void Function(double)? onProgress,
}) async {
  final req = http.StreamedRequest('PUT', Uri.parse(url));
  req.headers['content-type'] = contentType;
  req.contentLength = bytes.length;
  final client = http.Client();
  try {
    final resFuture = client.send(req);
    const chunk = 256 * 1024;
    for (var i = 0; i < bytes.length; i += chunk) {
      final end = math.min(i + chunk, bytes.length);
      req.sink.add(Uint8List.sublistView(bytes, i, end));
      onProgress?.call(end / bytes.length);
      await Future<void>.delayed(Duration.zero);
    }
    await req.sink.close();
    final res = await resFuture;
    await res.stream.drain<void>();
    if (res.statusCode < 200 || res.statusCode >= 300) throw R2UploadException(r2StatusMessage(res.statusCode));
  } on R2UploadException {
    rethrow;
  } catch (_) {
    throw R2UploadException('저장소에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
  } finally {
    client.close();
  }
}
