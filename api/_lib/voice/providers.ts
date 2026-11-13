import { UpstreamError, parseRetryAfter } from '../router.js';
import { timedFetch, withKeys } from './keys.js';

export type Msg = { role: 'system' | 'user' | 'assistant'; content: string };
export type ChatResult = { text: string; provider: string; failovers: number; tokensIn?: number; tokensOut?: number };

async function fail(r: Response): Promise<never> {
  throw new UpstreamError(r.status, parseRetryAfter(r.headers.get('retry-after')), (await r.text()).slice(0, 300));
}

// ---------- LLM ----------

export async function deepseekChat(messages: Msg[], model: string, maxTokens = 300): Promise<ChatResult> {
  const { value, failovers } = await withKeys('deepseek', async (key) => {
    const r = await timedFetch(
      'https://api.deepseek.com/chat/completions',
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model,
          messages,
          response_format: { type: 'json_object' },
          temperature: 0,
          max_tokens: maxTokens,
        }),
      },
      8000,
    );
    if (!r.ok) await fail(r);
    return (await r.json()) as {
      choices: { message: { content: string } }[];
      usage?: { prompt_tokens: number; completion_tokens: number };
    };
  });
  return {
    text: value.choices[0].message.content,
    provider: 'deepseek',
    failovers,
    tokensIn: value.usage?.prompt_tokens,
    tokensOut: value.usage?.completion_tokens,
  };
}

export async function groqJsonChat(messages: Msg[], maxTokens = 300): Promise<ChatResult> {
  const { value, failovers } = await withKeys('groq', async (key) => {
    const r = await timedFetch(
      'https://api.groq.com/openai/v1/chat/completions',
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', 'User-Agent': 'viegrand/1.0' },
        body: JSON.stringify({
          model: process.env.GROQ_LLM_MODEL ?? 'openai/gpt-oss-20b',
          messages,
          temperature: 0,
          max_tokens: maxTokens,
          response_format: { type: 'json_object' },
        }),
      },
      8000,
    );
    if (!r.ok) await fail(r);
    return (await r.json()) as {
      choices: { message: { content: string } }[];
      usage?: { prompt_tokens: number; completion_tokens: number };
    };
  });
  return {
    text: value.choices[0].message.content,
    provider: 'groq',
    failovers,
    tokensIn: value.usage?.prompt_tokens,
    tokensOut: value.usage?.completion_tokens,
  };
}

export async function geminiJsonChat(messages: Msg[], maxTokens = 300): Promise<ChatResult> {
  const model = process.env.GEMINI_MODEL;
  if (!model) throw new UpstreamError(500, undefined, 'no_gemini_model');
  const system = messages.filter((m) => m.role === 'system').map((m) => m.content).join('\n');
  const { value, failovers } = await withKeys('gemini', async (key) => {
    const r = await timedFetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}),
          contents: messages
            .filter((m) => m.role !== 'system')
            .map((m) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] })),
          generationConfig: { maxOutputTokens: maxTokens, responseMimeType: 'application/json' },
        }),
      },
      8000,
    );
    if (!r.ok) await fail(r);
    return (await r.json()) as { candidates: { content: { parts: { text: string }[] } }[] };
  });
  return { text: value.candidates[0].content.parts.map((p) => p.text).join(''), provider: 'gemini', failovers };
}

// ---------- STT ----------

export type SttResult = { text: string; provider: string; failovers: number; confidence?: number };

function multipart(fields: Record<string, string>, file: { name: string; mime: string; data: Buffer }) {
  const boundary = `----vg${Math.random().toString(16).slice(2)}`;
  const parts: Buffer[] = [];
  for (const [k, v] of Object.entries(fields)) {
    parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`));
  }
  parts.push(
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${file.name}"\r\nContent-Type: ${file.mime}\r\n\r\n`,
    ),
    file.data,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  );
  return { body: new Uint8Array(Buffer.concat(parts)), contentType: `multipart/form-data; boundary=${boundary}` };
}

export async function groqWhisper(audio: Buffer, mime: string, hint: string): Promise<SttResult> {
  const ext = mime.includes('mp4') || mime.includes('m4a') || mime.includes('aac') ? 'm4a' : mime.includes('ogg') ? 'ogg' : mime.includes('wav') ? 'wav' : 'webm';
  const { value, failovers } = await withKeys('groq', async (key) => {
    const mp = multipart(
      {
        model: process.env.GROQ_STT_MODEL ?? 'whisper-large-v3-turbo',
        language: 'vi',
        response_format: 'verbose_json',
        temperature: '0',
        // Gợi ý từ vựng (tên người trong danh bạ, từ khoá) giúp nhận dạng tên riêng tốt hơn.
        ...(hint ? { prompt: hint.slice(0, 220) } : {}),
      },
      { name: `a.${ext}`, mime, data: audio },
    );
    const r = await timedFetch(
      'https://api.groq.com/openai/v1/audio/transcriptions',
      { method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': mp.contentType, 'User-Agent': 'viegrand/1.0' }, body: mp.body },
      7000,
    );
    if (!r.ok) await fail(r);
    return (await r.json()) as { text: string; segments?: { avg_logprob?: number; no_speech_prob?: number }[] };
  });
  const segs = value.segments ?? [];
  const lp = segs.length ? segs.reduce((a, s) => a + (s.avg_logprob ?? -0.5), 0) / segs.length : undefined;
  const ns = segs.length ? Math.max(...segs.map((s) => s.no_speech_prob ?? 0)) : 0;
  // Whisper hay "bịa" chữ khi chỉ có tiếng ồn: coi là không có tiếng nói.
  const text = ns > 0.6 ? '' : value.text.trim();
  return { text, provider: 'groq-whisper', failovers, confidence: lp === undefined ? undefined : Math.max(0, Math.min(1, 1 + lp)) };
}

export async function elevenScribe(audio: Buffer, mime: string): Promise<SttResult> {
  const { value, failovers } = await withKeys('elevenlabs', async (key) => {
    const mp = multipart({ model_id: 'scribe_v1', language_code: 'vie' }, { name: 'a.m4a', mime, data: audio });
    const r = await timedFetch(
      'https://api.elevenlabs.io/v1/speech-to-text',
      { method: 'POST', headers: { 'xi-api-key': key, 'Content-Type': mp.contentType }, body: mp.body },
      8000,
    );
    if (!r.ok) await fail(r);
    return (await r.json()) as { text: string; words?: { logprob?: number; type?: string }[] };
  });
  const ws = (value.words ?? []).filter((w) => w.type === 'word' && typeof w.logprob === 'number');
  const lp = ws.length ? ws.reduce((a, w) => a + (w.logprob as number), 0) / ws.length : undefined;
  return { text: value.text.trim(), provider: 'elevenlabs-scribe', failovers, confidence: lp === undefined ? undefined : Math.max(0, Math.min(1, 1 + lp / 2)) };
}

// ---------- TTS ----------

export async function elevenTts(
  text: string,
  voiceId: string,
  model: string,
): Promise<{ audio: Buffer; fp: string; failovers: number }> {
  const { value, fp, failovers } = await withKeys('elevenlabs', async (key) => {
    const r = await timedFetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_64`,
      {
        method: 'POST',
        headers: { 'xi-api-key': key, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
        body: JSON.stringify({ text, model_id: model, language_code: 'vi' }),
      },
      7000,
    );
    if (!r.ok) await fail(r);
    return Buffer.from(await r.arrayBuffer());
  });
  return { audio: value, fp, failovers };
}
