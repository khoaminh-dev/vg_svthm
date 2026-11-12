import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import { checkLogin, issueToken } from '../_lib/admin.js';
import { allow } from '../_lib/auth.js';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'method_not_allowed' });
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY && !process.env.ADMIN_SESSION_SECRET) {
    return res.status(500).json({ error: 'server_not_configured' });
  }
  const ip = String(req.headers['x-forwarded-for'] ?? 'x').split(',')[0].trim();
  // Tối đa 10 lần thử / 5 phút mỗi IP (đếm dùng chung giữa các instance).
  if (!(await allow(`admin_login:${ip}`, 10, 300))) return res.status(429).json({ error: 'too_many_attempts' });

  const { username, password } = (req.body ?? {}) as { username?: string; password?: string };
  if (typeof username !== 'string' || typeof password !== 'string' || !checkLogin(username, password)) {
    return res.status(401).json({ error: 'invalid_credentials' });
  }
  return res.status(200).json({ token: issueToken() });
}
