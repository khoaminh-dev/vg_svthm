// Bộ nhớ đệm ngắn của quyền dùng Vy Live (danh sách thử và gói đang hiệu lực). Tách riêng để admin xoá đệm
// mà không phải nạp cả lớp gọi OpenAI.

export const liveCache: {
  users: { at: number; ids: Set<string> } | null;
  plans: Map<string, { at: number; ok: boolean }>;
} = { users: null, plans: new Map() };

/** Xoá đệm ngay (sau khi admin đổi danh sách hoặc xác nhận/thu hồi gói). */
export function invalidateLiveUsers() {
  liveCache.users = null;
  liveCache.plans.clear();
}
