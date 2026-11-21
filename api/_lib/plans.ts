// Logic thuần của gói Vy Live (dễ test): tính ngày hết hạn khi admin xác nhận thanh toán.

const DAY_MS = 86_400_000;

/**
 * Ngày hết hạn khi xác nhận một đơn [days] ngày. Nếu người mua còn gói đang chạy ([currentExpiry] ở tương lai)
 * thì cộng nối tiếp sau ngày đó, không làm mất phần còn lại; ngược lại tính từ [now].
 */
export function newExpiry(now: Date, days: number, currentExpiry?: Date | null): Date {
  const base = currentExpiry && currentExpiry.getTime() > now.getTime() ? currentExpiry : now;
  return new Date(base.getTime() + days * DAY_MS);
}

export type PlanInput = { name: string; price_vnd: number; days: number; active: boolean; sort: number; note: string };

/** Kiểm tra dữ liệu gói admin nhập. Trả về lỗi (tên trường) hoặc gói đã chuẩn hoá. */
export function parsePlan(b: Record<string, unknown>): { ok: true; plan: PlanInput } | { ok: false; field: string } {
  const name = String(b.name ?? '').trim();
  if (name.length < 1 || name.length > 60) return { ok: false, field: 'name' };
  const price = Number(b.price_vnd);
  if (!Number.isInteger(price) || price < 0 || price > 100_000_000) return { ok: false, field: 'price_vnd' };
  const days = Number(b.days);
  if (!Number.isInteger(days) || days < 1 || days > 3660) return { ok: false, field: 'days' };
  const sort = b.sort === undefined ? 0 : Number(b.sort);
  if (!Number.isInteger(sort) || sort < -1000 || sort > 1000) return { ok: false, field: 'sort' };
  const note = String(b.note ?? '').trim();
  if (note.length > 200) return { ok: false, field: 'note' };
  const active = b.active === true;
  // Gói đang bán phải có giá, để không hiện gói 0đ cho người dùng.
  if (active && price <= 0) return { ok: false, field: 'price_vnd' };
  return { ok: true, plan: { name, price_vnd: price, days, active, sort, note } };
}

export function validUuid(v: unknown): v is string {
  return typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(v);
}
