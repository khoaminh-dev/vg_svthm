import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import { requireAdmin } from '../_lib/admin.js';
import { bodyObject } from '../_lib/http.js';
import { dbDelete, dbInsert, dbPatch, dbSelect } from '../_lib/db.js';
import { envKeys, fingerprint, invalidateKeyCache, timedFetch, type Provider } from '../_lib/voice/keys.js';
import { getPolicy, invalidatePolicy } from '../_lib/voice/gate.js';

const PROVIDERS: Provider[] = ['deepseek', 'elevenlabs', 'groq', 'gemini'];

// Quản lý key bị khoá khi mật khẩu admin còn là mặc định (123): key là bí mật, không để lộ cho ai đoán được pass.
function canEdit(): boolean {
  const p = process.env.ADMIN_PASS;
  return !!p && p !== '123' && p.length >= 6;
}

type Test = { ok: boolean; status: 'ok' | 'invalid' | 'exhausted'; note: string };

/** Gọi thử một API rẻ/miễn phí của nhà cung cấp để biết key dùng được không (không tốn hạn mức). */
export async function testKey(p: Provider, key: string): Promise<Test> {
  try {
    let r: Response;
    if (p === 'elevenlabs') {
      r = await timedFetch('https://api.elevenlabs.io/v1/user/subscription', { headers: { 'xi-api-key': key } }, 7000);
      if (r.ok) {
        const j = (await r.json()) as { character_count?: number; character_limit?: number };
        const left = (j.character_limit ?? 0) - (j.character_count ?? 0);
        if (j.character_limit && left <= 0) return { ok: false, status: 'exhausted', note: 'Hết hạn mức ký tự' };
        return { ok: true, status: 'ok', note: j.character_limit ? `Còn ${left} ký tự` : 'Hợp lệ' };
      }
    } else if (p === 'deepseek') {
      r = await timedFetch('https://api.deepseek.com/user/balance', { headers: { Authorization: `Bearer ${key}` } }, 7000);
      if (r.ok) {
        const j = (await r.json()) as { is_available?: boolean; balance_infos?: { total_balance: string; currency: string }[] };
        if (j.is_available === false) return { ok: false, status: 'exhausted', note: 'Hết số dư' };
        const b = j.balance_infos?.[0];
        return { ok: true, status: 'ok', note: b ? `Số dư ${b.total_balance} ${b.currency}` : 'Hợp lệ' };
      }
    } else if (p === 'groq') {
      r = await timedFetch('https://api.groq.com/openai/v1/models', { headers: { Authorization: `Bearer ${key}`, 'User-Agent': 'viegrand/1.0' } }, 7000);
      if (r.ok) return { ok: true, status: 'ok', note: 'Hợp lệ' };
    } else {
      r = await timedFetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${key}`, {}, 7000);
      if (r.ok) return { ok: true, status: 'ok', note: 'Hợp lệ' };
    }
    if (r.status === 401 || r.status === 403) return { ok: false, status: 'invalid', note: 'Key sai hoặc bị thu hồi' };
    if (r.status === 402) return { ok: false, status: 'exhausted', note: 'Hết hạn mức/số dư' };
    return { ok: false, status: 'invalid', note: `Nhà cung cấp trả HTTP ${r.status}` };
  } catch {
    return { ok: false, status: 'invalid', note: 'Không kết nối được tới nhà cung cấp' };
  }
}

type KeyRow = { id: string; provider: Provider; label: string; api_key: string; fingerprint: string; enabled: boolean; status: string; last_error: string | null; cooldown_until: string | null; created_at: string };

function mask(k: string): string {
  return `…${k.slice(-4)}`;
}

function int(v: unknown, lo: number, hi: number): number | null {
  const n = Number(v);
  return Number.isInteger(n) && n >= lo && n <= hi ? n : null;
}

async function overview() {
  const rows = await dbSelect<KeyRow[]>('provider_keys?select=*&order=created_at.asc');
  const tiers = await dbSelect<{ user_id: string; tier: string; updated_at: string }[]>('voice_tiers?select=*&order=updated_at.desc&limit=100');
  const names = tiers.length
    ? await dbSelect<{ id: string; username: string | null; display_name: string | null }[]>(
        `profiles?select=id,username,display_name&id=in.(${tiers.map((t) => t.user_id).join(',')})`,
      )
    : [];
  return {
    canEdit: canEdit(),
    keys: rows.map((r) => ({
      id: r.id, provider: r.provider, label: r.label, masked: mask(r.api_key), fp: r.fingerprint, enabled: r.enabled,
      status: r.status, error: r.last_error, cooldownUntil: r.cooldown_until, createdAt: r.created_at,
    })),
    envCounts: Object.fromEntries(PROVIDERS.map((p) => [p, envKeys(p).length])),
    policy: await getPolicy(),
    tiers: tiers.map((t) => {
      const n = names.find((x) => x.id === t.user_id);
      return { userId: t.user_id, tier: t.tier, label: n?.username ? `@${n.username}` : n?.display_name ?? t.user_id.slice(0, 8) };
    }),
  };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (!requireAdmin(req, res)) return;
  try {
    if (req.method === 'GET') {
      res.setHeader('Cache-Control', 'no-store');
      return res.status(200).json(await overview());
    }
    if (req.method !== 'POST') return res.status(405).end();
    const b = bodyObject(req) ?? {};
    const action = String(b.action ?? '');
    const mutatesKeys = ['add_key', 'toggle_key', 'delete_key', 'test_key'].includes(action);
    if (mutatesKeys && !canEdit()) {
      return res.status(403).json({ error: 'locked', message: 'Hãy đặt biến ADMIN_PASS (≥6 ký tự, khác 123) trên Vercel rồi redeploy để mở khoá quản lý key.' });
    }

    if (action === 'add_key') {
      const provider = String(b.provider ?? '') as Provider;
      const key = String(b.api_key ?? '').trim();
      const label = String(b.label ?? '').trim().slice(0, 60);
      if (!PROVIDERS.includes(provider)) return res.status(400).json({ error: 'bad_provider' });
      if (key.length < 8 || key.length > 300 || /\s/.test(key)) return res.status(400).json({ error: 'bad_key' });
      const t = await testKey(provider, key);
      // Key hết hạn mức vẫn lưu được (sẽ tự dùng lại khi nạp thêm); key sai thì từ chối.
      if (!t.ok && t.status === 'invalid') return res.status(422).json({ error: 'key_rejected', note: t.note });
      try {
        await dbInsert('provider_keys', {
          provider, label, api_key: key, fingerprint: fingerprint(key), enabled: true, status: t.status, last_error: t.ok ? null : t.note,
        });
      } catch (e) {
        if ((e as Error).message === 'db_409') return res.status(409).json({ error: 'duplicate' });
        throw e;
      }
      invalidateKeyCache();
      return res.status(200).json({ ok: true, note: t.note, ...(await overview()) });
    }

    if (action === 'toggle_key' || action === 'delete_key' || action === 'test_key') {
      const id = String(b.id ?? '');
      if (!/^[0-9a-f-]{36}$/.test(id)) return res.status(400).json({ error: 'bad_id' });
      if (action === 'delete_key') await dbDelete('provider_keys', `id=eq.${id}`);
      else if (action === 'toggle_key') await dbPatch('provider_keys', `id=eq.${id}`, { enabled: b.enabled === true });
      else {
        const rows = await dbSelect<KeyRow[]>(`provider_keys?select=*&id=eq.${id}`);
        if (!rows[0]) return res.status(404).json({ error: 'not_found' });
        const t = await testKey(rows[0].provider, rows[0].api_key);
        await dbPatch('provider_keys', `id=eq.${id}`, { status: t.status, last_error: t.ok ? null : t.note, cooldown_until: null });
      }
      invalidateKeyCache();
      return res.status(200).json({ ok: true, ...(await overview()) });
    }

    if (action === 'set_policy') {
      const p = (b.policy ?? {}) as Record<string, unknown>;
      const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
      const nums: [string, number, number][] = [
        ['eleven_calls_per_day', 0, 500], ['eleven_chars_per_day', 0, 20000], ['eleven_calls_per_min', 1, 60],
        ['eleven_max_chars', 10, 300], ['eleven_global_chars_per_day', 0, 5_000_000], ['vip_multiplier', 1, 50],
        ['turns_per_min', 1, 60], ['turns_per_day', 1, 5000],
      ];
      for (const [k, lo, hi] of nums) {
        if (p[k] === undefined) continue;
        const v = int(p[k], lo, hi);
        if (v === null) return res.status(400).json({ error: 'bad_value', field: k });
        patch[k] = v;
      }
      for (const k of ['voice_enabled', 'eleven_enabled']) if (typeof p[k] === 'boolean') patch[k] = p[k];
      for (const [k, re] of [['deepseek_model', /^[a-z0-9._-]{2,40}$/i], ['eleven_voice_id', /^[A-Za-z0-9]{10,40}$/], ['eleven_model', /^[a-z0-9._-]{4,40}$/i]] as [string, RegExp][]) {
        if (p[k] === undefined) continue;
        if (typeof p[k] !== 'string' || !re.test(p[k] as string)) return res.status(400).json({ error: 'bad_value', field: k });
        patch[k] = p[k];
      }
      await dbPatch('voice_policy', 'id=eq.1', patch);
      invalidatePolicy();
      return res.status(200).json({ ok: true, ...(await overview()) });
    }

    if (action === 'set_tier') {
      const username = String(b.username ?? '').trim().replace(/^@/, '').toLowerCase();
      const tier = String(b.tier ?? '');
      if (!/^[a-z0-9_.]{2,30}$/.test(username)) return res.status(400).json({ error: 'bad_username' });
      if (!['normal', 'vip', 'off'].includes(tier)) return res.status(400).json({ error: 'bad_tier' });
      const found = await dbSelect<{ id: string }[]>(`profiles?select=id&username=eq.${encodeURIComponent(username)}`);
      if (!found[0]) return res.status(404).json({ error: 'user_not_found' });
      if (tier === 'normal') await dbDelete('voice_tiers', `user_id=eq.${found[0].id}`);
      else await dbInsert('voice_tiers', { user_id: found[0].id, tier, updated_at: new Date().toISOString() }, 'resolution=merge-duplicates,return=minimal');
      return res.status(200).json({ ok: true, ...(await overview()) });
    }

    return res.status(400).json({ error: 'bad_action' });
  } catch (e) {
    const m = e instanceof Error ? e.message : 'error';
    return res.status(m === 'service_key_missing' ? 500 : 502).json({ error: m });
  }
}
