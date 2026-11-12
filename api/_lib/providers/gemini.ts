import { KeyPool } from '../keypool.js';
import { UpstreamError, parseRetryAfter, withKeyFailover } from '../router.js';
import type { ChatMessage } from './groq.js';

// Dự phòng cho LLM khi toàn bộ key Groq lỗi. Đặt GEMINI_KEYS và GEMINI_MODEL để bật.
const pool = new KeyPool(process.env.GEMINI_KEYS);

export function geminiChat(messages: ChatMessage[]) {
  return withKeyFailover(pool, async (key) => {
    const model = process.env.GEMINI_MODEL ?? '';
    const r = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: messages.map((m) => ({
            role: m.role === 'assistant' ? 'model' : 'user',
            parts: [{ text: m.content }],
          })),
        }),
      },
    );
    if (!r.ok) throw new UpstreamError(r.status, parseRetryAfter(r.headers.get('retry-after')), await r.text());
    const data = (await r.json()) as { candidates: { content: { parts: { text: string }[] } }[] };
    return data.candidates[0].content.parts.map((p) => p.text).join('');
  });
}
