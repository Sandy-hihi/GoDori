# 손님용 패드 웹 배포

손님용 웹의 진입점은 `lib/main.dart`입니다. 관리자 웹의
`lib/main_admin.dart`와 구분해 빌드합니다.

Vercel 프로젝트의 Root Directory는 이 `vercel.json`이 있는 저장소 루트로,
Output Directory는 `build/web`으로 설정합니다. 기존 Flutter SDK 설치 및
빌드 명령을 유지하되 손님용 진입점을 사용해야 합니다.

```sh
flutter pub get
flutter build web --release -t lib/main.dart
```

`vercel.json`은 `/api/*`를 Firebase에 배포된 동일한 경로로 프록시합니다.
브라우저는 Vercel과 같은 출처로 요청하므로 별도의 Firebase CORS 변경은
필요하지 않습니다. API는 기존 인증과 권한 검사를 그대로 수행합니다.

팀 저장소 `Sandy-hihi/GoDori`에 이 설정을 커밋한 뒤, 포크 동기화 작업과
Vercel 자동 배포의 성공을 각각 확인합니다. 포크에만 수정하면 다음
원본 동기화의 강제 푸시로 덮어써질 수 있습니다.

배포 후 확인:

- `https://godoriv1-flax.vercel.app/api/health` → HTTP 200, `{"ok":true}`
- 빈 JSON으로 `POST /api/auth/store-login` → HTTP 400 JSON
  (`INVALID_STORE_ID`); HTTP 404나 HTML이면 API 연결이 적용되지 않은 상태입니다.
- 실제 매장 아이디, 패드 비밀번호, 유효한 방 번호로 손님 패드에 로그인합니다.

패드 비밀번호와 관리자 PIN은 관리자 웹의 **매장 설정 → 로그인**에서
설정합니다. 관리자 웹 비밀번호와 패드 비밀번호는 서로 다릅니다.
