import type { VercelRequest, VercelResponse } from './_lib/vercel-types.js';
import { requireUser, rateLimit } from './_lib/auth.js';
import { dbInsert, dbSelect } from './_lib/db.js';
import { assess, type Reading, type RiskResult } from './_lib/health/risk.js';
import { HEALTH_MODELS } from './_lib/health/models.js';

type Profile = {
  birth_year: number;
  sex: 'male' | 'female';
  has_hypertension: boolean | null;
  has_heart_disease: boolean | null;
  is_smoker: boolean | null;
  on_bp_meds: boolean | null;
  has_diabetes: boolean | null;
  had_stroke: boolean | null;
  updated_at: string;
};
type ReadingRow = { id: string; systolic: number; diastolic: number; pulse: number | null; measured_at: string };
type Stored = { id: string; level: string; details: RiskResult; created_at: string };

/**
 * Tự đánh giá nguy cơ sau mỗi lần đo huyết áp. App chỉ gọi, không gửi số liệu: server tự đọc hồ sơ
 * và các lần đo của người dùng nên đầu vào luôn khớp dữ liệu đã lưu.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  if (!(await rateLimit(uid, 'hr', 10, Number(process.env.HEALTH_DAILY_LIMIT ?? 200)))) {
    return res.status(429).json({ error: 'rate_limited' });
  }

  try {
    const [profiles, readings] = await Promise.all([
      dbSelect<Profile[]>(`health_profile?user_id=eq.${uid}&select=*&limit=1`),
      dbSelect<ReadingRow[]>(
        `bp_readings?user_id=eq.${uid}&select=id,systolic,diastolic,pulse,measured_at&order=measured_at.desc&limit=3`,
      ),
    ]);
    const p = profiles[0];
    if (!p) return res.status(409).json({ error: 'no_profile' });
    if (!readings.length) return res.status(409).json({ error: 'no_reading' });
    const latest = readings[0];

    // Đã đánh giá cho đúng lần đo này, sau lần sửa hồ sơ cuối: trả lại kết quả cũ, không tính và không ghi trùng.
    const prev = await dbSelect<Stored[]>(
      `health_assessments?user_id=eq.${uid}&reading_id=eq.${latest.id}&select=id,level,details,created_at&order=created_at.desc&limit=1`,
    );
    if (prev[0] && prev[0].created_at >= p.updated_at) {
      return res.status(200).json({ ...prev[0].details, createdAt: prev[0].created_at, cached: true });
    }

    const rs: Reading[] = readings.map((r) => ({
      systolic: r.systolic,
      diastolic: r.diastolic,
      pulse: r.pulse,
      measuredAt: r.measured_at,
    }));
    const result = assess(HEALTH_MODELS, {
      birthYear: p.birth_year,
      sex: p.sex,
      hypertension: p.has_hypertension,
      heartDisease: p.has_heart_disease,
      smoker: p.is_smoker,
      bpMeds: p.on_bp_meds,
      diabetes: p.has_diabetes,
      hadStroke: p.had_stroke,
      readings: rs,
      year: new Date().getUTCFullYear(),
    });
    await dbInsert('health_assessments', {
      user_id: uid,
      reading_id: latest.id,
      level: result.level,
      stroke_p: result.stroke.p,
      heart_p: result.heart.p,
      details: result,
    });
    return res.status(200).json({ ...result, createdAt: new Date().toISOString(), cached: false });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'internal' });
  }
}
