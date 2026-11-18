# 고도리 토스 포스 플러그인 (96차~)

토스 포스 안에서 도는 고도리 플러그인이에요. 토스 개발자센터 '내 애플리케이션'의 포스 플러그인
**고도리 보드게임 패드 (`godori-pad-pos`, 웹 워커)**로 올려요. ACL = `https://godori-pad.web.app`.

왜 플러그인인가: 서버 Open API로 만든 주문은 포스 테이블에 안 붙어서 포스에서 결제할 화면이 없었음(95차 시험).
플러그인은 주문에 `tableId`를 넣을 수 있고, 테이블 비움·결제 신호도 받을 수 있음.

## 0.4.0 (113차 — 3단계)

- 넣은 주문이 만든 포스 줄 ID를 서버에 알림(ack `lineIds`) → 포스에서 그 고도리 주문 줄을 모두 지우면 서버가 그 주문만 취소로
- 열린 주문이 바뀔 때도 `POST /api/toss/plugin/event`(orderState OPENED + `paid`·`unpaid`·`lineIds`) → 일부 결제(나눠 내기)를
  손님 패드 '주문 내역'·관리자 방 현황판에 표시. 같은 내용이면 다시 안 보냄
- 테이블 옮기기·합치기(`table.on('move'|'merge')`) → event `kind: 'move'|'merge'` → 서버가 고도리 주문의 테이블·포스 주문 번호를 따라 바꿈
  (합쳐져 없어진 주문의 '취소' 신호는 보내지 않음 — 4초 기다림)
- 놓친 신호 다시 확인: 고도리 주문이 든 열린 포스 주문(storage `godori.open`)을 2분마다 다시 읽음
- 켜질 때·10분마다 최근 24시간 열린 포스 주문을 훑어 세트 구성품 덧붙이기(포스가 꺼져 있던 동안의 세트 주문)
- 세트를 뺐는데 덧붙인 구성품 줄이 남으면 poll `notes`로 알림 → 운영자 페이지 '포스 플러그인' 창 '플러그인 알림'
- 서버 쪽(플러그인 변경 없음): 연결 안 된 메뉴 → 관리자가 고른 '고도리 기타' 포스 상품 줄(메모에 원래 이름·옵션·값),
  포스 상품 품절 → 고도리 메뉴 `posSoldOut`(1분마다)

## 지금 하는 일 (0.2.0 — 2단계, 100차)

- 신호: 켜지자마자 stage boot(가맹점 정보 없이), 켜질 때·10분마다 가맹점·포스 기기 번호·홀·테이블 목록을 `POST /api/toss/plugin/hello`로
  (서버 `_tossPlugin/{가맹점}`, 기록 `[토스 플러그인]`)
- 기기 승인: 첫 hello 때 서버가 이 포스의 열쇠(deviceToken)를 줌 → 포스 storage `godori.token`. 운영자 페이지 매장 카드
  '포스 플러그인'에서 승인해야 주문을 받음(승인 전에는 30초마다 hello로 승인됐는지만 확인). 코드가 공개 저장소라 비밀값 대신 이 방식.
- 주문 넣기(폴링): 승인되면 서버가 정한 간격(3초)마다 `POST /api/toss/plugin/poll` → 대기 주문을 가져와
  방 N에 맞는 테이블(이름이 'N번 방'·'방N' 등으로 같은 것 → 없으면 이름 끝 숫자가 N인 것, 예: 기본홀03 = 3번 방)에
  열린 주문이 있으면 `order.addMenu`(새 줄만), 없으면 `order.add({tableId, orderKey, memo})` → `POST /api/toss/plugin/ack`
  - 넣은 주문은 storage `godori.done`에 기억 → 결과를 못 알렸다가 다시 받아도 두 번 넣지 않음
- 주문 끝: 고도리 주문을 넣은 포스 주문(storage `godori.mine`)이 완료·취소되면 `POST /api/toss/plugin/event` → 서버가 방 정산
- 매장을 플러그인으로 보내게 하는 스위치도 운영자 페이지 '포스 플러그인'(서버 private/tossPos.via = 'plugin')
- 폴링 → 웹소켓은 매장이 많아지면(고도리 '서비스 커지면 바꿀 것' 23번) — `poll()`만 바꾸면 되게 따로 둠

## 만들기

템플릿: github.com/tossplace/toss-pos-plugin-template `worker-plugin-ts`

```
npm install          # (puppeteer 크롬 받기가 막히면 PUPPETEER_SKIP_DOWNLOAD=1)
npm run build        # dist/main.js
npm run zip          # godori-toss-plugin.zip (dist/ 폴더째) → 개발자센터 '개발 배포 > 개발용 파일 추가'
```

새 버전을 올린 뒤에는 포스를 다시 시작해야 반영돼요. 개발 배포는 테스트 단말기(지금 26BP0000WP01528)에만 적용.
버전을 올릴 때는 `src/index.ts`의 VERSION과 package.json version을 같이 바꿀 것.
