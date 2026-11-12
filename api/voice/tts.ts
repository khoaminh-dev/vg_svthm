import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import { requireUser, rateLimit } from '../_lib/auth.js';
import { bodyObject } from '../_lib/http.js';
import { classify, speak } from '../_lib/voice/gate.js';
import type { SayClass } from '../_lib/voice/dm.js';

// 200 audio/mpeg khi dùng được giọng ElevenLabs; 204 + X-TTS-Mode: device khi app nên đọc bằng giọng máy.
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  if (!(await rateLimit(uid, 'vtts', 20, 400))) {
    res.setHeader('X-TTS-Mode', 'device');
    res.setHeader('X-TTS-Reason', 'rate_limited');
    return res.status(204).end();
  }
  const body = bodyObject(req);
  const text = typeof body?.text === 'string' ? body.text.trim().slice(0, 300) : '';
  if (!text) return res.status(400).json({ error: 'bad_request' });

  // Câu cố định/khẩn cấp do server tự nhận diện; app chỉ được xin mức "important" hoặc "other".
  const known = classify(text);
  const asked = body?.class === 'important' ? 'important' : 'other';
  const cls: SayClass = known !== 'other' ? known : asked;

  const r = await speak(uid, text, cls);
  res.setHeader('X-TTS-Mode', r.mode);
  res.setHeader('X-TTS-Reason', r.reason);
  if (r.mode === 'device') return res.status(204).end();
  res.setHeader('Content-Type', 'audio/mpeg');
  res.setHeader('Cache-Control', 'private, max-age=86400');
  return res.status(200).send(r.audio);
}
