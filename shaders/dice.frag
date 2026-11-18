#version 460 core
// 고도리 게임도구 주사위 (130차) — 모서리가 둥근 주사위를 화면 점마다 빛을 계산해서 그림(레이마칭)
//   lib/widgets/tools/dice_roller.dart 가 uniform을 넣음:
//   uSize(그릴 사각형 크기) · uOrigin(사각형 왼쪽 위) · uC0·uC1·uC2(주사위 회전 — 단위 벡터 x·y·z를 돌린 것)
//   좌표: x 오른쪽, y 아래, z 화면 안쪽. 화면 쪽 면(-z)=1, 뒤 6, 오른쪽 3, 왼쪽 4, 위 2, 아래 5 (마주 보는 면 합 7)
//   상자 반 크기 1(모서리 반지름 RAD), 눈은 오목한 홈(구를 빼냄)
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uOrigin;
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;

out vec4 fragColor;

const float RAD = 0.22;
const float FOV = 0.25;   // 화면 반 높이 / 카메라 거리
const float CAM = 7.0;
const vec3 BODY = vec3(0.965, 0.945, 0.905);
const vec3 PIP = vec3(0.075, 0.065, 0.06);

vec3 toLocal(vec3 p) {
  return vec3(dot(p, uC0), dot(p, uC1), dot(p, uC2));
}

float sdRoundBox(vec3 p) {
  vec3 q = abs(p) - vec3(1.0 - RAD);
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - RAD;
}

// 그 면 눈 v에서 3×3 칸 (i, j)에 점이 있는지 (u 방향 i, v 방향 j — dice_roller.dart 예전 배치와 같음)
float inLayout(float v, float i, float j) {
  if (i == 0.0 && j == 0.0) return mod(v, 2.0) > 0.5 ? 1.0 : 0.0;
  if (i != 0.0 && j != 0.0) {
    if (i == -j) return v > 1.5 ? 1.0 : 0.0;
    return v > 3.5 ? 1.0 : 0.0;
  }
  if (j == 0.0) return v > 5.5 ? 1.0 : 0.0;
  return 0.0;
}

// 가장 가까운 눈 홈(구)까지의 거리 — 점이 없는 자리면 큰 값
float pipDist(vec3 p) {
  vec3 a = abs(p);
  float v;
  vec2 uv;
  float w;
  if (a.z >= a.x && a.z >= a.y) {
    w = a.z;
    if (p.z < 0.0) { v = 1.0; uv = vec2(p.x, p.y); } else { v = 6.0; uv = vec2(-p.x, p.y); }
  } else if (a.x >= a.y) {
    w = a.x;
    if (p.x > 0.0) { v = 3.0; uv = vec2(p.z, p.y); } else { v = 4.0; uv = vec2(-p.z, p.y); }
  } else {
    w = a.y;
    if (p.y < 0.0) { v = 2.0; uv = vec2(p.x, p.z); } else { v = 5.0; uv = vec2(p.x, -p.z); }
  }
  float gap = 0.52;
  float i = clamp(floor(uv.x / gap + 0.5), -1.0, 1.0);
  float j = clamp(floor(uv.y / gap + 0.5), -1.0, 1.0);
  if (inLayout(v, i, j) < 0.5) return 1.0;
  // 홈: 보이는 반지름 a, 깊이 0.07 → 구 반지름 rho, 면에서 h만큼 바깥에 중심
  float r = v == 1.0 ? 0.25 : 0.185;
  float depth = 0.07;
  float rho = (r * r + depth * depth) / (2.0 * depth);
  float h = rho - depth;
  vec3 q = vec3(uv - vec2(i, j) * gap, w - (1.0 + h));
  return length(q) - rho;
}

float smax(float a, float b, float k) {
  float hh = clamp(0.5 - 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, hh) + k * hh * (1.0 - hh);
}

