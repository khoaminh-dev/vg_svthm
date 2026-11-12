import type { VercelRequest, VercelResponse } from './vercel-types.js';
import { rpc } from './admin.js';

/** Xác thực bằng token Supabase của người dùng. Trả về user id hoặc null (đã trả 401). */
export async function requireUser(req: VercelRequest, res: VercelResponse): Promise<string | null> {
  const auth = req.headers.authorization;
  if (!auth?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'missing_token' });
    return null;
  }
  const base = process.env.SUPABASE_URL;
  if (!base || !process.env.SUPABASE_ANON_KEY) {
    res.status(500).json({ error: 'server_not_configured' });
    return null;
  }
  let r: Response;
  try {
    r = await fetch(`${base}/auth/v1/user`, {
      headers: { Authorization: auth, apikey: process.env.SUPABASE_ANON_KEY ?? '' },
    });
  } catch {
    res.status(502).json({ error: 'auth_unreachable' });
    return null;
  }
  if (!r.ok) {
    res.status(401).json({ error: 'invalid_token' });
    return null;
  }
  const user = (await r.json()) as { id: string };
  return user.id;
}

// Giới hạn tần suất dùng chung giữa mọi instance Vercel (đếm trong Postgres, nguyên tử).
// Nếu DB/khoá service không dùng được thì rơi về đếm trong bộ nhớ từng instance (vẫn chặn được phần nào).
const hits = new Map<string, number[]>();
function localLimit(key: string, limit: number, windowSec: number): boolean {
  const now = Date.now();
  const arr = (hits.get(key) ?? []).filter((t) => now - t < windowSec * 1000);
  if (arr.length >= limit) return false;
  arr.push(now);
  hits.set(key, arr);
  return true;
}

/** true nếu còn trong hạn mức `limit` lần mỗi `windowSec` giây cho `key`. */
export async function allow(key: string, limit: number, windowSec: number): Promise<boolean> {
  try {
    return await rpc<boolean>('consume_rate', { p_key: key, p_limit: limit, p_window_sec: windowSec });
  } catch {
    return localLimit(key, limit, windowSec);
  }
}

/** Chặn cả theo phút (chống dồn request) lẫn theo ngày (bảo vệ quota Groq/ElevenLabs). */
export async function rateLimit(userId: string, bucket: string, perMinute: number, perDay: number): Promise<boolean> {
  return (await allow(`${bucket}:m:${userId}`, perMinute, 60)) && (await allow(`${bucket}:d:${userId}`, perDay, 86_400));
}
