/**
 * Luật quyết định huyết áp theo chuẩn AHA/ACC. Thuần logic, không phụ thuộc gì.
 * Bản Dart song song: app/lib/features/bp/domain/bp_protocol.dart. Cả hai chạy chung bộ ca
 * api/_tests/fixtures/bp_protocol_cases.json để không lệch nhau.
 */
import script from './bp_script.json' with { type: 'json' };

export type BpCategory = 'normal' | 'elevated' | 'stage1' | 'stage2' | 'crisis';
export type BpAction = 'none' | 'rest_recheck' | 'recheck_1min' | 'ask_symptoms' | 'monitor' | 'call_doctor_today' | 'call_doctor_now' | 'call_115';
export type BpContext = 'woke_up' | 'exertion' | 'caffeine_smoke';
export type ScriptKey = keyof typeof script;

/** [tâm thu, tâm trương, đã ngồi nghỉ yên đủ 5 phút trước số đo này]. */
export type Reading = { s: number; d: number; rested: boolean };

export interface BpDecision {
  avgSys: number;
  avgDia: number;
  /** Số lần đo được dùng để tính trung bình. */
  count: number;
  category: BpCategory;
  action: BpAction;
  script: ScriptKey;
  /** Ít nhất một số đo có ngồi nghỉ đủ chuẩn. */
  protocolOk: boolean;
}

/** Ngưỡng AHA: cao hơn 180 hoặc cao hơn 120 là rất cao (180/120 đúng chưa tính). */
export const isSevere = (s: number, d: number): boolean => s > 180 || d > 120;

export function categoryOf(s: number, d: number): BpCategory {
  if (isSevere(s, d)) return 'crisis';
  if (s >= 140 || d >= 90) return 'stage2';
  if (s >= 130 || d >= 80) return 'stage1';
  if (s >= 120) return 'elevated';
  return 'normal';
}

const avg = (xs: number[]): number => Math.round(xs.reduce((a, b) => a + b, 0) / xs.length);

export function decide(input: { readings: Reading[]; context?: BpContext[]; symptoms?: boolean | null }): BpDecision {
  const all = input.readings;
  const ctx = new Set(input.context ?? []);
  const symptoms = input.symptoms ?? null;
  const protocolOk = all.some((r) => r.rested);
  if (all.length === 0) return { avgSys: 0, avgDia: 0, count: 0, category: 'normal', action: 'none', script: 'normal', protocolOk: false };

  const latest = all[all.length - 1];
  const latestSevere = isSevere(latest.s, latest.d);
  const anySevere = all.some((r) => isSevere(r.s, r.d));
  // Số chưa ngồi nghỉ đủ chuẩn bị bỏ khi đã có số đo đủ chuẩn, trừ khi có số rất cao (an toàn trước).
  const pool = anySevere || !protocolOk ? all : all.filter((r) => r.rested);
  const a = { s: avg(pool.map((r) => r.s)), d: avg(pool.map((r) => r.d)) };
  const base = { avgSys: a.s, avgDia: a.d, count: pool.length, protocolOk };
  const category: BpCategory = latestSevere ? 'crisis' : categoryOf(a.s, a.d);
  const out = (action: BpAction, key: ScriptKey): BpDecision => ({ ...base, category, action, script: key });

  if (symptoms === true) return out('call_115', 'emergency');

  if (latestSevere) {
    if (all.length === 1) return out('recheck_1min', 'severe_wait');
    if (symptoms === false) return out('call_doctor_now', 'severe_confirm');
    return out('ask_symptoms', 'ask_symptoms');
  }

  if (category === 'normal') return out('none', 'normal');

  // Số đầu tiên chưa nghỉ mà vừa uống cà phê / hút thuốc: chờ khoảng 30 phút, không đủ 5 phút.
  if (pool.length === 1 && !pool[0].rested && ctx.has('caffeine_smoke')) return out('rest_recheck', 'caffeine_smoke');

  if (pool.length === 1) {
    if (!pool[0].rested && ctx.has('woke_up')) return out('rest_recheck', 'woke_up');
    if (!pool[0].rested && ctx.has('exertion')) return out('rest_recheck', 'after_walk');
    return out('rest_recheck', 'high_recheck');
  }

  if (category === 'elevated') return out('monitor', 'elevated');
  if (category === 'stage1') return out('monitor', 'keep_monitoring');
  return out('call_doctor_today', 'still_high');
}

const BAC = /(?<![\p{L}])([Bb])ác(?![\p{L}])(?!\s+sĩ)/gu;

/** Câu cố định, xưng hô theo [hon] (mặc định "bác"). */
export function scriptText(key: ScriptKey, hon = 'bác'): string {
  const w = hon.trim().toLowerCase() || 'bác';
  const t: string = script[key];
  if (w === 'bác') return t;
  return t.replace(BAC, (_m, c: string) => (c === 'B' ? w[0].toUpperCase() + w.slice(1) : w));
}

export const SCRIPT_KEYS = Object.keys(script) as ScriptKey[];
