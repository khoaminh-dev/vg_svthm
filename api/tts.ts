import type { VercelRequest, VercelResponse } from '@vercel/node';
import { requireUser, rateLimit } from './_lib/auth.js';
import { elevenTts } from './_lib/providers/elevenlabs.js';
import { sendError } from './_lib/http.js';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  if (!rateLimit(uid)) return res.status(429).json({ error: 'rate_limited' });

  const { text } = req.body as { text?: string };
  if (!text || text.length > 600) return res.status(400).json({ error: 'bad_request' });

  try {
    const audio = await elevenTts(text);
    res.setHeader('Content-Type', 'audio/mpeg');
    return res.status(200).send(audio);
  } catch (e) {
    return sendError(res, e);
  }
}
