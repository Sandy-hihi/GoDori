# 고도리 (GoDori)

Flutter와 Firebase로 만든 보드게임 카페용 손님 패드 및 관리자 앱입니다.
실제 앱 화면은 lib/main.dart와 lib/screens/에 있습니다.
windows/runner/main.cpp는 Flutter 앱을 Windows 창에서 띄우는 실행 진입부입니다.

## 기존 기능

- 손님/관리자 진입 화면, 손님의 방 번호 선택, 관리자의 PIN 확인
- 게임 이름 검색, 장르·인원·시간·난이도 필터, 직원 추천 게임 표시, 게임 설명 영상 열기
- 음식/음료 카테고리와 옵션 선택, 장바구니, 수량 변경, 방 번호를 포함한 주문 전송
- 직원 호출 및 관리자 화면의 호출·주문 수신과 주문 처리 상태 관리
- 이용 안내·공지와 이벤트 표시
- 게임 도구: 카운트다운(알림), 스톱워치, 주사위, 랜덤 팀 나누기 및 선 뽑기
- 관리자: 게임·장르·메뉴·옵션·공지·이벤트 관리, 게임 이용 가능/추천 설정, 손님 앱 목록 새로고침

기존 카페 데이터와 주문·직원 호출은 Firestore를 사용합니다.
이미지에는 Firebase Storage와 네트워크 이미지가 사용됩니다.

## 추가 기능: 일행과 함께

손님용 패드 → 방 선택 → 홈 상단의 **일행과 함께** 버튼에서 이용합니다.

### 인원별 추천

인원 수(1~100명)를 입력하면 카페에 등록된 이용 가능 게임 중 해당 인원이
최소·최대 범위에 포함되는 게임을 보여줍니다. 직원 추천 게임을 먼저 표시합니다.
게임을 누르면 기존 게임 목록에서 해당 이름으로 검색합니다.

기존 games 컬렉션의 players 필드를 사용합니다.
지원 예: 2~4인, 3–6명, 2인전용, 5인 이상, 6+, 4인 이하.
인원이 비어 있거나 해석할 수 없는 게임은 추천에서 제외합니다.

### 승패 기록과 음료 내기

1. 승패 · 음료 내기 탭에서 참가자 이름을 줄바꿈 또는 쉼표로 입력합니다.
   동명이인은 다른 별명을 사용합니다(2~30명).
2. 카페와 음료·내기 내용을 미리 정하고 설정을 저장합니다.
3. 등록된 게임을 선택하거나 게임 이름을 직접 입력합니다.
4. 각 참가자를 승 / 패 / 미참가로 지정하고 이 판의 승패를 저장합니다.
   승자와 패자를 각각 한 명 이상 선택해야 하며 여러 승자·패자를 허용합니다.
5. 전체 및 게임별 승패를 확인합니다. 음료 내기는 **전체 게임의 누적 패배 횟수**가
   가장 많은 사람에게 당첨됩니다. 동률이면 공동 당첨이며, 기록이 없으면 당첨자가 없습니다.

판별 기록을 삭제하면 집계와 현재 당첨자를 다시 계산합니다.
첫 판 이후 참가자 및 내기 조건은 고정됩니다.
새 일행 시작 버튼은 확인 후 현재 방의 모든 일행·내기 기록을 초기화합니다.

기록은 shared_preferences로 **현재 기기에 방별로 저장**됩니다.
화면 재진입 및 앱 재시작 시 복원되며 다른 기기와 동기화하지 않습니다.
현재 당첨자는 기록이 추가/삭제될 때 바뀝니다. 실제 음료 주문은 자동 전송하지 않습니다.
앱 데이터 삭제/브라우저 저장소 삭제 시 기록도 삭제됩니다.

### 밸런스 게임과 팀 나누기

준비된 30개의 가벼운 대화 질문 중 하나를 랜덤으로 뽑습니다.
한 바퀴를 돌기 전에는 질문이 중복되지 않으며 다음 바퀴 첫 질문도 직전과 같지 않습니다.
질문을 바꾸면 이전 선택 및 팀 결과를 초기화합니다.

