# 고도리 (GoDori)

보드게임 카페용 손님 패드·관리자 웹·운영자 페이지입니다. Flutter와 Firebase(Firestore, Storage, Hosting, Functions, Authentication)로 만들었고, 룰 설명 영상은 Cloudflare R2에 저장합니다.
여러 매장이 함께 쓰는 구조이고, 매장마다 데이터가 따로 저장됩니다(Firestore `stores/{매장 아이디}/...`).

## 앱 세 가지

| 앱 | 시작 파일 | 쓰는 사람 | 주소 |
| --- | --- | --- | --- |
| 손님 패드 (+ 패드 관리자 대시보드) | `lib/main.dart` | 방마다 놓는 태블릿 | 안드로이드 앱(`kr.godori.pad`), 개발 중엔 크롬 |
| 관리자 웹 | `lib/main_admin.dart` | 매장 사장님 | https://godori-pad.web.app |
| 운영자 페이지 | `lib/main_ops.dart` | 서비스 운영자 | https://godori-ops.web.app |

예전 주소 `platform6-boardpad.web.app`은 `godori-pad.web.app`으로 넘어갑니다.

## 주요 기능

**손님 패드**
- 로그인: 매장 아이디 + 패드 비밀번호 + 방 번호. 자동 로그인을 켜 두면 다음부터 바로 그 방 화면이 열립니다.
- 방 번호 `0` + 관리자 PIN → 패드 관리자 대시보드(주문 현황·직원 호출). 매장 설정에서 끌 수 있습니다.
- 로그아웃: 홈 왼쪽 위 매장 로고(왼쪽 영역이 꺼져 있으면 왼쪽 위 구석)를 빠르게 10번 누른 뒤 패드 비밀번호 또는 관리자 PIN 입력.
- 홈 화면: 관리자 웹에서 꾸민 위젯 배치(음식 주문, 게임 목록, 시계, 방 번호, 공지, 이벤트 등).
- 게임 목록: 이름·초성 검색, 장르·인원·시간·난이도 필터, 추천 게임, 룰 설명 영상 재생.
- 음식 주문: 카테고리·옵션·장바구니, 방 번호와 함께 주문 전송. 매장의 수령 방식(방으로 서빙 / 카운터에서 받아 감 / 카운터에서 결제 후 받아 감)에 따라 안내와 '준비 완료' 알림이 달라집니다.
- 직원 호출, 이용 안내·공지, 이벤트, 게임 도구(타이머, 스톱워치, 주사위, 팀 나누기, 선 뽑기).

**관리자 웹 (사장님)**
- 회원가입 → 운영자 승인 → 로그인.
- 게임(BGG 정보 불러오기, 룰 영상 올리기), 음식 메뉴·옵션·품절, 공지, 이벤트, 홈 화면 꾸미기.
- 매장 설정: 방 개수, 음식 수령 방식, 기능 사용(패드 관리자 대시보드), 비밀번호·PIN 바꾸기.

**운영자 페이지**
- 가입 승인·거절·정지, 매장별 기능 켜기·끄기(토스 POS 연동 포함), 서버 이용 통계(비용 관리), 매장 통계.

**서버 (`functions/`)** — Cloud Functions(2세대, 서울 asia-northeast3) 하나(`api`)에 모든 API가 있습니다.
- 로그인 토큰 발급(매장·방 번호가 들어 있음), 가입·운영자 API, BGG 조회, 룰 영상 임시 주소(R2), 이용량 기록, 토스 POS 연동.
- 비밀번호는 해시로만 저장하고(`stores/{매장}/private/...`, 서버만 읽음), 로그인 실패가 많으면 잠깐 막습니다.
- 보안 규칙(`firestore.rules`, `storage.rules`): 자기 매장 데이터만, 손님 패드는 자기 방 주문·호출만 할 수 있습니다.

## 실행 (개발)

Flutter SDK(Dart 3.13 이상)를 설치하고 프로젝트 루트(pubspec.yaml이 있는 폴더)에서 실행합니다.

~~~powershell
flutter pub get
flutter run -t lib/main.dart -d chrome        # 손님 패드
flutter run -t lib/main_admin.dart -d chrome  # 관리자 웹
flutter run -t lib/main_ops.dart -d chrome    # 운영자 페이지
~~~

- `-t`를 빼면 손님 패드(`lib/main.dart`)가 실행됩니다.
- 실행할 때마다 새 크롬 창이 열리므로 로그인도 매번 다시 해야 합니다.
- 코드를 고친 뒤에는 실행 중인 터미널에서 `r`(빠른 반영) 또는 `R`(다시 시작)을 누르세요.
- 실제 Firebase 프로젝트(`platform6-boardpad`)에 연결되므로, 로그인하려면 승인된 매장 계정이 필요합니다.

서버 테스트는 `functions/` 폴더에서 실행합니다.

~~~powershell
cd functions
npm install
node --test test/*.test.js
~~~

## 검증

~~~powershell
flutter analyze
flutter test
~~~

## 배포

Firebase CLI로 로그인한 뒤 프로젝트 루트에서 실행합니다(권한이 있는 계정만).

~~~powershell
flutter build web --release -t lib/main_admin.dart
flutter build web --release -t lib/main_ops.dart --output build/ops
firebase deploy --only hosting                 # 관리자 웹·운영자 페이지
firebase deploy --only functions               # 서버
firebase deploy --only firestore:rules,storage # 보안 규칙
~~~

비밀값(BGG, R2, 토스)은 Firebase Secret Manager에 들어 있고 저장소에는 없습니다. 비밀번호·키 값은 코드·README·커밋 메시지에 적지 마세요.

## Windows 앱으로 실행할 때 Firebase 링크 오류

MSVC 14.39에서 Firebase Windows 라이브러리를 링크하면 `__std_find_end_1`,
`_Cnd_timedwait_for_unchecked` 등의 LNK2019/LNK2001 오류가 날 수 있습니다.
Visual Studio Installer에서 Visual Studio 2022와 C++ 도구를 업데이트한 뒤
`flutter clean`, `flutter pub get`, `flutter run -d windows` 순서로 다시 실행하세요. LNK4099는 디버그 기호 경고라 무시해도 됩니다.

## 참고

- 예전 손님 화면의 '일행과 함께'(인원별 추천, 승패·음료 내기, 밸런스 게임) 코드는 `lib/screens/party_screen.dart`에 남아 있지만 지금은 메뉴에서 열 수 없습니다.
- 예전 기본 관리자 PIN이 오래된 커밋 기록에 남아 있습니다. 지금은 매장별 비밀번호·PIN을 해시로 저장하고 예전 값은 쓰지 않습니다.
