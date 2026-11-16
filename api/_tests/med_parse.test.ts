import { test } from 'node:test';
import assert from 'node:assert/strict';
import { approxDistance, checkEvidence, cleanMedParse, normText } from '../_lib/meds/parse.ts';

const TEXT = `ĐƠN THUỐC
Họ tên: [ĐÃ CHE]
Sáng: Amlodipin 5mg x 1 viên sau ăn
Tối: Metformin 500mg x 1 viên
Khi đau ngực: ngậm Nitroglycerin 0,5mg
Uống 30 ngày. Tái khám 20/12/2026`;
const hay = normText(TEXT);

test('normText bỏ dấu và chữ đ', () => {
  assert.equal(normText('Đau Ngực, Tối!'), 'dau nguc toi');
});

test('approxDistance cho phép sai vài ký tự', () => {
  assert.equal(approxDistance('amlodipin', 'xx amlodipin yy'), 0);
  assert.equal(approxDistance('amlodipin', 'xx amlodlpin yy'), 1);
  assert.ok(approxDistance('amlodipin', 'xx paracetamol yy') > 3);
});

test('checkEvidence: khớp, gần đúng, không có, quá ngắn', () => {
  assert.equal(checkEvidence('Amlodipin 5mg x 1 viên', hay), 'ok');
  assert.equal(checkEvidence('Amlodlpin 5mg x 1 vien', hay), 'fuzzy');
  assert.equal(checkEvidence('Atorvastatin 20mg buổi tối', hay), 'none');
  assert.equal(checkEvidence('ab', hay), 'none');
});

test('cleanMedParse: thuốc bịa hoặc đoạn trích sai bị đánh none, thuốc thật giữ ok', () => {
  const r = cleanMedParse(
    {
      title: 'Đơn tim mạch',
      days: 30,
      recheck: '2026-12-20',
      slots: [
        {
          label: 'Sáng',
          meal: 'after_meal',
          evidence: 'Sáng: Amlodipin 5mg',
          items: [
            { name: 'Amlodipin', strength: '5mg', qty: 1, unit: 'viên', evidence: 'Amlodipin 5mg x 1 viên' },
            { name: 'Aspirin', strength: '81mg', qty: 1, unit: 'viên', evidence: 'Amlodipin 5mg x 1 viên' }, // bịa tên
            { name: 'Bisoprolol', qty: 1, unit: 'viên', evidence: 'Bisoprolol 2,5mg mỗi sáng' }, // bịa cả đoạn trích
          ],
        },
        { label: 'Tối', meal: 'xyz', evidence: 'Tối: Metformin 500mg', items: [{ name: 'Metformin', qty: '1', unit: 'cái', evidence: 'Metformin 500mg x 1 viên' }] },
      ],
      prn: [{ name: 'Nitroglycerin', instruction: 'ngậm khi đau ngực', evidence: 'ngậm Nitroglycerin 0,5mg' }],
    },
    TEXT,
  );
  assert.equal(r.days, 30);
  assert.equal(r.recheck, '2026-12-20');
  assert.deepEqual(r.slots[0].items.map((i) => i.status), ['ok', 'none', 'none']);
  assert.equal(r.slots[0].status, 'ok');
  assert.equal(r.slots[0].meal, 'after_meal');
  assert.equal(r.slots[1].meal, null); // giá trị lạ bị bỏ
  assert.equal(r.slots[1].items[0].unit, 'viên'); // đơn vị lạ về mặc định
  assert.equal(r.slots[1].items[0].status, 'ok');
  assert.equal(r.prn[0].status, 'ok');
});

test('cleanMedParse gộp các cữ cùng tên thành một túi', () => {
  const r = cleanMedParse(
    {
      slots: [
        { label: 'Sáng', meal: 'after_meal', evidence: 'Sáng: Amlodipin 5mg', items: [{ name: 'Amlodipin', evidence: 'Amlodipin 5mg x 1 viên' }] },
        { label: 'sáng', meal: 'with_meal', evidence: 'Sáng: Metformin 500mg', items: [{ name: 'Metformin', evidence: 'Metformin 500mg x 1 viên' }] },
        { label: 'Tối', meal: null, evidence: 'Tối: Metformin', items: [] },
      ],
    },
    TEXT,
  );
  assert.equal(r.slots.length, 2);
  assert.deepEqual(r.slots[0].items.map((i) => i.name), ['Amlodipin', 'Metformin']);
  assert.equal(r.slots[0].meal, null); // hai chỉ dẫn khác nhau
});

test('cleanMedParse chịu được đầu ra rác', () => {
  for (const bad of [null, 'x', 5, [], { slots: 'a', prn: 3 }, { slots: [null, 1, {}], days: 'ba' }]) {
    const r = cleanMedParse(bad, TEXT);
    assert.deepEqual(r.slots, []);
    assert.deepEqual(r.prn, []);
    assert.equal(r.days, null);
  }
  assert.equal(cleanMedParse({ days: 9999, recheck: '2026-13-45' }, TEXT).days, null);
  assert.equal(cleanMedParse({ recheck: '2026-13-45' }, TEXT).recheck, null);
});
