import type { VercelRequest, VercelResponse } from './_lib/vercel-types.js';
import { requireUser, rateLimit } from './_lib/auth.js';
import { groqTranscribe } from './_lib/providers/groq.js';
import { bodyObject, sendError } from './_lib/http.js';

// Body JSON: { audioBase64, filename?, language? }  (giới hạn body của Vercel ~4.5MB)
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  if (!(await rateLimit(uid, 'stt', 10, Number(process.env.STT_DAILY_LIMIT ?? 200)))) return res.status(429).json({ error: 'rate_limited' });

  const { audioBase64, filename = 'audio.m4a', language = 'vi' } = (bodyObject(req) ?? {}) as {
    audioBase64?: unknown; filename?: unknown; language?: unknown;
  };
  if (typeof audioBase64 !== 'string' || !audioBase64 || audioBase64.length > 4_000_000) {
    return res.status(400).json({ error: 'bad_request' });
  }
  if (typeof filename !== 'string' || !/^[\w.-]{1,60}$/.test(filename)) return res.status(400).json({ error: 'bad_request' });
  if (typeof language !== 'string' || !/^[a-z]{2,3}$/.test(language)) return res.status(400).json({ error: 'bad_request' });

  try {
    const text = await groqTranscribe(Buffer.from(audioBase64, 'base64'), filename, language);
    return res.status(200).json({ text });
  } catch (e) {
    return sendError(res, e);
  }
}
