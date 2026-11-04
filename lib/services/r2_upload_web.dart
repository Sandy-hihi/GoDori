import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'r2_upload_common.dart';

export 'r2_upload_common.dart';

/// 관리자 웹용: 브라우저가 R2로 바로 올림 (서버 함수를 거치지 않음 — 수백 MB라서)
/// R2 버킷의 CORS 설정에 관리자 웹 주소가 있어야 함 ("R2 룰 영상 연결 방법.txt")
Future<void> putToStorage(
  String url,
  Uint8List bytes, {
  required String contentType,
  void Function(double)? onProgress,
}) {
  final done = Completer<void>();
  final xhr = web.XMLHttpRequest();
  xhr.open('PUT', url);
  xhr.setRequestHeader('Content-Type', contentType);
  xhr.upload.onprogress = ((web.ProgressEvent e) {
    if (e.lengthComputable && e.total > 0) onProgress?.call(e.loaded / e.total);
  }).toJS;
  xhr.onload = ((web.Event _) {
    if (done.isCompleted) return;
    final s = xhr.status;
    if (s >= 200 && s < 300) {
      onProgress?.call(1);
      done.complete();
    } else {
      done.completeError(R2UploadException(r2StatusMessage(s)));
    }
  }).toJS;
  xhr.onerror = ((web.Event _) {
    if (!done.isCompleted) {
      done.completeError(R2UploadException('저장소에 연결하지 못했어요. 인터넷 연결 또는 R2 버킷 CORS 설정을 확인해 주세요.'));
    }
  }).toJS;
  xhr.onabort = ((web.Event _) {
    if (!done.isCompleted) done.completeError(R2UploadException('올리기가 취소됐어요.'));
  }).toJS;
  xhr.send(bytes.toJS);
  return done.future;
}
