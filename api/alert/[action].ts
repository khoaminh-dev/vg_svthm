import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import trigger from '../_lib/alert_trigger.js';
import status from '../_lib/alert_status.js';

// Một hàm duy nhất cho /api/alert/trigger và /api/alert/status (gói Vercel Hobby tối đa 12 hàm mỗi lần deploy).
// Địa chỉ gọi không đổi: POST /api/alert/trigger, GET /api/alert/status. Xem docs/API_CANH_BAO_DEMO.md.
const ROUTES: Record<string, (req: VercelRequest, res: VercelResponse) => Promise<void>> = { trigger, status };

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const a = req.query.action;
  const name = String(Array.isArray(a) ? a[0] : a ?? '');
  const h = Object.hasOwn(ROUTES, name) ? ROUTES[name] : undefined;
  if (!h) return void res.status(404).json({ error: 'not_found' });
  return h(req, res);
}
