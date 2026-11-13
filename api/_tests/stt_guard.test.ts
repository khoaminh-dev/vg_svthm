import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isHallucination, isReliable } from '../_lib/voice/stt_guard.ts';

test('chữ ảo quen thuộc của Whisper bị loại', () => {
  assert.equal(isHallucination('Hãy subscribe cho kênh La La School'), true);
  assert.equal(isHallucination('Cảm ơn các bạn đã xem video'), true);
  assert.equal(isHallucination('Hẹn gặp lại các bạn trong video tiếp theo'), true);
});

test('câu bình thường không bị loại nhầm', () => {
  assert.equal(isHallucination('nhắn cho con trai'), false);
  assert.equal(isHallucination('đo huyết áp'), false);
  assert.equal(isHallucination('cảm ơn con'), false);
});

test('độ tin cậy thấp thì không đáng tin, không có số thì cho qua', () => {
  assert.equal(isReliable('đo huyết áp', 0.19), false);
  assert.equal(isReliable('đo huyết áp', 0.55), true);
  assert.equal(isReliable('đo huyết áp', undefined), true);
  assert.equal(isReliable('hãy subscribe cho kênh', 0.9), false);
});
