import type { VercelRequest, VercelResponse } from './_lib/vercel-types.js';
import llm from './_lib/proxy/llm.js';
import stt from './_lib/proxy/stt.js';
import tts from './_lib/proxy/tts.js';

// Một hàm duy nhất cho /api/llm, /api/stt, /api/tts (gói Vercel Hobby tối đa 12 hàm mỗi lần deploy).
// Địa chỉ gọi không đổi. Các tệp /api/<tên>.ts khác (ocr, youtube, health-risk...) vẫn được ưu tiên vì là tệp riêng.
const ROUTES: Record<string, (req: VercelRequest, res: VercelResponse) => unknown> = { llm, stt, tts };

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const o = req.query.op;
  const name = String(Array.isArray(o) ? o[0] : o ?? '');
  const h = Object.hasOwn(ROUTES, name) ? ROUTES[name] : undefined;
  if (!h) return void res.status(404).json({ error: 'not_found' });
  return void (await h(req, res));
}
