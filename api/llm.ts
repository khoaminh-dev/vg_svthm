import type { VercelRequest, VercelResponse } from './_lib/vercel-types.js';
import { requireUser, rateLimit } from './_lib/auth.js';
import { withProviderFallback } from './_lib/router.js';
import { groqChat, type ChatMessage } from './_lib/providers/groq.js';
import { geminiChat } from './_lib/providers/gemini.js';
import { bodyObject, sendError } from './_lib/http.js';

const ROLES = new Set(['system', 'user', 'assistant']);
const MAX_MESSAGES = 20;
const MAX_TOTAL_CHARS = 12_000;

/** Chỉ nhận danh sách tin nhắn hợp lệ, có giới hạn số lượng và tổng độ dài (chống dùng làm proxy LLM tự do). */
function parseMessages(v: unknown): ChatMessage[] | null {
  if (!Array.isArray(v) || v.length === 0 || v.length > MAX_MESSAGES) return null;
  let total = 0;
  const out: ChatMessage[] = [];
  for (const m of v) {
    if (!m || typeof m !== 'object') return null;
    const { role, content } = m as { role?: unknown; content?: unknown };
    if (typeof role !== 'string' || !ROLES.has(role) || typeof content !== 'string' || content.length === 0) return null;
    total += content.length;
    if (total > MAX_TOTAL_CHARS) return null;
    out.push({ role: role as ChatMessage['role'], content });
  }
  return out;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  if (!(await rateLimit(uid, 'llm', 20, Number(process.env.LLM_DAILY_LIMIT ?? 300)))) return res.status(429).json({ error: 'rate_limited' });

  const body = bodyObject(req);
  const messages = parseMessages(body?.messages);
  if (!messages) return res.status(400).json({ error: 'bad_request' });
  const json = body?.json === true;

  try {
    const providers = [() => groqChat(messages, { json })];
    if (process.env.GEMINI_KEYS && process.env.GEMINI_MODEL) providers.push(() => geminiChat(messages, { json }));
    const text = await withProviderFallback(providers);
    return res.status(200).json({ text });
  } catch (e) {
    return sendError(res, e);
  }
}
