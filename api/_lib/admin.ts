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

/** Số ms kể từ lúc phiên admin được cấp (token chứa giờ hết hạn = giờ cấp + TTL). Hết hạn hoặc sai chữ ký → Infinity. */
export function tokenAgeMs(req: Pick<VercelRequest, 'headers'>, now = Date.now()): number {
  const h = req.headers.authorization ?? '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : '';
  const [payload, sig] = token.split('.');
  if (!secret() || !payload || !sig || !same(sig, sign(payload))) return Infinity;
  const exp = Number(payload);
  if (!(exp > now)) return Infinity;
  return Math.max(0, now - (exp - TTL_MS));
}

/**
 * Thao tác nhạy cảm (thêm/xoá/bật tắt khoá, đổi ngưỡng): chỉ chấp nhận khi đăng nhập trong `maxAgeMs` gần đây,
 * để token bị lộ/để quên trên máy khác không đổi được khoá. Quá hạn thì trả 401 `reauth_required`.
 */
export function requireFreshAdmin(req: VercelRequest, res: VercelResponse, maxAgeMs = 15 * 60_000): boolean {
  if (tokenAgeMs(req) <= maxAgeMs) return true;
  res.status(401).json({ error: 'reauth_required' });
  return false;
}

/** IP người gọi (Vercel đặt `x-forwarded-for`). */
export function clientIp(req: Pick<VercelRequest, 'headers'>): string {
  return String(req.headers['x-forwarded-for'] ?? 'x').split(',')[0].trim().slice(0, 64);
}

/** Băm một chiều IP (kèm bí mật) để nhật ký phân biệt được nguồn mà không lưu IP thật. */
export function ipHash(ip: string): string {
  return createHmac('sha256', secret() || 'x').update(`ip:${ip}`).digest('hex').slice(0, 16);
}

/** Gọi hàm Postgres (RPC) bằng service role (chỉ chạy trên server). */
export async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const base = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!base || !key) throw new Error('service_key_missing');
  const headers: Record<string, string> = { apikey: key, 'Content-Type': 'application/json' };
  if (!key.startsWith('sb_')) headers.Authorization = `Bearer ${key}`;
  const r = await fetch(`${base}/rest/v1/rpc/${fn}`, { method: 'POST', headers, body: JSON.stringify(args) });
  if (!r.ok) throw new Error(`db_${r.status}`);
  return (await r.json()) as T;
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