float map(vec3 p) {
  return smax(sdRoundBox(p), -pipDist(p), 0.015);
}

vec3 calcNormal(vec3 p) {
  const float e = 0.0015;
  vec3 k1 = vec3(1.0, -1.0, -1.0);
  vec3 k2 = vec3(-1.0, -1.0, 1.0);
  vec3 k3 = vec3(-1.0, 1.0, -1.0);
  vec3 k4 = vec3(1.0, 1.0, 1.0);
  return normalize(k1 * map(p + k1 * e) + k2 * map(p + k2 * e) + k3 * map(p + k3 * e) + k4 * map(p + k4 * e));
}

float ambientOcc(vec3 p, vec3 n) {
  float o = 0.0;
  float s = 1.0;
  for (int i = 1; i <= 4; i++) {
    float hh = 0.035 * float(i);
    o += (hh - map(p + n * hh)) * s;
    s *= 0.65;
  }
  return clamp(1.0 - 3.5 * o, 0.0, 1.0);
}

void main() {
  vec2 fc = FlutterFragCoord().xy - uOrigin;
  vec2 uv = (fc - 0.5 * uSize) / (0.5 * uSize.y);
  vec3 ro = vec3(0.0, 0.0, -CAM);
  vec3 rd = normalize(vec3(uv * FOV, 1.0));

  // 둘레 구(반지름 1.8)와 안 만나면 빈칸
  float b = dot(ro, rd);
  float c = dot(ro, ro) - 1.8 * 1.8;
  float disc = b * b - c;
  if (disc < 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  float t = -b - sqrt(disc);
  float tEnd = -b + sqrt(disc);
  float minD = 1000.0;
  float tMin = t;
  float hit = 0.0;
  for (int k = 0; k < 80; k++) {
    float d = map(toLocal(ro + rd * t));
    if (d < minD) {
      minD = d;
      tMin = t;
    }
    if (d < 0.0006) {
      hit = 1.0;
      break;
    }
    t += d;
    if (t > tEnd) break;
  }
  // 바깥 윤곽 매끈하게: 한 화소 크기 안으로 스치면 반투명
  float px = (2.0 * FOV * CAM) / uSize.y;
  float alpha = hit > 0.5 ? 1.0 : 1.0 - smoothstep(0.0, px * 1.3, minD);
  if (alpha <= 0.001) {
    fragColor = vec4(0.0);
    return;
  }
  float th = hit > 0.5 ? t : tMin;
  vec3 pl = toLocal(ro + rd * th);
  vec3 nl = calcNormal(pl);
  vec3 n = normalize(uC0 * nl.x + uC1 * nl.y + uC2 * nl.z);

  vec3 L = normalize(vec3(-0.45, -0.75, -0.55));
  vec3 V = -rd;
  vec3 H = normalize(L + V);
  float diff = max(dot(n, L), 0.0);
  float spec = pow(max(dot(n, H), 0.0), 60.0);
  float fres = pow(1.0 - max(dot(n, V), 0.0), 3.0);
  float ao = ambientOcc(pl, nl);
  float isPip = 1.0 - smoothstep(0.004, 0.02, pipDist(pl));
  vec3 base = mix(BODY, PIP, isPip);

  vec3 col = base * (0.45 + 0.55 * diff) * ao;
  col += base * vec3(1.0, 0.97, 0.92) * 0.1 * max(dot(n, vec3(0.0, 1.0, 0.0)), 0.0); // 바닥에서 튀는 은은한 빛
  col += base * 0.08 * max(dot(n, vec3(0.6, -0.2, -0.4)), 0.0); // 오른쪽 보조광
  col += vec3(1.0) * spec * mix(0.55, 0.3, isPip) * ao;
  col += vec3(0.95, 0.96, 1.0) * fres * 0.1 * (1.0 - isPip);
  col = clamp(col, 0.0, 1.0);
  fragColor = vec4(col * alpha, alpha);
}
