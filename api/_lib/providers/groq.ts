import { KeyPool } from '../keypool.js';
import { UpstreamError, parseRetryAfter, withKeyFailover } from '../router.js';

const pool = new KeyPool(process.env.GROQ_KEYS);
const BASE = 'https://api.groq.com/openai/v1';

export type ChatMessage = { role: 'system' | 'user' | 'assistant'; content: string };

export function groqChat(messages: ChatMessage[], opts: { json?: boolean; temperature?: number } = {}) {
  return withKeyFailover(pool, async (key) => {
    const r = await fetch(`${BASE}/chat/completions`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: process.env.GROQ_LLM_MODEL ?? 'openai/gpt-oss-20b',
        messages,
        temperature: opts.temperature ?? 0.2,
        ...(opts.json ? { response_format: { type: 'json_object' } } : {}),
      }),
    });
    if (!r.ok) throw new UpstreamError(r.status, parseRetryAfter(r.headers.get('retry-after')), await r.text());
    const data = (await r.json()) as { choices: { message: { content: string } }[] };
    return data.choices[0].message.content;
  });
}

export function groqTranscribe(audio: Buffer, filename: string, language?: string) {
  return withKeyFailover(pool, async (key) => {
    const form = new FormData();
    form.append('file', new Blob([new Uint8Array(audio)]), filename);
    form.append('model', process.env.GROQ_STT_MODEL ?? 'whisper-large-v3-turbo');
    if (language) form.append('language', language);
    const r = await fetch(`${BASE}/audio/transcriptions`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}` },
      body: form,
    });
    if (!r.ok) throw new UpstreamError(r.status, parseRetryAfter(r.headers.get('retry-after')), await r.text());
    return ((await r.json()) as { text: string }).text;
  });
}

/** Đọc ảnh bằng mô hình vision của Groq. `imageDataUrl` dạng `data:image/jpeg;base64,...`. */
export function groqVision(imageDataUrl: string, prompt: string) {
  return withKeyFailover(pool, async (key) => {
    const r = await fetch(`${BASE}/chat/completions`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: process.env.GROQ_VISION_MODEL ?? 'qwen/qwen3.8-27b',
        temperature: 0,
        max_tokens: 1500,
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: prompt },
              { type: 'image_url', image_url: { url: imageDataUrl } },
            ],
          },
        ],
      }),
    });
    if (!r.ok) throw new UpstreamError(r.status, parseRetryAfter(r.headers.get('retry-after')), await r.text());
    const data = (await r.json()) as { choices: { message: { content: string } }[] };
    return data.choices[0].message.content;
  });
}
