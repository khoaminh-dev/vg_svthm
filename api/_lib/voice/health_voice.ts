import { dbInsert, dbSelect } from '../db.js';
import { buildHealthSay, type Assessed, type BpRow, type HealthSay, type Topic } from './health_say.js';

type StoredAssessment = { level: string; details: { reasons?: string[] } | null };

/**
 * Đọc số liệu của chính người dùng, dựng câu trả lời từ khuôn rồi ghi vào lịch sử hỏi đáp (cho bác xem lại).
 * Việc ghi lịch sử không bao giờ làm hỏng câu trả lời.
 */
export async function answerHealth(uid: string, topic: Topic, hon: string, question: string): Promise<HealthSay> {
  const [readings, assessed, profile] = await Promise.all([
    dbSelect<BpRow[]>(`bp_readings?user_id=eq.${uid}&select=systolic,diastolic,pulse,measured_at&order=measured_at.desc&limit=60`),
    dbSelect<StoredAssessment[]>(`health_assessments?user_id=eq.${uid}&select=level,details&order=created_at.desc&limit=1`),
    dbSelect<{ user_id: string }[]>(`health_profile?user_id=eq.${uid}&select=user_id&limit=1`),
  ]);
  const a: Assessed | null = assessed[0] ? { level: assessed[0].level, reasons: assessed[0].details?.reasons ?? [] } : null;
  const r = buildHealthSay(topic, { hon, now: new Date(), readings, assessment: a, hasProfile: profile.length > 0 });

  void dbInsert('health_qa', {
    user_id: uid,
    topic,
    question: question.trim().slice(0, 300),
    answer: r.say.slice(0, 600),
    level: r.level,
    systolic: r.systolic,
    diastolic: r.diastolic,
  }).catch(() => undefined);
  return r;
}
