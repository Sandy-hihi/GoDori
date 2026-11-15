// 고도리 토스 포스 플러그인 (96차 — 1단계: '살아 있어요' 신호)
//
// 토스 포스 안(웹 워커, 화면 없음)에서 돌면서 고도리 서버 POST https://godori-pad.web.app/api/toss/plugin/hello 로 신호를 보냄.
//   0.1.1: 켜지자마자 가맹점 정보 없이 stage 'boot' 신호부터 보냄 → 단계마다 오류(errors[])도 같이 보냄
//          (0.1.0은 서버에 한 번도 닿지 않았는데 포스 안 로그를 볼 방법이 없어서)
//   0.1.2: 0.1.0 신호에서 table.getHalls/getTables 결과가 배열이 아니었음('.map is not a function')
//          → 배열·{content|items|list|data|halls|tables} 모양 모두 받고, 처음 몇 번은 받은 모양(shapes)을 서버로 보냄
//   - 포스가 켜질 때, 10분마다, 테이블이 비워질 때: 가맹점 + 기기 번호 + 홀·테이블 목록(후불형 매장에서만 됨)
// 서버는 저장·기록만 함(운영자 GET /api/ops/toss/plugins, 서버 기록 '[토스 플러그인]').
// 아직 주문·결제는 건드리지 않음 — 2단계에서 '패드 주문 → 방에 연결된 테이블에 주문 넣기'를 붙일 예정.
import { posPluginSdk } from "@tossplace/pos-plugin-sdk";

const SERVER = "https://godori-pad.web.app";
const VERSION = "0.1.2";
const EVERY_MS = 10 * 60 * 1000;

const errText = (e: unknown): string => {
  if (e && typeof e === "object") {
    const o = e as { code?: unknown; message?: unknown; name?: unknown };
    return [o.name, o.code, o.message].filter((x) => x != null && x !== "").map(String).join(" ") || String(e);
  }
  return String(e);
};

type Obj = Record<string, any>;
let shapeReports = 0;
// 응답 모양 요약 (값은 앞부분만) — 0.1.2 디버그용
const shapeOf = (v: unknown): string => {
  try {
    if (Array.isArray(v)) return `array(${v.length}) ${JSON.stringify(v[0] ?? null).slice(0, 120)}`;
    if (v && typeof v === "object") return `object{${Object.keys(v as Obj).slice(0, 10).join(",")}} ${JSON.stringify(v).slice(0, 120)}`;
    return `${typeof v} ${String(v).slice(0, 60)}`;
  } catch (e) {
    return `? ${errText(e)}`;
  }
};
// 배열이면 그대로, 객체면 안의 배열을 찾아서
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

async function send(payload: Record<string, unknown>, reason: string) {
  try {
    const res = await posPluginSdk.http.post(`${SERVER}/api/toss/plugin/hello`, { version: VERSION, reason, ...payload },
      [["Content-Type", "application/json"]], { timeoutMs: 10000 });
    console.log(`[고도리] 신호(${reason}) → ${res.code}`, res.body);
  } catch (e) {
    console.log(`[고도리] 신호(${reason}) 실패`, errText(e));
  }
}

async function collect() {
  const errors: string[] = [];
  let merchantId: number | null = null;
  let merchantName = "";
  try {
    const m = await posPluginSdk.merchant.getMerchant();
    merchantId = m.id;
    merchantName = m.name;
  } catch (e) {
    errors.push(`merchant: ${errText(e)}`);
  }
  let serial = "";
  try {
    serial = (await posPluginSdk.device.getDeviceInfo()).serialNumber || "";
  } catch (e) {
    errors.push(`device: ${errText(e)}`);
  }
  let halls: { id: number; title: string }[] = [];
  let tables: { id: number; hallId: number; title: string; hasOrder: boolean }[] = [];
  let tableError = "";
  const shapes: string[] = [];
  try {
    const rawHalls: unknown = await posPluginSdk.table.getHalls();
    shapes.push(`halls: ${shapeOf(rawHalls)}`);
    halls = asList(rawHalls).map((h) => ({ id: Number(h.id), title: String(h.title ?? "") }));
  } catch (e) {
    // 테이블 API는 '음식점 → 후불형 매장'에서만 켜짐
    tableError = `halls: ${errText(e)}`;
  }
  try {
    const rawTables: unknown = await posPluginSdk.table.getTables();
    shapes.push(`tables: ${shapeOf(rawTables)}`);
    tables = asList(rawTables).map((t) => ({
      id: Number(t.id), hallId: Number(t.hallId), title: String(t.title ?? ""), hasOrder: !!t.order,
    }));
  } catch (e) {
    tableError = [tableError, `tables: ${errText(e)}`].filter(Boolean).join(" / ");
  }
  if (shapeReports < 3) {
    shapeReports++;
    errors.push(...shapes);
  }
  return { stage: "hello", merchantId, merchantName, serial, halls, tables, tableError, errors };
}

async function hello(reason: string) {
  let payload: Record<string, unknown>;
  try {
    payload = await collect();
  } catch (e) {
    payload = { stage: "collect-failed", errors: [errText(e)] };
  }
  await send(payload, reason);
}

async function main() {
  await send({ stage: "boot" }, "boot");
  try {
    posPluginSdk.error.addErrorListener((e) => {
      send({ stage: "error", errors: [errText(e)] }, "sdk-error");
    });
  } catch (e) {
    console.log("[고도리] 오류 리스너 못 붙임", errText(e));
  }
  await hello("start");
  setInterval(() => hello("timer"), EVERY_MS);
  // 테이블이 비워지면 바로 한 번 더 (2단계 '방 정산' 신호 자리 시험)
  try {
    posPluginSdk.table.on("clear", () => hello("table-clear"));
  } catch (e) {
    send({ stage: "error", errors: [`table.on: ${errText(e)}`] }, "table-on");
  }
}

main();
