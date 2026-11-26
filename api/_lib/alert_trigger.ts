import type { VercelRequest, VercelResponse } from './vercel-types.js';
import { dbRpc } from './db.js';
import { bodyOf, keyFrom, keyOk, parseAlert } from './alert.js';

// POST /api/alert/trigger — module cảnh báo (camera...) gọi vào đây để phát cảnh báo khẩn cấp DEMO
// tới các tài khoản đã được chỉ định trong bảng `demo_alert_targets`. Xem docs/API_CANH_BAO_DEMO.md.
// Khoá: header `x-alert-key` (hoặc `Authorization: Bearer`), khớp biến môi trường ALERT_API_KEY.

type Fired = { ok?: boolean; error?: string; duplicate?: boolean; dry?: boolean; id?: string; recipients?: number; labels?: string[]; retry_after?: number };

export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') return void res.status(405).json({ error: 'method' });

  const env = process.env.ALERT_API_KEY;
  if (!env || !env.split(',').some((k) => k.trim().length >= 24)) {
    return void res.status(503).json({ error: 'alert_disabled' }); // chưa cấu hình khoá thì tính năng tắt hẳn
  }
  if (!keyOk(keyFrom(req.headers), env)) return void res.status(401).json({ error: 'unauthorized' });

  const p = parseAlert(bodyOf(req.body));
  if (!p.ok) return void res.status(400).json({ error: p.error });
  const a = p.v;

  try {
    const r = await dbRpc<Fired>('demo_alert_fire', {
      p_event_id: a.eventId,
      p_source: a.source,
      p_kind: a.kind,
      p_message: a.message,
      p_camera: a.camera,
      p_labels: a.labels,
      p_dry: a.dry,
    });
    if (r.error === 'no_target') return void res.status(404).json(r);
    if (r.error === 'cooldown') return void res.status(429).json(r);
    return void res.status(200).json({ ...r, event_id: a.eventId });
  } catch (e) {
    console.error('alert_trigger', e instanceof Error ? e.message : e);
    return void res.status(502).json({ error: 'upstream' });
  }
}
