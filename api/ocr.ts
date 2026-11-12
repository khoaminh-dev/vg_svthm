import type { VercelRequest, VercelResponse } from './_lib/vercel-types.js';
import { requireUser, rateLimit } from './_lib/auth.js';
import { groqVision } from './_lib/providers/groq.js';
import { bodyObject, sendError } from './_lib/http.js';

// Vercel giới hạn body ~4.5 MB; ảnh base64 lớn hơn mức này sẽ bị từ chối.
const MAX_BASE64_CHARS = 4_000_000;

const PROMPT = `You read measurements from a photo (a device display, receipt, invoice, form or table).
Extract every measurement or number that matters as a list of rows.
- "label": what the number is (e.g. SYS, DIA, PULSE, Total, Electricity). Keep the label language as shown on the photo.
- "value": the number exactly as displayed, as a string (keep decimal and thousand separators).
- "unit": the unit if shown (mmHg, kWh, kg, ...), otherwise "".
Ignore decorative text, brand names and model numbers. For blood pressure monitors use labels SYS, DIA and PULSE.
Reply ONLY with JSON: {"values":[{"label":"","value":"","unit":""}],"raw_text":"all text you can read, line by line"}`;

type Row = { label: string; value: string; unit: string };

function clean(parsed: unknown): { values: Row[]; raw_text: string } {
  const obj = (parsed ?? {}) as { values?: unknown; raw_text?: unknown };
  const rows = Array.isArray(obj.values) ? obj.values : [];
  const values: Row[] = rows
    .map((r) => {
      const o = (r ?? {}) as Record<string, unknown>;
      return {
        label: String(o.label ?? '').trim(),
        value: String(o.value ?? '').trim(),
        unit: String(o.unit ?? '').trim(),
      };
    })
    .filter((r) => r.value !== '');
  return { values, raw_text: typeof obj.raw_text === 'string' ? obj.raw_text : '' };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  if (!(await rateLimit(uid, 'ocr', 6, Number(process.env.OCR_DAILY_LIMIT ?? 30)))) return res.status(429).json({ error: 'rate_limited' });

  const { image, mime } = (bodyObject(req) ?? {}) as { image?: string; mime?: string };
  if (typeof image !== 'string' || image.length === 0) return res.status(400).json({ error: 'bad_request' });
  if (image.length > MAX_BASE64_CHARS) return res.status(413).json({ error: 'image_too_large' });
  const type = mime === 'image/png' ? 'image/png' : 'image/jpeg';

  try {
    const text = await groqVision(`data:${type};base64,${image}`, PROMPT);
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      return res.status(502).json({ error: 'bad_model_output' });
    }
    return res.status(200).json(clean(parsed));
  } catch (e) {
    return sendError(res, e);
  }
}
