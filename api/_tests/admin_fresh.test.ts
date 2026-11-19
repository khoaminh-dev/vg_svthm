import test from 'node:test';
import assert from 'node:assert/strict';

process.env.ADMIN_SESSION_SECRET = 'test-secret-for-admin-session-123456';
const { issueToken, tokenAgeMs, ipHash, clientIp } = await import('../_lib/admin.ts');

const req = (token?: string, extra: Record<string, string> = {}) => ({ headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...extra } }) as any;

test('token mới cấp: tuổi gần 0', () => {
  const t = issueToken();
  const age = tokenAgeMs(req(t));
  assert.ok(age >= 0 && age < 2000, String(age));
});

test('token cũ hơn 15 phút bị coi là cũ; chưa hết hạn 12 giờ', () => {
  const t = issueToken();
  const later = Date.now() + 20 * 60_000;
  const age = tokenAgeMs(req(t), later);
  assert.ok(age > 15 * 60_000 && age < 21 * 60_000, String(age));
});

test('token sai chữ ký, thiếu hoặc hết hạn → Infinity', () => {
  const t = issueToken();
  assert.equal(tokenAgeMs(req()), Infinity);
  assert.equal(tokenAgeMs(req('abc.def')), Infinity);
  const [p] = t.split('.');
  assert.equal(tokenAgeMs(req(`${p}.sai`)), Infinity);
  assert.equal(tokenAgeMs(req(t), Date.now() + 13 * 3600_000), Infinity);
});

test('clientIp lấy IP đầu tiên; ipHash ổn định và không chứa IP', () => {
  assert.equal(clientIp(req(undefined, { 'x-forwarded-for': '1.2.3.4, 5.6.7.8' })), '1.2.3.4');
  const h = ipHash('1.2.3.4');
  assert.equal(h, ipHash('1.2.3.4'));
  assert.notEqual(h, ipHash('1.2.3.5'));
  assert.ok(!h.includes('1.2.3.4'));
});
