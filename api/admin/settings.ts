import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import { requireAdmin, requireFreshAdmin } from '../_lib/admin.js';
import { bodyObject } from '../_lib/http.js';
import { dbDelete, dbInsert, dbPatch, dbSelect } from '../_lib/db.js';
import { envKeys, fingerprint, invalidateKeyCache, plainKey, timedFetch, type Provider } from '../_lib/voice/keys.js';
import { getPolicy, invalidatePolicy } from '../_lib/voice/gate.js';
import { encryptKey, isEncrypted, validSecret } from '../_lib/secretbox.js';
import { audit } from '../_lib/audit.js';
import { invalidateLiveUsers } from '../_lib/voice/live_start.js';
import { PLAN_ACTIONS, handlePlanAction, plansOverview } from '../_lib/plans_admin.js';

const PROVIDERS: Provider[] = ['deepseek', 'elevenlabs', 'groq', 'gemini', 'openai'];
/** Nhà cung cấp bắt buộc mã hoá khoá khi lưu (khoá trả tiền theo mức dùng, lộ là mất tiền). */
const ENCRYPT_REQUIRED: Provider[] = ['openai'];

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
    } else if (p === 'openai') {
      r = await timedFetch('https://api.openai.com/v1/models', { headers: { Authorization: `Bearer ${key}` } }, 9000);
      if (r.ok) {
        const j = (await r.json().catch(() => ({}))) as { data?: { id?: string }[] };
        const ids = (j.data ?? []).map((m) => m.id ?? '');
        const live = ids.includes('gpt-live-1');
        // Hợp lệ nhưng chưa thấy quyền GPT-Live vẫn lưu được; chỉ cảnh báo để admin biết vì sao Live chưa chạy.
        return { ok: true, status: 'ok', note: live ? 'Hợp lệ, có quyền gpt-live-1' : 'Hợp lệ nhưng CHƯA thấy quyền gpt-live-1 (kiểm tra quyền của dự án)' };
      }
      if (r.status === 429) return { ok: false, status: 'exhausted', note: 'Hết hạn mức hoặc bị giới hạn tốc độ' };
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

function maskOf(provider: Provider, stored: string): string {
  const k = plainKey(provider, stored);
  return k ? `…${k.slice(-4)}` : '…????';
}

function int(v: unknown, lo: number, hi: number): number | null {
  const n = Number(v);
  return Number.isInteger(n) && n >= lo && n <= hi ? n : null;
}

type Named = { id: string; username: string | null; display_name: string | null };
const labelOf = (n: Named | undefined, id: string) => (n?.username ? `@${n.username}` : n?.display_name ?? id.slice(0, 8));

async function overview() {
  const rows = await dbSelect<KeyRow[]>('provider_keys?select=*&order=created_at.asc');
  const tiers = await dbSelect<{ user_id: string; tier: string; updated_at: string }[]>('voice_tiers?select=*&order=updated_at.desc&limit=100');
  const live = await dbSelect<{ user_id: string; added_at: string }[]>('live_users?select=user_id,added_at&order=added_at.desc&limit=100').catch(() => []);
  const ids = [...new Set([...tiers.map((t) => t.user_id), ...live.map((t) => t.user_id)])];
  const names = ids.length ? await dbSelect<Named[]>(`profiles?select=id,username,display_name&id=in.(${ids.join(',')})`) : [];
  const trail = await dbSelect<{ ts: string; actor: string; action: string; target: string | null; detail: Record<string, unknown> }[]>(
    'admin_audit?select=ts,actor,action,target,detail&order=ts.desc&limit=40',
  ).catch(() => []);
  const pass = process.env.ADMIN_PASS ?? '';
  return {
    canEdit: canEdit(),
    keys: rows.map((r) => ({
      id: r.id, provider: r.provider, label: r.label, masked: maskOf(r.provider, r.api_key), fp: r.fingerprint, enabled: r.enabled,
      status: r.status, error: r.last_error, cooldownUntil: r.cooldown_until, createdAt: r.created_at,
      encrypted: isEncrypted(r.api_key), unreadable: plainKey(r.provider, r.api_key) === null,
    })),
    envCounts: Object.fromEntries(PROVIDERS.map((p) => [p, envKeys(p).length])),
    policy: await getPolicy(),
    tiers: tiers.map((t) => ({ userId: t.user_id, tier: t.tier, label: labelOf(names.find((x) => x.id === t.user_id), t.user_id) })),
    liveUsers: live.map((t) => ({ userId: t.user_id, label: labelOf(names.find((x) => x.id === t.user_id), t.user_id), addedAt: t.added_at })),
    audit: trail,
    // Cảnh báo cấu hình bảo mật (không lộ giá trị).
    security: {
      encryption: validSecret(process.env.KEY_ENCRYPTION_SECRET),
      weakPass: pass.length < 12,
      sharedSessionSecret: !process.env.ADMIN_SESSION_SECRET,
    },
  };
}

const SENSITIVE = ['add_key', 'toggle_key', 'delete_key', 'set_policy', 'live_add_user', 'live_remove_user'];

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (!requireAdmin(req, res)) return;
  res.setHeader('Cache-Control', 'no-store');
  try {
    if (req.method === 'GET') {
      return res.status(200).json(await overview());
    }
    if (req.method !== 'POST') return res.status(405).end();
    const b = bodyObject(req) ?? {};
    const action = String(b.action ?? '');
    const mutatesKeys = ['add_key', 'toggle_key', 'delete_key', 'test_key'].includes(action);
    if (mutatesKeys && !canEdit()) {
      return res.status(403).json({ error: 'locked', message: 'Hãy đặt biến ADMIN_PASS (≥6 ký tự, khác 123) trên Vercel rồi redeploy để mở khoá quản lý key.' });
    }
    // Thao tác nhạy cảm cần đăng nhập mới (≤ 15 phút): token cũ bị lộ/để quên không đổi được khoá.
    if (SENSITIVE.includes(action) && !requireFreshAdmin(req, res)) return;

    if (action === 'add_key') {
      const provider = String(b.provider ?? '') as Provider;
      const key = String(b.api_key ?? '').trim();
      const label = String(b.label ?? '').trim().slice(0, 60);
      if (!PROVIDERS.includes(provider)) return res.status(400).json({ error: 'bad_provider' });
      if (key.length < 8 || key.length > 300 || /\s/.test(key)) return res.status(400).json({ error: 'bad_key' });
      const secret = process.env.KEY_ENCRYPTION_SECRET;
      if (ENCRYPT_REQUIRED.includes(provider) && !validSecret(secret)) {
        return res.status(422).json({ error: 'encryption_required', message: 'Cần đặt biến KEY_ENCRYPTION_SECRET (≥ 32 ký tự ngẫu nhiên) trên Vercel và redeploy trước khi lưu key OpenAI.' });
      }
      const fp = fingerprint(key);
      const dup = await dbSelect<{ id: string }[]>(`provider_keys?select=id&provider=eq.${provider}&fingerprint=eq.${fp}`);
      if (dup.length) return res.status(409).json({ error: 'duplicate' });
      const t = await testKey(provider, key);
      // Key hết hạn mức vẫn lưu được (sẽ tự dùng lại khi nạp thêm); key sai thì từ chối.
      if (!t.ok && t.status === 'invalid') {
        await audit(req, 'key_rejected', `${provider}:${fp}`, { note: t.note });
        return res.status(422).json({ error: 'key_rejected', note: t.note });
      }
      const stored = validSecret(secret) ? encryptKey(key, secret, provider) : key;
      try {
        await dbInsert('provider_keys', {
          provider, label, api_key: stored, fingerprint: fp, enabled: true, status: t.status, last_error: t.ok ? null : t.note,
        });
      } catch (e) {
        if ((e as Error).message === 'db_409') return res.status(409).json({ error: 'duplicate' });
        throw e;
      }
      invalidateKeyCache();
      await audit(req, 'key_add', `${provider}:${fp}`, { label, encrypted: stored !== key, status: t.status });
      return res.status(200).json({ ok: true, note: t.note, ...(await overview()) });
    }

    if (action === 'toggle_key' || action === 'delete_key' || action === 'test_key') {
      const id = String(b.id ?? '');
      if (!/^[0-9a-f-]{36}$/.test(id)) return res.status(400).json({ error: 'bad_id' });
      const rows = await dbSelect<KeyRow[]>(`provider_keys?select=*&id=eq.${id}`);
      const row = rows[0];
      if (!row) return res.status(404).json({ error: 'not_found' });
      const tgt = `${row.provider}:${row.fingerprint}`;
      if (action === 'delete_key') {
        await dbDelete('provider_keys', `id=eq.${id}`);
        await audit(req, 'key_delete', tgt);
      } else if (action === 'toggle_key') {
        await dbPatch('provider_keys', `id=eq.${id}`, { enabled: b.enabled === true });
        await audit(req, b.enabled === true ? 'key_enable' : 'key_disable', tgt);
      } else {
        const plain = plainKey(row.provider, row.api_key);
        if (!plain) {
          await dbPatch('provider_keys', `id=eq.${id}`, { status: 'invalid', last_error: 'Không giải mã được (thiếu hoặc đổi KEY_ENCRYPTION_SECRET)' });
        } else {
          const t = await testKey(row.provider, plain);
          await dbPatch('provider_keys', `id=eq.${id}`, { status: t.status, last_error: t.ok ? null : t.note, cooldown_until: null });
          await audit(req, 'key_test', tgt, { status: t.status });
        }
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
      for (const k of ['voice_enabled', 'eleven_enabled', 'live_enabled']) if (typeof p[k] === 'boolean') patch[k] = p[k];
      for (const [k, re] of [['deepseek_model', /^[a-z0-9._-]{2,40}$/i], ['eleven_voice_id', /^[A-Za-z0-9]{10,40}$/], ['eleven_model', /^[a-z0-9._-]{4,40}$/i]] as [string, RegExp][]) {
        if (p[k] === undefined) continue;
        if (typeof p[k] !== 'string' || !re.test(p[k] as string)) return res.status(400).json({ error: 'bad_value', field: k });
        patch[k] = p[k];
      }
      await dbPatch('voice_policy', 'id=eq.1', patch);
      invalidatePolicy();
      const { updated_at: _u, ...changed } = patch;
      await audit(req, 'policy_set', undefined, changed);
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
      await audit(req, 'tier_set', `@${username}`, { tier });
      return res.status(200).json({ ok: true, ...(await overview()) });
    }

    if (action === 'live_add_user' || action === 'live_remove_user') {
      const username = String(b.username ?? '').trim().replace(/^@/, '').toLowerCase();
      if (!/^[a-z0-9_.]{2,30}$/.test(username)) return res.status(400).json({ error: 'bad_username' });
      const found = await dbSelect<{ id: string }[]>(`profiles?select=id&username=eq.${encodeURIComponent(username)}`);
      if (!found[0]) return res.status(404).json({ error: 'user_not_found' });
      if (action === 'live_remove_user') await dbDelete('live_users', `user_id=eq.${found[0].id}`);
      else await dbInsert('live_users', { user_id: found[0].id }, 'resolution=merge-duplicates,return=minimal');
      invalidateLiveUsers();
      await audit(req, action, `@${username}`);
      return res.status(200).json({ ok: true, ...(await overview()) });
    }

    return res.status(400).json({ error: 'bad_action' });
  } catch (e) {
    const m = e instanceof Error ? e.message : 'error';
    return res.status(m === 'service_key_missing' ? 500 : 502).json({ error: m });
  }
}
