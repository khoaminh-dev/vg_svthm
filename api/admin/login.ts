import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import { checkLogin, issueToken } from '../_lib/admin.js';
import { allow } from '../_lib/auth.js';
import { audit } from '../_lib/audit.js';

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'method_not_allowed' });
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY && !process.env.ADMIN_SESSION_SECRET) {
    return res.status(500).json({ error: 'server_not_configured' });
  }
  const ip = String(req.headers['x-forwarded-for'] ?? 'x').split(',')[0].trim();
  // Tối đa 10 lần thử / 5 phút mỗi IP, và 40 lần / 15 phút trên toàn hệ thống (chặn dò mật khẩu bằng nhiều IP).
  if (!(await allow(`admin_login:${ip}`, 10, 300)) || !(await allow('admin_login:all', 40, 900))) {
    return res.status(429).json({ error: 'too_many_attempts' });
  }

  const { username, password } = (req.body ?? {}) as { username?: string; password?: string };
  if (typeof username !== 'string' || typeof password !== 'string' || username.length > 100 || password.length > 200 || !checkLogin(username, password)) {
    await sleep(500); // làm chậm mỗi lần đoán sai
    await audit(req, 'login_fail');
    return res.status(401).json({ error: 'invalid_credentials' });
  }
  await audit(req, 'login_ok');
  return res.status(200).json({ token: issueToken() });
}
