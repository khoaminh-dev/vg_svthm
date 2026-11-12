import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import { requireAdmin, rpc } from '../_lib/admin.js';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (!requireAdmin(req, res)) return;
  const days = Math.min(Math.max(Number(req.query.days) || 7, 1), 90);
  try {
    const stats = await rpc<unknown>('admin_voice_stats', { p_days: days });
    res.setHeader('Cache-Control', 'private, max-age=15');
    res.status(200).json(stats);
  } catch (e) {
    const m = e instanceof Error ? e.message : 'error';
    res.status(m === 'service_key_missing' ? 500 : 502).json({ error: m });
  }
}
