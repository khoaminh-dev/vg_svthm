import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import { requireAdmin, rpc } from '../_lib/admin.js';

// Toàn bộ số liệu được gom nhóm ngay trong Postgres (hàm admin_stats / admin_voice_stats), nên chi phí
// không tăng theo số dòng sự kiện: server chỉ nhận về một JSON nhỏ.
// `?kind=voice` trả số liệu trợ lý giọng nói (gộp chung một hàm để không vượt giới hạn 12 hàm của gói Hobby).
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (!requireAdmin(req, res)) return;
  const voice = req.query.kind === 'voice';
  const days = Math.min(Math.max(Number(req.query.days) || (voice ? 7 : 14), 1), 90);
  try {
    const stats = await rpc<unknown>(voice ? 'admin_voice_stats' : 'admin_stats', { p_days: days });
    res.setHeader('Cache-Control', 'private, max-age=15');
    res.status(200).json(stats);
  } catch (e) {
    const m = e instanceof Error ? e.message : 'error';
    res.status(m === 'service_key_missing' ? 500 : 502).json({ error: m });
  }
}
