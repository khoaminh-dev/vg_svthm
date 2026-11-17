import { test } from 'node:test';
import assert from 'node:assert/strict';
import { groqBody, failCode } from '../_lib/voice/llm_body.ts';

const msgs = [{ role: 'user' as const, content: 'x' }];

test('gpt-oss: hạ mức suy nghĩ và nới trần token', () => {
  const b = groqBody(msgs, 300, 'openai/gpt-oss-20b');
  assert.equal(b.reasoning_effort, 'low');
  assert.equal(b.max_tokens, 600);
});

test('gpt-oss: thử lại không có reasoning_effort', () => {
  assert.equal('reasoning_effort' in groqBody(msgs, 300, 'openai/gpt-oss-20b', false), false);
});

test('mô hình khác: không thêm tham số lạ', () => {
  const b = groqBody(msgs, 300, 'llama-3.3-70b-versatile');
  assert.equal('reasoning_effort' in b, false);
  assert.equal(b.max_tokens, 300);
});

test('failCode: mã lỗi ngắn, không lộ nội dung', () => {
  assert.equal(failCode('groq', Object.assign(new Error('secret text'), { status: 429 })), 'groq:429');
  assert.equal(failCode('groq', new SyntaxError('Unexpected end of JSON')), 'groq:parse');
  assert.equal(failCode('groq', new Error('This operation was aborted')), 'groq:timeout');
});
