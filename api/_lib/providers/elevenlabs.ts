import { KeyPool } from '../keypool.js';
import { UpstreamError, parseRetryAfter, withKeyFailover } from '../router.js';

const pool = new KeyPool(process.env.ELEVENLABS_KEYS);

/** Trả về audio mp3 dạng Buffer. */
export function elevenTts(text: string, voiceId = process.env.ELEVENLABS_VOICE_ID ?? '') {
  return withKeyFailover(pool, async (key) => {
    const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
      method: 'POST',
      headers: { 'xi-api-key': key, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
      body: JSON.stringify({
        text,
        model_id: process.env.ELEVENLABS_MODEL ?? 'eleven_multilingual_v2',
      }),
    });
    if (!r.ok) throw new UpstreamError(r.status, parseRetryAfter(r.headers.get('retry-after')), await r.text());
    return Buffer.from(await r.arrayBuffer());
  });
}
