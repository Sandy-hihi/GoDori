/// 영상 파일을 저장소(Cloudflare R2) 임시 주소로 바로 올리기 (PUT, 진행률 표시)
/// 웹(관리자 웹)은 브라우저 XMLHttpRequest로 진짜 전송 진행률을, 그 밖(안드로이드·윈도우)은 보낸 양을 보여 줌.
library;

export 'r2_upload_web.dart' if (dart.library.io) 'r2_upload_io.dart';
