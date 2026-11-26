import type { VercelRequest, VercelResponse } from './vercel-types.js';
import { dbRpc } from './db.js';
import { eventIdOf, keyFrom, keyOk } from './alert.js';

// GET /api/alert/status?event_id=... — module cảnh báo hỏi "người nhận đã bấm nhận chưa" để tắt chuông.
// Cùng khoá với /api/alert/trigger. Xem docs/API_CANH_BAO_DEMO.md.

type Status = { ok?: boolean; error?: string };

export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'GET') return void res.status(405).json({ error: 'method' });

  const env = process.env.ALERT_API_KEY;
  if (!env || !env.split(',').some((k) => k.trim().length >= 24)) return void res.status(503).json({ error: 'alert_disabled' });
  if (!keyOk(keyFrom(req.headers), env)) return void res.status(401).json({ error: 'unauthorized' });

  const eventId = eventIdOf(req.query.event_id);
  if (!eventId) return void res.status(400).json({ error: 'bad_event_id' });

  try {
    const r = await dbRpc<Status>('demo_alert_status', { p_event_id: eventId });
    if (r.error === 'not_found') return void res.status(404).json(r);
    return void res.status(200).json(r);
  } catch (e) {
    console.error('alert_status', e instanceof Error ? e.message : e);
    return void res.status(502).json({ error: 'upstream' });
  }
}
