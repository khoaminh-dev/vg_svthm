// Chuẩn hoá giống `norm` trong dm.ts (không import để file này chạy độc lập trong test).
function norm(s: string): string {
  return s
    .toLowerCase()
    .replace(/đ/g, 'd')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Dưới mức này coi như không nghe rõ: Vy hỏi lại, không hành động (đo từ voice_turns: 0,11 đến 0,21 toàn tiếng ồn). */
export const MIN_STT_CONFIDENCE = 0.3;

// Whisper hay "bịa" các câu quen thuộc từ video khi chỉ có tiếng ồn hoặc im lặng.
const HALLUCINATIONS = [
  'subscribe',
  'dang ky kenh',
  'la la school',
  'hay dang ky',
  'cam on cac ban da xem',
  'cam on ca nha da xem',
  'hen gap lai cac ban',
  'ghien mi go',
  'amara org',
  'phu de',
  'thanks for watching',
  'thank you for watching',
  'like va share',
  'bam chuong',
];

export function isHallucination(text: string): boolean {
  const t = norm(text);
  if (!t) return false;
  return HALLUCINATIONS.some((h) => t.includes(h));
}

/** Văn bản nhận được có đáng tin để hành động không. Độ tin cậy không có (nhà cung cấp không trả) thì cho qua. */
export function isReliable(text: string, confidence: number | undefined): boolean {
  if (isHallucination(text)) return false;
  if (confidence !== undefined && confidence < MIN_STT_CONFIDENCE) return false;
  return true;
}
