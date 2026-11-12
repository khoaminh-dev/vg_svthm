import type { VercelRequest, VercelResponse } from '@vercel/node';
import { requireUser, rateLimit } from './_lib/auth.js';
import { groqTranscribe } from './_lib/providers/groq.js';
import { sendError } from './_lib/http.js';

// Body JSON: { audioBase64, filename?, language? }  (giới hạn body của Vercel ~4.5MB)
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  if (!rateLimit(uid)) return res.status(429).json({ error: 'rate_limited' });

  const { audioBase64, filename = 'audio.m4a', language = 'vi' } = req.body as {
    audioBase64?: string; filename?: string; language?: string;
  };
  if (!audioBase64) return res.status(400).json({ error: 'bad_request' });

  try {
    const text = await groqTranscribe(Buffer.from(audioBase64, 'base64'), filename, language);
    return res.status(200).json({ text });
  } catch (e) {
    return sendError(res, e);
  }
}
