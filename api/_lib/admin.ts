import { createHmac, timingSafeEqual } from 'node:crypto';
import type { VercelRequest, VercelResponse } from './vercel-types.js';

const TTL_MS = 12 * 60 * 60 * 1000;

function secret(): string {
  // Khoá ký phiên: ưu tiên biến riêng, mặc định dùng service key (đã bí mật sẵn).
  return process.env.ADMIN_SESSION_SECRET ?? process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
}

function sign(payload: string): string {
  return createHmac('sha256', secret()).update(payload).digest('base64url');
}

function same(a: string, b: string): boolean {
  const x = new Uint8Array(Buffer.from(a));
  const y = new Uint8Array(Buffer.from(b));
  return x.length === y.length && timingSafeEqual(x, y);
}

export function checkLogin(user: string, pass: string): boolean {
  const u = process.env.ADMIN_USER ?? 'admin';
  const p = process.env.ADMIN_PASS ?? '123';
  // Không short-circuit để so sánh cả hai trường.
  const okU = same(user, u);
  const okP = same(pass, p);
  return okU && okP;
}

export function issueToken(): string {
  const payload = String(Date.now() + TTL_MS);
  return `${payload}.${sign(payload)}`;
}

/** Trả true nếu request có token admin hợp lệ; ngược lại đã trả 401. */
export function requireAdmin(req: VercelRequest, res: VercelResponse): boolean {
  const h = req.headers.authorization ?? '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : '';
  const [payload, sig] = token.split('.');
  if (secret() && payload && sig && same(sig, sign(payload)) && Number(payload) > Date.now()) {
    return true;
  }
  res.status(401).json({ error: 'unauthorized' });
  return false;
}

/** Gọi PostgREST của Supabase bằng service role (chỉ chạy trên server). */
export async function dbGet<T>(path: string): Promise<T> {
  const base = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!base || !key) throw new Error('service_key_missing');
  // Key mới `sb_secret_...` không phải JWT: chỉ gửi qua `apikey`. Key legacy (JWT) gửi cả Bearer.
  const headers: Record<string, string> = { apikey: key };
  if (!key.startsWith('sb_')) headers.Authorization = `Bearer ${key}`;
  const r = await fetch(`${base}/rest/v1/${path}`, { headers });
  if (!r.ok) throw new Error(`db_${r.status}`);
  return (await r.json()) as T;
}
