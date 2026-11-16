// 고도리 토스 포스 플러그인
//
// 토스 포스 안(웹 워커, 화면 없음)에서 돌면서 고도리 서버(https://godori-pad.web.app/api/toss/plugin/*)와 이야기함.
//   96차 0.1.x: '살아 있어요' 신호(hello) — 가맹점·포스 시리얼·홀·테이블 목록
//     0.1.1 켜지자마자 'boot' 신호·단계별 오류, 0.1.2 table.getHalls() = {halls:[…]}(문서와 다름) → asList로 받음
//   100차 0.2.0: 2단계 — 패드 주문을 방에 맞는 테이블에 넣기 (폴링)
//     ① hello 때 서버가 이 기기 열쇠(deviceToken)를 줌 → storage에 저장. 운영자 페이지에서 승인해야 주문을 받음
//        (플러그인 코드는 공개 저장소라 비밀값을 넣을 수 없어서)
//     ② 승인되면 몇 초마다(서버가 정한 pollMs) POST /plugin/poll → 대기 주문을 가져옴(서버가 한 포스에만 줌)
//     ③ 방 N에 맞는 테이블: 이름이 'N번 방'·'방N'처럼 같은 것 → 없으면 이름 끝 숫자가 N인 것(기본홀03 = 3번 방)
//        그 테이블에 열린 주문이 있으면 addMenu(새 줄만), 없으면 add({tableId, orderKey, memo}) → POST /plugin/ack
//     ④ 넣은 포스 주문이 완료·취소되면(order 'complete'·'update', payment 'paid') POST /plugin/event → 서버가 방 정산
//     같은 주문을 두 번 넣지 않게 넣은 주문 번호를 storage에 기억(서버에 결과를 못 알렸을 때 다시 받아도 결과만 다시 알림)
//   주문 가져오기는 폴링 — 매장이 많아지면 웹소켓으로 (고도리 '서비스 커지면 바꿀 것' 23번). poll()만 바꾸면 되게 따로 둠.
//   103차 0.3.0: 세트 구성품 재고 — 토스는 세트를 팔면 세트 상품 재고만 줄이고 구성품 재고는 그대로라서,
//     세트가 든 포스 주문(패드 주문이든 직원이 포스에서 직접 누른 주문이든)에 구성품을 0원 줄로 덧붙임 → 토스가 구성품 재고를 줄임.
//     구성표는 관리자 웹 '토스 POS 연동 > 세트 구성품'에서 정하고, poll 때 바뀌었으면 서버가 같이 줌(sets·setMapRev).
//     열린 주문(OPENED·REQUESTED)에만. 이미 있는 0원 구성품 줄 + 이 포스에서 덧붙인 개수(godori.parts)를 보고 모자란 만큼만 덧붙임.
//     ★세트를 결제 전에 지워도 덧붙인 구성품 줄은 남음(SDK에 줄 지우기가 없음) — 직원이 포스에서 같이 지워야 함.
//   0.3.1: 덧붙이기 결과·실패를 서버 기록에(가맹점 ID 없이 — 저장된 테이블 목록을 덮지 않게)
//   0.3.2: 구성품 조건(whenChoice) — 세트 줄에서 그 옵션 선택을 골랐을 때만 (예: [떡볶이] 로제 → 로제 떡볶이)
//   0.3.3: 11-16 시험 — 포스가 줄의 chargePrice 0을 무시하고 상품 값으로 받음(로제 떡볶이 x2 16,800원이 계산서에 더해짐)
//          → 구성품은 1개씩 줄로 넣고, 그 줄에 상품 값(+ 골라 둔 옵션 값)만큼 할인(discounts)을 붙여 0원으로 만듦
//          → 이미 있는 구성품 줄은 memo(SET_MEMO)로 알아봄
import { posPluginSdk } from "@tossplace/pos-plugin-sdk";

const SERVER = "https://godori-pad.web.app";
const VERSION = "0.3.3";
const HELLO_EVERY_MS = 10 * 60 * 1000;
const WAIT_MS = 30 * 1000; // 승인 전·플러그인으로 안 보내는 매장
const K_TOKEN = "godori.token";
const K_DONE = "godori.done"; // { 고도리 주문 ID: { posOrderId, tableId, tableTitle, appended } } — 최근 200개
const K_MINE = "godori.mine"; // 고도리 주문을 넣은 포스 주문 ID — 최근 300개
const K_PARTS = "godori.parts"; // 103차 { 포스 주문 ID: { 구성품 상품 ID: 덧붙인 개수 } } — 최근 200개
const SET_MEMO = "세트 구성품(재고 차감용)";
const SET_DISCOUNT = "세트 구성품";

