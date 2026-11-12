import type { VercelResponse } from '@vercel/node';
import { AllKeysFailed, UpstreamError } from './router.js';

export function sendError(res: VercelResponse, e: unknown) {
  if (e instanceof AllKeysFailed) return res.status(503).json({ error: 'all_keys_failed' });
  if (e instanceof UpstreamError) return res.status(502).json({ error: 'upstream', status: e.status });
  console.error(e);
  return res.status(500).json({ error: 'internal' });
}
