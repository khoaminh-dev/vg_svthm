import type { VercelRequest, VercelResponse } from './_lib/vercel-types.js';
import { requireUser, rateLimit } from './_lib/auth.js';
import { bodyObject } from './_lib/http.js';

type Video = { id: string; title: string; author: string; duration: number | null };

// Bộ nhớ đệm theo instance: cùng một từ khoá ("nhạc xưa") nhiều người tìm thì không tốn thêm hạn mức YouTube.
const CACHE_MS = 6 * 60 * 60 * 1000;
const cache = new Map<string, { at: number; items: Video[] }>();

/** "PT1H2M10S" thành số giây. */
export function isoSeconds(iso: string | undefined): number | null {
  const m = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(iso ?? '');
  if (!m) return null;
  const s = Number(m[1] ?? 0) * 3600 + Number(m[2] ?? 0) * 60 + Number(m[3] ?? 0);
  return s > 0 ? s : null;
}

const decode = (s: string) =>
  s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>');

async function yt(path: string, params: Record<string, string>, key: string) {
  const url = `https://www.googleapis.com/youtube/v3/${path}?${new URLSearchParams({ ...params, key })}`;
  const r = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!r.ok) throw new Error(`youtube ${r.status}`);
  return (await r.json()) as { items?: any[] };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  const key = process.env.YOUTUBE_API_KEY;
  if (!key) return res.status(503).json({ error: 'not_configured' });
  if (!(await rateLimit(uid, 'yt', 10, Number(process.env.YT_DAILY_LIMIT ?? 60)))) {
    return res.status(429).json({ error: 'rate_limited' });
  }

  const b = bodyObject(req) ?? {};
  const q = typeof b.q === 'string' ? b.q.trim().slice(0, 120) : '';
  if (!q) return res.status(400).json({ error: 'bad_request' });
  const limit = Math.min(Math.max(Number(b.limit) || 12, 1), 20);

  const ck = `${q.toLowerCase()}|${limit}`;
  const hit = cache.get(ck);
  if (hit && Date.now() - hit.at < CACHE_MS) return res.status(200).json({ items: hit.items });

  try {
    // videoEmbeddable: chỉ lấy video xem được trong app; safeSearch strict vì người dùng là người lớn tuổi.
    const found = await yt(
      'search',
      {
        part: 'snippet',
        type: 'video',
        q,
        maxResults: String(limit),
        videoEmbeddable: 'true',
        safeSearch: 'strict',
        regionCode: 'VN',
        relevanceLanguage: 'vi',
      },
      key,
    );
    const base = (found.items ?? [])
      .filter((i) => i?.id?.videoId)
      .map((i) => ({ id: String(i.id.videoId), title: decode(String(i.snippet?.title ?? '')), author: decode(String(i.snippet?.channelTitle ?? '')) }));
    const durations = new Map<string, number | null>();
    if (base.length) {
      const det = await yt('videos', { part: 'contentDetails', id: base.map((v) => v.id).join(',') }, key);
      for (const d of det.items ?? []) durations.set(String(d.id), isoSeconds(d.contentDetails?.duration));
    }
    const items: Video[] = base.map((v) => ({ ...v, duration: durations.get(v.id) ?? null }));
    cache.set(ck, { at: Date.now(), items });
    if (cache.size > 200) cache.delete(cache.keys().next().value as string);
    return res.status(200).json({ items });
  } catch (e) {
    console.error(e);
    return res.status(502).json({ error: 'upstream' });
  }
}
