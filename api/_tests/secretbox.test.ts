import test from 'node:test';
import assert from 'node:assert/strict';
import { decryptKey, encryptKey, isEncrypted, redact, validSecret } from '../_lib/secretbox.ts';

const S1 = 'a'.repeat(32) + 'S1';
const S2 = 'b'.repeat(32) + 'S2';
const KEY = 'sk-proj-' + 'x'.repeat(150);

test('mã hoá rồi giải mã ra đúng khoá; bản mã không chứa khoá gốc', () => {
  const e = encryptKey(KEY, S1, 'openai');
  assert.ok(isEncrypted(e));
  assert.ok(!e.includes('x'.repeat(10)));
  assert.equal(decryptKey(e, [S1], 'openai'), KEY);
});

test('mỗi lần mã hoá cho bản mã khác nhau (IV ngẫu nhiên)', () => {
  assert.notEqual(encryptKey(KEY, S1, 'openai'), encryptKey(KEY, S1, 'openai'));
});

test('sai bí mật, sai nhà cung cấp (aad) hoặc bị sửa thì giải mã thất bại', () => {
  const e = encryptKey(KEY, S1, 'openai');
  assert.throws(() => decryptKey(e, [S2], 'openai'), /decrypt_failed/);
  assert.throws(() => decryptKey(e, [S1], 'groq'), /decrypt_failed/);
  const bad = e.slice(0, -2) + (e.endsWith('AA') ? 'BB' : 'AA');
  assert.throws(() => decryptKey(bad, [S1], 'openai'), /decrypt_failed/);
  assert.throws(() => decryptKey('enc:v1:abc', [S1], 'openai'), /decrypt_failed/);
});

test('đổi bí mật: bí mật cũ vẫn giải mã được khi còn trong danh sách', () => {
  const e = encryptKey(KEY, S1, 'openai');
  assert.equal(decryptKey(e, [S2, S1], 'openai'), KEY);
});

test('không có bí mật thì báo secret_missing, khoá cũ lưu thô trả nguyên văn', () => {
  const e = encryptKey(KEY, S1, 'openai');
  assert.throws(() => decryptKey(e, [undefined, 'ngan'], 'openai'), /secret_missing/);
  assert.equal(decryptKey('gsk_plainlegacykey', [], 'groq'), 'gsk_plainlegacykey');
});

test('bí mật quá ngắn bị từ chối khi mã hoá', () => {
  assert.equal(validSecret('ngan'), false);
  assert.equal(validSecret(S1), true);
  assert.throws(() => encryptKey(KEY, 'ngan', 'openai'), /secret_invalid/);
});

test('thông báo lỗi không chứa khoá', () => {
  const e = encryptKey(KEY, S1, 'openai');
  try { decryptKey(e, [S2], 'openai'); } catch (err) { assert.ok(!String((err as Error).message).includes('sk-')); }
});

test('redact che khoá trong chuỗi log', () => {
  assert.equal(redact('Incorrect API key provided: sk-proj-abcdef123456. Bearer abcdefgh12345678'), 'Incorrect API key provided: sk-***. Bearer ***');
  assert.equal(redact('gsk_abcdef123456 ok'), 'gsk_*** ok');
  assert.equal(redact('không có gì'), 'không có gì');
});
