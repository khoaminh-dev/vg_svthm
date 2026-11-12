import type { VercelRequest, VercelResponse } from './vercel-types.js';

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

// Giới hạn đơn giản theo user (trong bộ nhớ): tối đa `limit` request mỗi phút.
const hits = new Map<string, number[]>();
export function rateLimit(userId: string, limit = 30): boolean {
  const now = Date.now();
  const arr = (hits.get(userId) ?? []).filter((t) => now - t < 60_000);
  if (arr.length >= limit) return false;
  arr.push(now);
  hits.set(userId, arr);
  return true;
}
