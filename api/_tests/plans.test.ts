import test from 'node:test';
import assert from 'node:assert/strict';
import { newExpiry, parsePlan, validUuid } from '../_lib/plans.js';

const NOW = new Date('2026-11-21T00:00:00.000Z');

test('newExpiry: chưa có gói thì tính từ bây giờ', () => {
  assert.equal(newExpiry(NOW, 30, null).toISOString(), '2026-12-21T00:00:00.000Z');
});

test('newExpiry: gói cũ đã hết hạn thì tính từ bây giờ, không cộng dồn quá khứ', () => {
  assert.equal(newExpiry(NOW, 30, new Date('2026-10-01T00:00:00.000Z')).toISOString(), '2026-12-21T00:00:00.000Z');
});

test('newExpiry: gói đang chạy thì cộng nối tiếp sau ngày hết hạn, không mất phần còn lại', () => {
  assert.equal(newExpiry(NOW, 30, new Date('2026-12-01T00:00:00.000Z')).toISOString(), '2026-12-31T00:00:00.000Z');
});

test('parsePlan: hợp lệ và chuẩn hoá', () => {
  const r = parsePlan({ name: '  Gói tháng ', price_vnd: 99000, days: 30, active: true, sort: 1, note: '' });
  assert.ok(r.ok);
  if (r.ok) assert.deepEqual(r.plan, { name: 'Gói tháng', price_vnd: 99000, days: 30, active: true, sort: 1, note: '' });
});

test('parsePlan: gói đang bán không được có giá 0', () => {
  const r = parsePlan({ name: 'A', price_vnd: 0, days: 30, active: true });
  assert.deepEqual(r, { ok: false, field: 'price_vnd' });
});

test('parsePlan: bắt từng trường sai', () => {
  assert.deepEqual(parsePlan({ name: '', price_vnd: 1, days: 1 }), { ok: false, field: 'name' });
  assert.deepEqual(parsePlan({ name: 'A', price_vnd: -1, days: 1 }), { ok: false, field: 'price_vnd' });
  assert.deepEqual(parsePlan({ name: 'A', price_vnd: 1.5, days: 1 }), { ok: false, field: 'price_vnd' });
  assert.deepEqual(parsePlan({ name: 'A', price_vnd: 1, days: 0 }), { ok: false, field: 'days' });
  assert.deepEqual(parsePlan({ name: 'A', price_vnd: 1, days: 4000 }), { ok: false, field: 'days' });
});

test('validUuid', () => {
  assert.equal(validUuid('0b0e7a4e-8f0a-4b8e-9c1d-2a3b4c5d6e7f'), true);
  assert.equal(validUuid('1; drop table'), false);
  assert.equal(validUuid(5), false);
});
