import { createHash } from 'node:crypto';
import { dbInsert, dbRpc, dbSelect, storageGet, storagePut } from '../db.js';
import { elevenTts } from './providers.js';
import { emergencyTexts, staticTexts, type SayClass } from './dm.js';

// Cổng quyết định dùng giọng ElevenLabs hay giọng máy: phrase/cache miễn phí → khẩn cấp → hạn mức từng người
// → ngân sách chung → ElevenLabs. Mọi lý do từ chối trả về để app đọc bằng giọng máy.

export type Policy = {
  voice_enabled: boolean;
  eleven_enabled: boolean;
  eleven_calls_per_day: number;
  eleven_chars_per_day: number;
  eleven_calls_per_min: number;
  eleven_max_chars: number;
  eleven_global_chars_per_day: number;
  vip_multiplier: number;
  deepseek_model: string;
  eleven_voice_id: string;
  eleven_model: string;
  turns_per_min: number;
  turns_per_day: number;
};

const DEFAULT_POLICY: Policy = {
  voice_enabled: true, eleven_enabled: true, eleven_calls_per_day: 3, eleven_chars_per_day: 240,
  eleven_calls_per_min: 2, eleven_max_chars: 80, eleven_global_chars_per_day: 8000, vip_multiplier: 3,
  deepseek_model: 'deepseek-flash', eleven_voice_id: 'EXAVITQu4vr4xnSDxMaL', eleven_model: 'eleven_flash_v2_5',
  turns_per_min: 10, turns_per_day: 150,
};

let policyCache: { at: number; p: Policy } | null = null;
export function invalidatePolicy() { policyCache = null; }

export async function getPolicy(): Promise<Policy> {
  if (policyCache && Date.now() - policyCache.at < 15_000) return policyCache.p;
  try {
    const rows = await dbSelect<Policy[]>('voice_policy?select=*&id=eq.1');
    const p = { ...DEFAULT_POLICY, ...(rows[0] ?? {}) };
    policyCache = { at: Date.now(), p };
    return p;
  } catch {
    return policyCache?.p ?? DEFAULT_POLICY;
  }
}

async function getTier(userId: string): Promise<'normal' | 'vip' | 'off'> {
  try {
    const rows = await dbSelect<{ tier: 'normal' | 'vip' | 'off' }[]>(`voice_tiers?select=tier&user_id=eq.${userId}`);
    return rows[0]?.tier ?? 'normal';
  } catch {
    return 'normal';
  }
}

export type TtsResult =
  | { mode: 'eleven' | 'cache'; audio: Buffer; reason: 'ok' }
  | { mode: 'device'; reason: string };

const MAX_INFLIGHT = 6; // chống dồn quá nhiều lệnh ElevenLabs cùng lúc trong một instance
let inflight = 0;
const BUCKET = 'tts-cache';

function cachePath(text: string, voice: string, model: string): string {
  const h = createHash('sha256').update(`${voice}|${model}|${text}`).digest('hex').slice(0, 40);
  return `${h}.mp3`;
}

async function log(userId: string, mode: string, reason: string, chars: number, keyFp?: string, ms?: number) {
  try {
    await dbInsert('voice_tts_log', { user_id: userId, mode, reason, chars, key_fp: keyFp ?? null, ms: ms ?? null });
  } catch {
    // bỏ qua
  }
}

export function classify(text: string): SayClass {
  if (emergencyTexts().has(text)) return 'emergency';
  if (staticTexts().has(text)) return 'static';
  return 'other';
}

/** `cls` do server xác định (không tin app). Câu động dài quá ngưỡng sẽ đọc bằng giọng máy. */
export async function speak(userId: string, text: string, cls: SayClass): Promise<TtsResult> {
  const pol = await getPolicy();
  const t = text.trim();
  if (!pol.voice_enabled || !pol.eleven_enabled) return { mode: 'device', reason: 'disabled' };
  if (!t) return { mode: 'device', reason: 'empty' };
  const tier = await getTier(userId);
  if (tier === 'off') return { mode: 'device', reason: 'tier_off' };

  const path = cachePath(t, pol.eleven_voice_id, pol.eleven_model);
  const isStatic = cls === 'static' || cls === 'emergency';

  // 1) Cache dùng chung (miễn phí hạn mức) — chỉ lưu câu cố định.
  if (isStatic) {
    try {
      const hit = await storageGet(BUCKET, path);
      if (hit) {
        void log(userId, 'cache', 'ok', t.length);
        return { mode: 'cache', audio: hit, reason: 'ok' };
      }
    } catch {
      // cache hỏng không ảnh hưởng luồng chính
    }
  }

  // 2) Câu động: chỉ đọc bằng ElevenLabs nếu quan trọng (xác nhận/khẩn cấp) và đủ ngắn.
  if (!isStatic && cls !== 'important') return { mode: 'device', reason: 'class' };
  if (cls !== 'emergency' && t.length > pol.eleven_max_chars && !isStatic) {
    void log(userId, 'device', 'too_long', t.length);
    return { mode: 'device', reason: 'too_long' };
  }

  // 3) Hạn mức theo người + ngân sách chung (khẩn cấp được bỏ qua hạn mức cá nhân).
  const mult = tier === 'vip' ? pol.vip_multiplier : 1;
  let verdict = 'ok';
  try {
    verdict = await dbRpc<string>('consume_tts', {
      p_user: userId,
      p_chars: t.length,
      p_calls_day: pol.eleven_calls_per_day * mult,
      p_chars_day: pol.eleven_chars_per_day * mult,
      p_calls_min: pol.eleven_calls_per_min,
      p_global_chars_day: pol.eleven_global_chars_per_day,
      p_bypass_user: cls === 'emergency',
    });
  } catch {
    verdict = 'error';
  }
  if (verdict !== 'ok') {
    void log(userId, 'device', verdict, t.length);
    return { mode: 'device', reason: verdict };
  }
  if (inflight >= MAX_INFLIGHT) {
    void log(userId, 'device', 'busy', t.length);
    return { mode: 'device', reason: 'busy' };
  }

  inflight++;
  const t0 = Date.now();
  try {
    const r = await elevenTts(t, pol.eleven_voice_id, pol.eleven_model);
    void log(userId, 'eleven', 'ok', t.length, r.fp, Date.now() - t0);
    if (isStatic) {
      try { await storagePut(BUCKET, path, r.audio, 'audio/mpeg'); } catch { /* bỏ qua */ }
    }
    return { mode: 'eleven', audio: r.audio, reason: 'ok' };
  } catch (e) {
    void log(userId, 'device', 'error', t.length);
    return { mode: 'device', reason: (e as Error).message?.startsWith('no_') ? 'no_key' : 'error' };
  } finally {
    inflight--;
  }
}
