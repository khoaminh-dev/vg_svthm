import { createHash } from 'node:crypto';
import { dbPatch, dbSelect } from '../db.js';
import { AllKeysFailed, UpstreamError } from '../router.js';

// Kho key dùng chung cho các nhà cung cấp giọng nói: gộp key từ biến môi trường (Vercel) và key admin thêm
// trong DB, xoay vòng, tự nghỉ key lỗi (cooldown) và đánh dấu key sai/hết quota để admin thấy.

export type Provider = 'deepseek' | 'elevenlabs' | 'groq' | 'gemini';

export type KeyRef = { key: string; fp: string; id?: string };

const ENV_VARS: Record<Provider, string[]> = {
  deepseek: ['DEEPSEEK_API_KEY', 'DEEPSEEK_API_KEYS'],
  elevenlabs: ['ELEVENLABS_API_KEYS', 'ELEVENLABS_API_KEY', 'ELEVENLABS_KEYS'],
  groq: ['GROQ_KEYS'],
  gemini: ['GEMINI_KEYS'],
};

export function fingerprint(key: string): string {
  return createHash('sha256').update(key).digest('hex').slice(0, 8);
}

type DbKey = { id: string; api_key: string; cooldown_until: string | null };

const CACHE_MS = 20_000;
const cache = new Map<Provider, { at: number; keys: KeyRef[] }>();
const cooldown = new Map<string, number>(); // fp -> thời điểm hết nghỉ
const cursor = new Map<Provider, number>();

export function envKeys(p: Provider): KeyRef[] {
  const out: KeyRef[] = [];
  for (const name of ENV_VARS[p]) {
    for (const k of (process.env[name] ?? '').split(',')) {
      const key = k.trim();
      if (key) out.push({ key, fp: fingerprint(key) });
    }
  }
  return out;
}

export function invalidateKeyCache() {
  cache.clear();
}

/** Danh sách key đang dùng được của một nhà cung cấp (env + DB đã bật), bỏ trùng. */
export async function listKeys(p: Provider): Promise<KeyRef[]> {
  const hit = cache.get(p);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.keys;

  const keys = envKeys(p);
  try {
    const rows = await dbSelect<DbKey[]>(
      `provider_keys?select=id,api_key,cooldown_until&provider=eq.${p}&enabled=eq.true&status=eq.ok`,
    );
    for (const r of rows) {
      if (r.cooldown_until && Date.parse(r.cooldown_until) > Date.now()) continue;
      if (!keys.some((k) => k.key === r.api_key)) keys.push({ key: r.api_key, fp: fingerprint(r.api_key), id: r.id });
    }
  } catch {
    // DB không đọc được: vẫn dùng key từ biến môi trường.
  }
  cache.set(p, { at: Date.now(), keys });
  return keys;
}

async function markDb(k: KeyRef, patch: Record<string, unknown>) {
  if (!k.id) return;
  try {
    await dbPatch('provider_keys', `id=eq.${k.id}`, patch);
    invalidateKeyCache();
  } catch {
    // bỏ qua
  }
}

function isQuotaExceeded(body: string): boolean {
  return /quota_exceeded|insufficient_balance|credit/i.test(body);
}

/**
 * Chạy `call` với từng key lần lượt tới khi có key thành công.
 * Trả thêm số lần phải đổi key (để ghi vào thống kê "fallbacks").
 */
export async function withKeys<T>(
  p: Provider,
  call: (key: string) => Promise<T>,
): Promise<{ value: T; fp: string; failovers: number }> {
  const all = await listKeys(p);
  if (all.length === 0) throw new AllKeysFailed(`no_${p}_key`);
  const start = (cursor.get(p) ?? Math.floor(Math.random() * all.length)) % all.length;
  let failovers = 0;

  for (let i = 0; i < all.length; i++) {
    const k = all[(start + i) % all.length];
    if ((cooldown.get(k.fp) ?? 0) > Date.now()) continue;
    try {
      const value = await call(k.key);
      cursor.set(p, (start + i + 1) % all.length);
      return { value, fp: k.fp, failovers };
    } catch (e) {
      failovers++;
      if (!(e instanceof UpstreamError)) {
        // Lỗi mạng/timeout: nghỉ ngắn rồi thử key khác.
        cooldown.set(k.fp, Date.now() + 15_000);
        continue;
      }
      const body = e.message ?? '';
      if (e.status === 401 || e.status === 403 || e.status === 402) {
        if (isQuotaExceeded(body)) {
          cooldown.set(k.fp, Date.now() + 6 * 3600_000);
          await markDb(k, {
            status: 'exhausted',
            last_error: 'Hết hạn mức',
            cooldown_until: new Date(Date.now() + 6 * 3600_000).toISOString(),
          });
        } else {
          cooldown.set(k.fp, Date.now() + 3600_000);
          await markDb(k, { status: 'invalid', last_error: `HTTP ${e.status}` });
        }
      } else if (e.status === 429) {
        cooldown.set(k.fp, Date.now() + (e.retryAfterMs ?? 60_000));
      } else if (e.status >= 500) {
        cooldown.set(k.fp, Date.now() + 30_000);
      } else {
        throw e; // lỗi 4xx khác: lỗi của request, đổi key cũng vô ích
      }
    }
  }
  throw new AllKeysFailed(`all_${p}_keys_failed`);
}

/** fetch có giới hạn thời gian; quá hạn sẽ ném lỗi (router sẽ chuyển key/nhà cung cấp khác). */
export async function timedFetch(url: string, init: RequestInit, ms: number): Promise<Response> {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: ctl.signal });
  } finally {
    clearTimeout(t);
  }
}