승패 · 음료 내기 탭에서 **참가자 이름만 저장해도** 이 기능을 사용할 수 있습니다.
각 참가자가 A/B를 고르면 같은 답을 고른 사람끼리 팀을 만듭니다.
모두 선택해야 팀 버튼이 활성화됩니다.
모두 같은 답이면 다음 질문을 뽑거나 인원 균등 랜덤 팀을 사용할 수 있습니다.
인원 균등 랜덤 팀은 선택과 별개로 배정하며 홀수 인원은 팀 간 인원 차이가 1명입니다.
질문에 대한 선택과 팀 결과는 화면을 나가면 초기화됩니다.

## 실행

Flutter SDK를 설치하고 SDK의 bin 경로를 PATH에 등록한 후 IDE를 다시 실행하세요.
Windows 앱에는 Visual Studio의 C++를 사용한 데스크톱 개발 워크로드가 필요합니다.

프로젝트 루트(pubspec.yaml이 있는 폴더)에서 실행합니다.

~~~powershell
flutter doctor -v
flutter pub get
flutter run -d windows
~~~

새 저장소 패키지를 추가했으므로 flutter pub get이 필요합니다.
Firebase 연결 설정 및 사용 권한도 필요합니다.

## 검증

~~~powershell
dart format lib/models/party_session.dart lib/services/party_session_store.dart lib/screens/party_screen.dart test/party_session_test.dart test/party_screen_test.dart test/widget_test.dart
flutter analyze
flutter test
~~~

테스트는 인원 범위, 게임별 집계, 동률, 미참가, JSON 복원, 질문 중복 방지,
A/B 팀 배정, 균등 팀의 누락·중복 방지, 화면에서 승패 저장·복원, 저장 실패를 다룹니다.

## Windows Firebase 링크 오류

MSVC 14.39에서 현재 Firebase Windows 라이브러리를 링크하면 `__std_find_end_1`,
`_Cnd_timedwait_for_unchecked` 등의 LNK2019/LNK2001 오류가 발생할 수 있습니다.
Visual Studio Installer에서 Visual Studio 2022와 설치된 C++ 도구를 업데이트하세요.
그 후 프로젝트 루트에서 `flutter clean`, `flutter pub get`,
`flutter run -d windows` 순서로 다시 실행하세요. LNK4099는 별도의 디버그 기호 경고입니다.

.

## 앞으로 보안 사항

2026-10-18 점검 결과, 아래 세 가지를 순서대로 처리해야 합니다.

### 1. 관리자 PIN 바꾸기 (바로)

예전 코드에 들어 있던 기본 관리자 PIN은 10/14 커밋(8abebed)에서 지웠지만,
**git 커밋 기록에는 그대로 남아 있습니다.** 이 저장소는 공개 저장소라 누구나 그 값을 볼 수 있습니다.

- Firebase 콘솔 → Firestore → `settings/adminPin` 문서의 `pin`, `webPassword` 값을 새 값으로 바꾸세요.
- 새 값은 코드·README·커밋 메시지에 절대 적지 마세요.

### 2. Firestore 보안 규칙 실제로 적용하기

`firestore.rules`(1단계 초안)는 저장소에 있지만 `firebase.json`에 연결되어 있지 않아
**아직 배포되지 않은 상태**입니다. 지금 Firestore는 콘솔에 설정된 규칙으로 동작합니다.

`firebase.json`에 아래 항목을 추가한 뒤 배포하세요.

~~~json
"firestore": {
  "rules": "firestore.rules"
}
~~~

~~~powershell
firebase deploy --only firestore:rules
~~~

배포 전에 손님 패드 주문·직원 호출, 관리자 웹 수정이 정상 동작하는지 확인하세요.

### 3. Firebase Authentication 도입 (Sprint 1)

1단계 규칙을 적용해도 `settings` 문서는 누구나 읽을 수 있습니다(`allow read: if true`).
관리자 비밀번호가 `settings/adminPin`에 평문으로 있으므로 **그대로 보일 수 있습니다.**
또 `games`, `menus`는 누구나 쓸 수 있습니다(`allow write: if true`).

- 관리자: Firebase Authentication 이메일 로그인으로 바꾸고, 비밀번호 비교를 앱이 아닌 Firebase에서 하도록 합니다.
- 손님 태블릿: 익명 로그인을 사용합니다.
- 보안 규칙 2단계: `games`, `menus`, `settings` 쓰기는 관리자만 가능하게, `settings/adminPin`은 읽기도 막습니다.
- BGG 조회 서버 함수(`functions/`)도 비밀번호 헤더 대신 Firebase ID 토큰으로 확인하도록 바꿉니다.
