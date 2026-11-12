import type { VercelRequest, VercelResponse } from './vercel-types.js';
import { AllKeysFailed, UpstreamError } from './router.js';

export function sendError(res: VercelResponse, e: unknown) {
  if (e instanceof AllKeysFailed) return res.status(503).json({ error: 'all_keys_failed' });
  if (e instanceof UpstreamError) return res.status(502).json({ error: 'upstream', status: e.status });
  console.error(e);
  return res.status(500).json({ error: 'internal' });
}

/** Body JSON dạng object, hoặc null nếu thiếu/sai định dạng (để trả 400 thay vì 500). */
export function bodyObject(req: VercelRequest): Record<string, unknown> | null {
  let b: unknown = req.body;
  if (typeof b === 'string') {
    try { b = JSON.parse(b); } catch { return null; }
  }
  return b && typeof b === 'object' && !Array.isArray(b) ? (b as Record<string, unknown>) : null;
}
