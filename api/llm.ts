import type { VercelRequest, VercelResponse } from '@vercel/node';
import { requireUser, rateLimit } from './_lib/auth.js';
import { withProviderFallback } from './_lib/router.js';
import { groqChat, type ChatMessage } from './_lib/providers/groq.js';
import { geminiChat } from './_lib/providers/gemini.js';
import { sendError } from './_lib/http.js';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  if (!rateLimit(uid)) return res.status(429).json({ error: 'rate_limited' });

  const { messages, json } = req.body as { messages: ChatMessage[]; json?: boolean };
  if (!Array.isArray(messages) || messages.length === 0) return res.status(400).json({ error: 'bad_request' });

  try {
    const providers = [() => groqChat(messages, { json })];
    if (process.env.GEMINI_KEYS) providers.push(() => geminiChat(messages));
    const text = await withProviderFallback(providers);
    return res.status(200).json({ text });
  } catch (e) {
    return sendError(res, e);
  }
}
