class R2UploadException implements Exception {
  final String message;
  R2UploadException(this.message);
  @override
  String toString() => message;
}

String r2StatusMessage(int status) {
  if (status == 403) return '저장소가 업로드를 거절했어요 (403). 시간이 오래 지났으면 다시 올려 주세요.';
  return '저장소에 영상을 올리지 못했어요. ($status)';
}
