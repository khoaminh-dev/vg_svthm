import type { VercelRequest, VercelResponse } from './_lib/vercel-types.js';
import { requireUser, rateLimit } from './_lib/auth.js';
import { elevenTts } from './_lib/providers/elevenlabs.js';
import { bodyObject, sendError } from './_lib/http.js';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  if (!(await rateLimit(uid, 'tts', 10, Number(process.env.TTS_DAILY_LIMIT ?? 200)))) return res.status(429).json({ error: 'rate_limited' });

  const { text } = (bodyObject(req) ?? {}) as { text?: unknown };
  if (typeof text !== 'string' || !text || text.length > 600) return res.status(400).json({ error: 'bad_request' });

  try {
    const audio = await elevenTts(text);
    res.setHeader('Content-Type', 'audio/mpeg');
    return res.status(200).send(audio);
  } catch (e) {
    return sendError(res, e);
  }
}
