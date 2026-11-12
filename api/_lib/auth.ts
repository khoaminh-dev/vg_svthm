import type { VercelRequest, VercelResponse } from '@vercel/node';

/** Xác thực bằng token Supabase của người dùng. Trả về user id hoặc null (đã trả 401). */
export async function requireUser(req: VercelRequest, res: VercelResponse): Promise<string | null> {
  const auth = req.headers.authorization;
  if (!auth?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'missing_token' });
    return null;
  }
  const r = await fetch(`${process.env.SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: process.env.SUPABASE_ANON_KEY ?? '' },
  });
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
