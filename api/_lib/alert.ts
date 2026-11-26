import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';

// Cảnh báo khẩn cấp DEMO: kiểm tra khoá gọi và kiểm tra nội dung yêu cầu từ module cảnh báo bên ngoài.

export const ALERT_KINDS = ['fall', 'danger', 'sos', 'test'] as const;
export type AlertKind = (typeof ALERT_KINDS)[number];

export type AlertInput = {
  eventId: string;
  source: string;
  kind: AlertKind;
  message: string;
  camera: string;
  labels: string[] | null;
  dry: boolean;
};

const LABEL = /^[a-z0-9_-]{2,30}$/;
const EVENT_ID = /^[A-Za-z0-9_.:-]{6,80}$/;
const SOURCE = /^[a-z0-9_-]{1,30}$/;

const digest = (s: string) => createHash('sha256').update(s).digest();

/** Khoá hợp lệ nếu trùng một khoá trong `ALERT_API_KEY` (nhiều khoá cách nhau dấu phẩy, mỗi khoá ≥ 24 ký tự). So sánh thời gian cố định. */
export function keyOk(given: string | undefined, env: string | undefined): boolean {
  if (!given) return false;
  const keys = (env ?? '').split(',').map((k) => k.trim()).filter((k) => k.length >= 24);
  let ok = false;
  const g = digest(given);
  for (const k of keys) if (timingSafeEqual(g, digest(k))) ok = true;
  return ok;
}

/** Lấy khoá từ `x-alert-key` hoặc `Authorization: Bearer ...`. */
export function keyFrom(headers: Record<string, string | string[] | undefined>): string | undefined {
  const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
  const direct = one(headers['x-alert-key']);
  if (direct) return direct.trim();
  const auth = one(headers.authorization);
  return auth?.startsWith('Bearer ') ? auth.slice(7).trim() : undefined;
}

export type Parsed = { ok: true; v: AlertInput } | { ok: false; error: string };

/** Kiểm tra từng trường; không đoán, sai là trả mã lỗi để bên gọi sửa. */
export function parseAlert(b: Record<string, unknown> | null): Parsed {
  if (!b) return { ok: false, error: 'bad_json' };

  const kind = b.kind === undefined ? 'danger' : b.kind;
  if (typeof kind !== 'string' || !(ALERT_KINDS as readonly string[]).includes(kind)) return { ok: false, error: 'bad_kind' };

  const source = b.source === undefined ? 'api' : b.source;
  if (typeof source !== 'string' || !SOURCE.test(source)) return { ok: false, error: 'bad_source' };

  const eventId = b.event_id === undefined ? `auto-${randomUUID()}` : b.event_id;
  if (typeof eventId !== 'string' || !EVENT_ID.test(eventId)) return { ok: false, error: 'bad_event_id' };

  const text = (v: unknown, max: number): string | null => {
    if (v === undefined || v === null) return '';
    if (typeof v !== 'string') return null;
    return v.replace(/\s+/g, ' ').trim().slice(0, max);
  };
  const message = text(b.message, 200);
  const camera = text(b.camera, 60);
  if (message === null) return { ok: false, error: 'bad_message' };
  if (camera === null) return { ok: false, error: 'bad_camera' };

  let labels: string[] | null = null;
  if (b.targets !== undefined && b.targets !== null) {
    if (!Array.isArray(b.targets) || b.targets.length === 0 || b.targets.length > 10) return { ok: false, error: 'bad_targets' };
    if (!b.targets.every((t) => typeof t === 'string' && LABEL.test(t))) return { ok: false, error: 'bad_targets' };
    labels = [...new Set(b.targets as string[])];
  }

  if (b.dry_run !== undefined && typeof b.dry_run !== 'boolean') return { ok: false, error: 'bad_dry_run' };

  return { ok: true, v: { eventId, source, kind: kind as AlertKind, message, camera, labels, dry: b.dry_run === true } };
}

/** Body JSON dạng object (không import `_lib/http.ts` để tệp này chạy được trong test strip-only). */
export function bodyOf(raw: unknown): Record<string, unknown> | null {
  let b = raw;
  if (typeof b === 'string') {
    try { b = JSON.parse(b); } catch { return null; }
  }
  return b && typeof b === 'object' && !Array.isArray(b) ? (b as Record<string, unknown>) : null;
}

/** event_id từ query string (một giá trị hợp lệ) hoặc null. */
export function eventIdOf(v: string | string[] | undefined): string | null {
  const s = Array.isArray(v) ? v[0] : v;
  return typeof s === 'string' && EVENT_ID.test(s) ? s : null;
}