type Obj = Record<string, any>;

const errText = (e: unknown): string => {
  if (e && typeof e === "object") {
    const o = e as { code?: unknown; message?: unknown; name?: unknown };
    return [o.name, o.code, o.message].filter((x) => x != null && x !== "").map(String).join(" ") || String(e);
  }
  return String(e);
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
// 배열이면 그대로, 객체면 안의 배열을 찾아서 (0.1.2: getHalls가 {halls:[…]})
const asList = (v: unknown): Obj[] => {
  if (Array.isArray(v)) return v as Obj[];
  if (v && typeof v === "object") {
    const o = v as Obj;
    for (const k of ["content", "items", "list", "data", "halls", "tables", "result", "success"]) {
      if (Array.isArray(o[k])) return o[k] as Obj[];
      if (o[k] && typeof o[k] === "object") {
        const inner = asList(o[k]);
        if (inner.length) return inner;
      }
    }
  }
  return [];
};

// ── 저장 (포스 storage) ──
async function loadJson<T>(key: string, fallback: T): Promise<T> {
  try {
    const s = await posPluginSdk.storage.get(key);
    return s ? (JSON.parse(s) as T) : fallback;
  } catch {
    return fallback;
  }
}
async function saveJson(key: string, v: unknown) {
  try {
    await posPluginSdk.storage.set(key, JSON.stringify(v));
  } catch (e) {
    console.log("[고도리] 저장 실패", key, errText(e));
  }
}
async function remember(orderId: string, info: Obj) {
  const done = await loadJson<Obj>(K_DONE, {});
  done[orderId] = info;
  const keys = Object.keys(done);
  for (const k of keys.slice(0, Math.max(0, keys.length - 200))) delete done[k];
  await saveJson(K_DONE, done);
  const mine = await loadJson<string[]>(K_MINE, []);
  if (!mine.includes(info.posOrderId)) await saveJson(K_MINE, [...mine, info.posOrderId].slice(-300));
}

// ── 서버 ──
const state = {
  merchantId: null as number | null,
  merchantName: "",
  serial: "",
  token: "",
  approved: false,
  pollMs: WAIT_MS,
};

async function post(path: string, body: Obj): Promise<{ code: number; json: Obj }> {
  const res = await posPluginSdk.http.post(`${SERVER}/api/toss/plugin/${path}`, { version: VERSION, ...body },
    [["Content-Type", "application/json"]], { timeoutMs: 10000 });
  let json: Obj = {};
  try {
    json = typeof res.body === "string" ? JSON.parse(res.body) : (res.body as Obj) || {};
  } catch {
    json = {};
  }
  return { code: Number(res.code), json };
}
const who = () => ({ merchantId: state.merchantId, serial: state.serial, token: state.token });

async function identify(errors: string[]) {
  if (state.merchantId == null) {
    try {
      const m = await posPluginSdk.merchant.getMerchant();
      state.merchantId = m.id;
      state.merchantName = m.name;
    } catch (e) {
      errors.push(`merchant: ${errText(e)}`);
    }
  }
  if (!state.serial) {
    try {
      state.serial = (await posPluginSdk.device.getDeviceInfo()).serialNumber || "";
    } catch (e) {
      errors.push(`device: ${errText(e)}`);
    }
  }
  if (!state.token) state.token = (await posPluginSdk.storage.get(K_TOKEN).catch(() => undefined)) || "";
}

async function readTables(): Promise<{ tables: Obj[]; error: string }> {
  try {
    return { tables: asList(await posPluginSdk.table.getTables()), error: "" };
  } catch (e) {
    // 테이블 API는 '음식점 → 후불형 매장'에서만 켜짐
    return { tables: [], error: errText(e) };
  }
}

async function hello(reason: string) {
  const errors: string[] = [];
  try {
    await identify(errors);
    let halls: Obj[] = [];
    let tableError = "";
    try {
      halls = asList(await posPluginSdk.table.getHalls()).map((h) => ({ id: Number(h.id), title: String(h.title ?? "") }));
    } catch (e) {
      tableError = `halls: ${errText(e)}`;
    }
    const t = await readTables();
    if (t.error) tableError = [tableError, `tables: ${t.error}`].filter(Boolean).join(" / ");
    const tables = t.tables.map((x) => ({ id: Number(x.id), hallId: Number(x.hallId), title: String(x.title ?? ""), hasOrder: !!x.order }));
    const { code, json } = await post("hello", {
      stage: "hello", reason, ...who(), merchantName: state.merchantName, halls, tables, tableError, errors,
    });
    if (code !== 200) {
      console.log(`[고도리] 신호(${reason}) → ${code}`, json);
      return;
    }
    if (json.deviceToken) {
      state.token = String(json.deviceToken);
      await posPluginSdk.storage.set(K_TOKEN, state.token);
    }
    state.approved = json.approved === true;
    state.pollMs = Number(json.pollMs) || WAIT_MS;
    if (json.deviceProblem) console.log("[고도리]", json.deviceProblem);
  } catch (e) {
    console.log(`[고도리] 신호(${reason}) 실패`, errText(e));
  }
}

// ── 방 → 테이블 ──
const norm = (s: unknown) => String(s ?? "").replace(/\s+/g, "").toLowerCase();
function pickTable(tables: Obj[], room: number): Obj | null {
  const names = [`${room}번방`, `방${room}`, `${room}번`, `room${room}`, `${room}`];
  const same = tables.find((t) => names.includes(norm(t.title)));
  if (same) return same;
  const byNumber = tables.filter((t) => {
    const m = /(\d+)\s*$/.exec(String(t.title ?? ""));
    return !!m && Number(m[1]) === room;
  });
  return byNumber[0] || null;
}

// ── 주문 넣기 ──
async function ack(body: Obj) {
  try {
    const { code, json } = await post("ack", { ...who(), ...body });
    if (code !== 200) console.log("[고도리] 결과 알리기", code, json);
  } catch (e) {
    console.log("[고도리] 결과 알리기 실패", errText(e));
  }
}

async function place(o: Obj) {
  const orderId = String(o.orderId);
  const done = await loadJson<Obj>(K_DONE, {});
  if (done[orderId]) {
    // 이미 넣었는데 서버가 결과를 못 받았던 주문 — 결과만 다시
    await ack({ orderId, ok: true, ...done[orderId], warnings: o.warnings || [] });
    return;
  }
  const room = Number(o.room);
  const { tables, error } = await readTables();
  if (error) {
    await ack({ orderId, ok: false, code: "NO_TABLE_API", error: `포스 테이블을 읽지 못했어요: ${error}`.slice(0, 200) });
    return;
  }
  const table = Number.isFinite(room) ? pickTable(tables, room) : null;
  if (!table) {
    await ack({ orderId, ok: false, code: "NO_TABLE", error: `${Number.isFinite(room) ? `${room}번 방` : "이 주문"}에 맞는 포스 테이블이 없어요.` });
    return;
  }
  const open = table.order && ["OPENED", "REQUESTED"].includes(String(table.order.orderState)) ? table.order : null;
  let posOrder: Obj | null = null;
  try {
    if (open) {
      posOrder = await posPluginSdk.order.addMenu(String(open.id), { discounts: [], lineItems: o.lineItems } as any);
    } else {
      posOrder = await posPluginSdk.order.add({
        orderKey: o.orderKey, memo: o.memo, tableId: Number(table.id), discounts: [], lineItems: o.lineItems,
      } as any);
    }
  } catch (e) {
    await ack({ orderId, ok: false, code: "POS_REJECTED", error: `포스가 주문을 받지 않았어요: ${errText(e)}`.slice(0, 200) });
    return;
  }
  const info = {
    posOrderId: String((posOrder && posOrder.id) || (open && open.id) || ""),
    tableId: Number(table.id),
    tableTitle: String(table.title ?? ""),
    appended: !!open,
  };
  if (!info.posOrderId) {
    await ack({ orderId, ok: false, code: "NO_POS_ID", error: "포스가 주문 번호를 돌려주지 않았어요." });
    return;
  }
  await remember(orderId, info);
  kickSetParts(info.posOrderId);
  const amount = posOrder && posOrder.chargePrice ? posOrder.chargePrice.chargePriceValue : null;
  await ack({ orderId, ok: true, ...info, posAmount: amount, warnings: o.warnings || [] });
}

// 폴링 — 웹소켓으로 바꿀 때는 이 함수만 바꾸면 됨
async function poll() {
  const { code, json } = await post("poll", { ...who(), setMapRev: sets.rev });
  if (code === 403) {
    state.approved = false;
    state.pollMs = WAIT_MS;
    return;
  }
  if (code !== 200) {
    state.pollMs = WAIT_MS;
    return;
  }
  state.pollMs = Number(json.pollMs) || WAIT_MS;
  applySets(json);
  for (const o of (json.orders as Obj[]) || []) {
    try {
      await place(o);
    } catch (e) {
      await ack({ orderId: String(o.orderId), ok: false, code: "PLUGIN_ERROR", error: errText(e).slice(0, 200) });
    }
  }
}

async function loop() {
  for (;;) {
    try {
      if (state.approved) await poll();
      else await hello("wait"); // 운영자가 승인하면 다음 신호에서 approved
    } catch (e) {
      console.log("[고도리] 반복 중 오류", errText(e));
    }
    await sleep(Math.max(1000, state.pollMs));
  }
}

// ── 세트 구성품 덧붙이기 (103차) ──
type SetPart = { itemId: number; qty: number; choices: { id: number; quantity: number }[]; whenChoice?: number };
const sets = { rev: -1, map: new Map<number, SetPart[]>() };
function applySets(json: Obj) {
  if (!Array.isArray(json.sets)) return; // 바뀐 게 없으면 서버가 안 보냄
  sets.map = new Map((json.sets as Obj[]).map((s) => [Number(s.setId), ((s.parts as SetPart[]) || [])]));
  sets.rev = Number(json.setMapRev) || 0;
  console.log(`[고도리] 세트 구성표 ${sets.map.size}개 (번호 ${sets.rev})`);
  setLog("info", `세트 구성표 받음 ${sets.map.size}개 (번호 ${sets.rev})`);
}

const partsBusy = new Set<string>();
const partsAgain = new Set<string>();
function kickSetParts(posOrderId: string) {
  if (!posOrderId || !sets.map.size) return;
  if (partsBusy.has(posOrderId)) {
    partsAgain.add(posOrderId); // 덧붙이는 중에 또 바뀜 → 끝나고 한 번 더 확인
    return;
  }
  partsBusy.add(posOrderId);
  (async () => {
    try {
      do {
        partsAgain.delete(posOrderId);
        await addSetParts(posOrderId);
      } while (partsAgain.has(posOrderId));
    } catch (e) {
      console.log("[고도리] 세트 구성품 덧붙이기 실패", posOrderId, errText(e));
      setLog("error", `실패 ${posOrderId}: ${errText(e)}`);
    } finally {
      partsBusy.delete(posOrderId);
    }
  })();
}

// 0.3.1: 서버 기록(firebase functions:log)에 남김 — 가맹점 ID를 빼고 보내서 서버가 저장은 안 하고 기록만
//   (가맹점 ID를 넣어 hello로 보내면 저장된 테이블 목록이 빈 목록으로 덮임 — 0.3.0 실수)
function setLog(stage: string, text: string) {
  post("hello", { stage, reason: "set-parts", errors: [`가맹점 ${state.merchantId} 포스 ${state.serial}: ${text}`.slice(0, 200)] }).catch(() => undefined);
}

const num = (v: unknown) => Number(v) || 0;
async function addSetParts(posOrderId: string) {
  const order = (await posPluginSdk.order.getOrder(posOrderId)) as Obj;
  const st = String(order.orderState);
  if (st !== "OPENED" && st !== "REQUESTED") return; // 결제 끝·취소된 주문엔 안 붙임
  const lines = (order.lineItems as Obj[]) || [];
  // 세트 줄 → 필요한 구성품 개수 (같은 구성품은 합침)
  const need = new Map<number, { qty: number; part: SetPart; dining: string }>();
  for (const li of lines) {
    const parts = sets.map.get(num(li.item && li.item.id));
    if (!parts) continue;
    const n = num(li.quantity && li.quantity.value);
    const picked = new Set(((li.optionChoices as Obj[]) || []).map((c) => num(c && c.id)));
    for (const p of parts) {
      if (p.whenChoice != null && !picked.has(num(p.whenChoice))) continue; // 그 옵션을 안 고른 세트
      const cur = need.get(p.itemId);
      need.set(p.itemId, { qty: (cur ? cur.qty : 0) + n * num(p.qty), part: cur ? cur.part : p, dining: cur ? cur.dining : String(li.diningOption || "HERE") });
    }
  }
  if (!need.size) return;
  // 이미 있는 구성품 줄 (메모로 알아봄 — 0.3.2까지 넣은 줄도 같은 메모)
  const have = new Map<number, number>();
  for (const li of lines) {
    const id = num(li.item && li.item.id);
    if (!need.has(id) || (String(li.memo || "") !== SET_MEMO && num(li.chargePrice && li.chargePrice.value) !== 0)) continue;
    have.set(id, (have.get(id) || 0) + num(li.quantity && li.quantity.value));
  }
  const all = await loadJson<Obj>(K_PARTS, {});
  const added: Obj = { ...(all[posOrderId] || {}) };
  const lineItems: Obj[] = [];
  for (const [itemId, n] of need) {
    const got = Math.max(have.get(itemId) || 0, num(added[itemId]));
    const missing = n.qty - got;
    if (missing <= 0) continue;
    const c = ((await posPluginSdk.catalog.getCatalog(itemId)) || {}) as Obj;
    const cat = (c.category || {}) as Obj;
    // 1개 값 = 상품 값 + 골라 둔 옵션 선택 값 → 이만큼 할인해서 0원
    const picks = new Set((n.part.choices || []).map((x) => num(x.id)));
    let unit = num(c.price && c.price.priceValue);
    for (const o of (c.options as Obj[]) || []) {
      for (const ch of (o.choices as Obj[]) || []) if (picks.has(num(ch.id))) unit += num(ch.priceValue);
    }
    for (let k = 0; k < missing; k++) {
      lineItems.push({
        diningOption: n.dining,
        item: { id: itemId, title: String(c.title ?? ""), category: { id: num(cat.id), title: String(cat.title ?? "") }, ...(c.code ? { code: String(c.code) } : {}), type: "ITEM" },
        quantity: { value: 1 },
        chargePrice: { value: 0 },
        optionChoices: n.part.choices || [],
        ...(unit > 0 ? { discounts: [{ title: SET_DISCOUNT, amountMoney: { value: unit } }] } : {}),
        memo: SET_MEMO,
      });
    }
    added[itemId] = got + missing;
  }
  if (!lineItems.length) return;
  await posPluginSdk.order.addMenu(posOrderId, { discounts: [], lineItems } as any);
  all[posOrderId] = added;
  const keys = Object.keys(all);
  for (const k of keys.slice(0, Math.max(0, keys.length - 200))) delete all[k];
  await saveJson(K_PARTS, all);
  const done = lineItems.map((l) => `${l.item.title}(-${l.discounts ? l.discounts[0].amountMoney.value : 0})`).join(", ");
  console.log(`[고도리] 세트 구성품 덧붙임 ${posOrderId}:`, done);
  setLog("info", `덧붙임 ${posOrderId}: ${done}`);
}

// ── 포스 주문이 끝나면 알림 ──
const reported = new Set<string>();
async function report(posOrderId: string, why: string) {
  try {
    const mine = await loadJson<string[]>(K_MINE, []);
    if (!mine.includes(String(posOrderId))) return; // 고도리 주문이 안 들어간 포스 주문
    const order = await posPluginSdk.order.getOrder(String(posOrderId));
    const st = String(order.orderState);
    if (st !== "COMPLETED" && st !== "CANCELLED") return;
    const key = `${posOrderId}:${st}`;
    if (reported.has(key)) return;
    const { code } = await post("event", {
      ...who(), posOrderId: String(posOrderId), orderState: st, paymentState: order.paymentState,
      unpaid: order.paymentPrice ? order.paymentPrice.paymentUnpaidValue : null, reason: why,
    });
    if (code === 200) reported.add(key);
  } catch (e) {
    console.log("[고도리] 주문 끝 알리기 실패", errText(e));
  }
}

async function main() {
  try {
    await post("hello", { stage: "boot", reason: "boot" });
  } catch (e) {
    console.log("[고도리] boot 신호 실패", errText(e));
  }
  try {
    posPluginSdk.error.addErrorListener((e) => {
      post("hello", { stage: "error", reason: "sdk-error", errors: [errText(e)] }).catch(() => undefined);
    });
  } catch (e) {
    console.log("[고도리] 오류 리스너 못 붙임", errText(e));
  }
  try {
    posPluginSdk.order.on("complete", (id) => report(String(id), "complete"));
    posPluginSdk.order.on("update", (id) => {
      report(String(id), "update");
      kickSetParts(String(id)); // 103차: 직원이 포스에서 세트를 더 넣었을 때도
    });
    posPluginSdk.order.on("add", (id) => kickSetParts(String(id)));
    posPluginSdk.payment.on("paid", (_paymentId, orderId) => report(String(orderId), "paid"));
  } catch (e) {
    post("hello", { stage: "error", reason: "events", errors: [`on: ${errText(e)}`] }).catch(() => undefined);
  }
  await hello("start");
  setInterval(() => hello("timer"), HELLO_EVERY_MS);
  loop();
}

main();
