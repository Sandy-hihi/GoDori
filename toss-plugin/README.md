# 고도리 토스 포스 플러그인 (96차~)

토스 포스 안에서 도는 고도리 플러그인이에요. 토스 개발자센터 '내 애플리케이션'의 포스 플러그인
**고도리 보드게임 패드 (`godori-pad-pos`, 웹 워커)**로 올려요. ACL = `https://godori-pad.web.app`.

왜 플러그인인가: 서버 Open API로 만든 주문은 포스 테이블에 안 붙어서 포스에서 결제할 화면이 없었음(95차 시험).
플러그인은 주문에 `tableId`를 넣을 수 있고, 테이블 비움·결제 신호도 받을 수 있음.

## 지금 하는 일 (0.1.2 — 1단계)

- 켜지자마자 stage boot 신호(가맹점 정보 없이), 그다음 포스가 켜질 때, 10분마다, 테이블이 비워질 때 → 가맹점·포스 기기 번호·홀·테이블 목록을
  `POST /api/toss/plugin/hello` 로 보냄 (서버는 `_tossPlugin/{가맹점}`에 저장만, 기록 `[토스 플러그인]`)
- 주문·결제는 아직 안 건드림

## 만들기

템플릿: github.com/tossplace/toss-pos-plugin-template `worker-plugin-ts`

```
npm install          # (puppeteer 크롬 받기가 막히면 PUPPETEER_SKIP_DOWNLOAD=1)
npm run build        # dist/main.js
npm run zip          # godori-toss-plugin.zip (dist/ 폴더째) → 개발자센터 '개발 배포 > 개발용 파일 추가'
```

새 버전을 올린 뒤에는 포스를 다시 시작해야 반영돼요. 개발 배포는 테스트 단말기(지금 26BP0000WP01528)에만 적용.
버전을 올릴 때는 `src/index.ts`의 VERSION과 package.json version을 같이 바꿀 것.
