import test from 'node:test';
import assert from 'node:assert/strict';

process.env.ADMIN_SESSION_SECRET = 'test-secret-for-admin-session-123456';
process.env.SUPABASE_URL = 'https://example.supabase.test';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'sb_secret_test';
const { issueToken } = await import('../_lib/admin.ts');
const { handlePlanAction } = await import('../_lib/plans_admin.ts');

type Call = { url: string; method: string; body: unknown };

/** Thay fetch bằng bản giả: trả dữ liệu theo đường dẫn, ghi lại các lệnh ghi. */
function fakeDb(routes: Record<string, unknown>) {
  const calls: Call[] = [];
  globalThis.fetch = (async (url: string, init?: { method?: string; body?: string }) => {
    const method = init?.method ?? 'GET';
    calls.push({ url: String(url), method, body: init?.body ? JSON.parse(init.body) : undefined });
    const path = String(url).replace('https://example.supabase.test/rest/v1/', '');
    const key = Object.keys(routes).find((k) => path.startsWith(k));
    const data = method === 'GET' ? (key ? routes[key] : []) : [];
    return { ok: true, status: 200, json: async () => data, text: async () => '' } as unknown as Response;
  }) as typeof fetch;
  return calls;
}

function fakeRes() {
  const r = { code: 0, body: undefined as unknown, setHeader() {}, status(c: number) { r.code = c; return r; }, json(b: unknown) { r.body = b; return r; }, end() { return r; } };
  return r as any;
}

const req = () => ({ headers: { authorization: `Bearer ${issueToken()}` }, method: 'POST', query: {} }) as any;
const ID = '0b0e7a4e-8f0a-4b8e-9c1d-2a3b4c5d6e7f';
const PAYER = '1c1e7a4e-8f0a-4b8e-9c1d-2a3b4c5d6e7f';
const SUB = { id: ID, payer_id: PAYER, plan_id: null, plan_name: 'Gói tháng', price_vnd: 99000, days: 30, order_code: 'VGAAA111', status: 'pending', admin_note: '', created_at: '2026-11-21T00:00:00Z', confirmed_at: null, expires_at: null };

test('xác nhận đơn chờ: chuyển active, đặt ngày hết hạn, ghi nhật ký', async () => {
  const calls = fakeDb({ 'subscriptions?select=*&id=': [SUB], 'subscriptions?select=expires_at': [], 'profiles': [], 'plans': [], 'plan_settings': [], 'subscriptions?select=*&order': [] });
  const res = fakeRes();
  await handlePlanAction(req(), res, { action: 'confirm_sub', id: ID, note: 'đã nhận' }, 'confirm_sub');
  assert.equal(res.code, 200);
  const patch = calls.find((c) => c.method === 'PATCH' && c.url.includes('subscriptions'));
  assert.ok(patch, 'phải PATCH subscriptions');
  assert.ok(patch.url.includes(`id=eq.${ID}`) && patch.url.includes('status=eq.pending'), 'chỉ đổi đơn đang chờ');
  const b = patch.body as Record<string, string>;
  assert.equal(b.status, 'active');
  assert.equal(b.admin_note, 'đã nhận');
  const days = (Date.parse(b.expires_at) - Date.parse(b.confirmed_at)) / 86_400_000;
  assert.ok(Math.abs(days - 30) < 0.01, `hết hạn sau 30 ngày, được ${days}`);
  assert.ok(calls.some((c) => c.method === 'POST' && c.url.includes('admin_audit')), 'có ghi nhật ký');
});

test('xác nhận đơn không còn chờ: 409, không ghi gì', async () => {
  const calls = fakeDb({ 'subscriptions?select=*&id=': [{ ...SUB, status: 'active' }] });
  const res = fakeRes();
  await handlePlanAction(req(), res, { action: 'confirm_sub', id: ID }, 'confirm_sub');
  assert.equal(res.code, 409);
  assert.equal(calls.filter((c) => c.method !== 'GET').length, 0);
});

test('id sai định dạng: 400 và không gọi DB', async () => {
  const calls = fakeDb({});
  const res = fakeRes();
  await handlePlanAction(req(), res, { action: 'confirm_sub', id: '1; drop table' }, 'confirm_sub');
  assert.equal(res.code, 400);
  assert.equal(calls.length, 0);
});

test('thao tác gói cần đăng nhập admin mới (token cũ bị từ chối)', async () => {
  const calls = fakeDb({});
  const res = fakeRes();
  const old = { headers: { authorization: 'Bearer abc.def' }, method: 'POST', query: {} } as any;
  await handlePlanAction(old, res, { action: 'confirm_sub', id: ID }, 'confirm_sub');
  assert.equal(res.code, 401);
  assert.equal(calls.length, 0);
});

test('cấp tay: tạo đơn đã xác nhận ngay, cộng nối tiếp gói đang chạy', async () => {
  const later = new Date(Date.now() + 10 * 86_400_000).toISOString();
  const calls = fakeDb({ 'profiles?select=id&username': [{ id: PAYER }], 'subscriptions?select=expires_at': [{ expires_at: later }], 'profiles?select=id,username': [], 'plans': [], 'plan_settings': [], 'subscriptions?select=*&order': [] });
  const res = fakeRes();
  await handlePlanAction(req(), res, { action: 'grant_sub', username: '@Hung', days: 5 }, 'grant_sub');
  assert.equal(res.code, 200);
  const ins = calls.find((c) => c.method === 'POST' && c.url.endsWith('/subscriptions'));
  assert.ok(ins, 'phải tạo đơn');
  const b = ins.body as Record<string, unknown>;
  assert.equal(b.status, 'active');
  assert.equal(b.price_vnd, 0);
  const left = (Date.parse(String(b.expires_at)) - Date.now()) / 86_400_000;
  assert.ok(left > 14.9 && left < 15.1, `10 ngày còn lại + 5 ngày = 15, được ${left}`);
});

test('lưu gói đang bán nhưng giá 0: bị từ chối', async () => {
  const calls = fakeDb({});
  const res = fakeRes();
  await handlePlanAction(req(), res, { action: 'save_plan', name: 'A', price_vnd: 0, days: 30, active: true }, 'save_plan');
  assert.equal(res.code, 400);
  assert.equal(calls.length, 0);
});
