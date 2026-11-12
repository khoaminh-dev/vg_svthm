import type { VercelRequest, VercelResponse } from '@vercel/node';
import { checkLogin, issueToken } from '../_lib/admin.js';

// Chống dò mật khẩu: tối đa 10 lần sai / 5 phút mỗi IP (trong bộ nhớ).
const fails = new Map<string, number[]>();

export default function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'method_not_allowed' });
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY && !process.env.ADMIN_SESSION_SECRET) {
    return res.status(500).json({ error: 'server_not_configured' });
  }
  const ip = String(req.headers['x-forwarded-for'] ?? 'x').split(',')[0].trim();
  const now = Date.now();
  const recent = (fails.get(ip) ?? []).filter((t) => now - t < 300_000);
  if (recent.length >= 10) return res.status(429).json({ error: 'too_many_attempts' });

  const { username, password } = (req.body ?? {}) as { username?: string; password?: string };
  if (typeof username !== 'string' || typeof password !== 'string' || !checkLogin(username, password)) {
    recent.push(now);
    fails.set(ip, recent);
    return res.status(401).json({ error: 'invalid_credentials' });
  }
  return res.status(200).json({ token: issueToken() });
}
