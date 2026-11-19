// So sánh Jev (TypeSafe) với Groq trên câu lệnh tiếng Việt của Vy. Đợt A, xem docs/PREMIUM_LIVE_DESIGN.md.
//
//   $env:TYPESAFE_API_KEY = "..."   # khoá Jev (console.typesafe.ai)
//   $env:GROQ_API_KEY     = "..."   # khoá Groq
//   node scripts/nlu_compare/compare.mjs            # chạy cả hai
//   node scripts/nlu_compare/compare.mjs --only=jev # chỉ một bên
//   node scripts/nlu_compare/compare.mjs --selftest # kiểm tra phần chấm điểm, không gọi mạng
//
// Biến tuỳ chọn: JEV_MODEL (mặc định jev-latest; thử thêm jev-preview), GROQ_LLM_MODEL (mặc định openai/gpt-oss-20b).
// Không in khoá. Kết quả chi tiết ghi vào scripts/nlu_compare/result-<giờ>.json (không đưa vào git).
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const dir = dirname(fileURLToPath(import.meta.url));
const cases = JSON.parse(readFileSync(join(dir, 'cases.json'), 'utf8'));
const args = new Set(process.argv.slice(2));
const only = [...args].find((a) => a.startsWith('--only='))?.slice(7);

const INTENTS = {
  send_message: 'Muốn nhắn/gửi tin nhắn cho một người',
  open_chat: 'Muốn mở khung chat/tin nhắn với một người cụ thể',
  open_feature: 'Muốn mở một mục của ứng dụng (tin nhắn, giải trí, chụp số liệu)',
  measure_bp: 'Muốn đo hoặc chụp máy đo huyết áp',
  show_bp: 'Muốn xem lịch sử hoặc biểu đồ huyết áp',
  read_bp: 'Muốn nghe/đọc kết quả huyết áp lần đo gần nhất',
  health_status: 'Hỏi về tình trạng sức khoẻ, nguy cơ, triệu chứng, thói quen đo',
  play_video: 'Muốn nghe nhạc hoặc xem video, phim',
  video_control: 'Điều khiển video đang phát: dừng, phát tiếp, bài sau, to nhỏ',
  go_back: 'Muốn quay lại màn hình trước',
  go_home: 'Muốn về trang chủ',
  help: 'Hỏi trợ lý làm được những gì',
  chitchat: 'Chào hỏi, hỏi thăm, cảm ơn, trò chuyện ngắn',
  unsupported: 'Việc ngoài khả năng ứng dụng (đặt vé, gọi xe, điều khiển đèn, tin tức, giá cả)',
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function timed(fn) {
  const t0 = performance.now();
  try {
    const r = await fn();
    return { ...r, ms: performance.now() - t0 };
  } catch (e) {
    return { error: String(e.message ?? e).slice(0, 120), ms: performance.now() - t0 };
  }
}

// ---------- Jev ----------
async function jevCall(state, questions) {
  const r = await fetch('https://api.typesafe.ai/v1/systemone', {
    method: 'POST',
    headers: { Authorization: `Bearer ${process.env.TYPESAFE_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: process.env.JEV_MODEL || 'jev-latest', state, questions }),
  });
  if (!r.ok) throw new Error(`jev ${r.status} ${(await r.text()).slice(0, 80)}`);
  return (await r.json()).answers;
}

const jev = {
  intent: (t) => jevCall(t, { q: { type: 'choice', instructions: 'Người cao tuổi này muốn trợ lý làm gì (câu nói có thể nghe sai chữ)', criteria: INTENTS } })
    .then((a) => ({ label: a.q.choice, conf: a.q.confidence })),
  confirm: (t) => jevCall(t, { q: { type: 'choice', instructions: 'Câu này là trả lời cho câu hỏi "Con gửi tin này nhé?"', criteria: {
    yes: 'Đồng ý, xác nhận, bảo cứ làm đi', no: 'Từ chối, huỷ, bảo đừng làm, nói sai rồi', other: 'Không phải trả lời có hay không (hỏi lại, nói chuyện khác, yêu cầu khác)' } } })
    .then((a) => ({ label: a.q.choice, conf: a.q.confidence })),
  emergency: (t) => jevCall(t, { q: { type: 'noul', instructions: 'Người nói đang gặp tình huống khẩn cấp về sức khoẻ hoặc an toàn cần giúp đỡ ngay (đau ngực, khó thở, ngã, ngất, kêu cứu)' } })
    .then((a) => ({ label: a.q.noul >= 0.5, conf: Math.abs(a.q.noul - 0.5) * 2 })),
};

// ---------- Groq ----------
async function groqJson(system, user) {
  const model = process.env.GROQ_LLM_MODEL || 'openai/gpt-oss-20b';
  const oss = /gpt-oss/.test(model);
  const r = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${process.env.GROQ_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model, temperature: 0, max_tokens: oss ? 600 : 300, response_format: { type: 'json_object' },
      ...(oss ? { reasoning_effort: 'low' } : {}),
      messages: [{ role: 'system', content: system }, { role: 'user', content: user }],
    }),
  });
  if (!r.ok) throw new Error(`groq ${r.status}`);
  const j = await r.json();
  return JSON.parse(j.choices[0].message.content);
}

const groq = {
  intent: (t) => groqJson(
    `Bạn là bộ hiểu lệnh tiếng Việt cho ứng dụng chăm sóc người cao tuổi. Chỉ trả JSON {"intent":"..."}. intent là một trong:\n${Object.entries(INTENTS).map(([k, v]) => `- ${k}: ${v}`).join('\n')}\nCâu nói có thể bị nghe sai chữ. Không chắc thì chọn unsupported.`,
    `Câu nói: ${t}`).then((o) => ({ label: o.intent })),
  confirm: (t) => groqJson(
    'Trợ lý vừa hỏi "Con gửi tin này nhé?". Phân loại câu trả lời. Chỉ trả JSON {"answer":"yes|no|other"}: yes=đồng ý, no=từ chối/huỷ/sai, other=không phải trả lời có/không.',
    `Câu nói: ${t}`).then((o) => ({ label: o.answer })),
  emergency: (t) => groqJson(
    'Xác định người nói có đang gặp tình huống khẩn cấp về sức khoẻ/an toàn cần giúp ngay (đau ngực, khó thở, ngã, ngất, kêu cứu) không. Chỉ trả JSON {"emergency":true|false}.',
    `Câu nói: ${t}`).then((o) => ({ label: o.emergency === true })),
};

// ---------- Chấm điểm ----------
function pct(a, b) { return b === 0 ? '-' : `${((100 * a) / b).toFixed(0)}%`; }
function quant(xs, q) { if (!xs.length) return 0; const s = [...xs].sort((a, b) => a - b); return Math.round(s[Math.min(s.length - 1, Math.floor(q * s.length))]); }

export function score(rows, task) {
  const ok = rows.filter((r) => !r.error);
  const right = ok.filter((r) => r.label === r.y);
  const res = { n: rows.length, errors: rows.length - ok.length, acc: right.length / (ok.length || 1), p50: quant(rows.map((r) => r.ms), 0.5), p95: quant(rows.map((r) => r.ms), 0.95) };
  const withConf = ok.filter((r) => typeof r.conf === 'number');
  if (withConf.length) {
    const hi = withConf.filter((r) => r.conf >= 0.8);
    res.coverage80 = hi.length / withConf.length;
    res.acc80 = hi.filter((r) => r.label === r.y).length / (hi.length || 1);
    res.confidentWrong = hi.filter((r) => r.label !== r.y).length; // sai nhưng rất tự tin: nguy hiểm nhất
  }
  if (task === 'emergency') {
    const pos = ok.filter((r) => r.y === true);
    res.recall = pos.filter((r) => r.label === true).length / (pos.length || 1);
    res.falsePositives = ok.filter((r) => r.y === false && r.label === true).length;
  }
  return res;
}

async function runTask(name, task, impl) {
  const out = [];
  const queue = cases[task].map((c) => c);
  const workers = Array.from({ length: 4 }, async () => {
    while (queue.length) {
      const c = queue.shift();
      const r = await timed(() => impl[task](c.t));
      out.push({ t: c.t, y: c.y, ...r });
      await sleep(40);
    }
  });
  await Promise.all(workers);
  return out;
}

function fmt(name, task, s) {
  const extra = [];
  if (s.coverage80 !== undefined) extra.push(`tự tin≥0,8: phủ ${pct(s.coverage80 * 100, 100)}, đúng ${pct(s.acc80 * 100, 100)}, sai-mà-tự-tin ${s.confidentWrong}`);
  if (s.recall !== undefined) extra.push(`bắt được khẩn cấp ${pct(s.recall * 100, 100)}, báo nhầm ${s.falsePositives}`);
  return `| ${name} | ${task} | ${pct(s.acc * 100, 100)} | ${s.p50} | ${s.p95} | ${s.errors} | ${extra.join('; ')} |`;
}

async function selftest() {
  const rows = [
    { y: 'a', label: 'a', ms: 100, conf: 0.9 }, { y: 'a', label: 'b', ms: 200, conf: 0.95 },
    { y: 'b', label: 'b', ms: 300, conf: 0.5 }, { y: 'b', error: 'x', ms: 900 },
  ];
  const s = score(rows, 'intent');
  const exp = { n: 4, errors: 1, coverage80: 2 / 3, acc80: 0.5, confidentWrong: 1 };
  for (const [k, v] of Object.entries(exp)) if (Math.abs(s[k] - v) > 1e-9) throw new Error(`selftest ${k}: ${s[k]} != ${v}`);
  const e = score([{ y: true, label: true, ms: 1 }, { y: true, label: false, ms: 1 }, { y: false, label: true, ms: 1 }], 'emergency');
  if (e.recall !== 0.5 || e.falsePositives !== 1) throw new Error('selftest emergency');
  console.log('selftest OK');
}

if (args.has('--selftest')) {
  await selftest();
} else {
  const want = { jev: !!process.env.TYPESAFE_API_KEY && only !== 'groq', groq: !!process.env.GROQ_API_KEY && only !== 'jev' };
  if (!want.jev && !want.groq) {
    console.error('Thiếu khoá: đặt TYPESAFE_API_KEY và/hoặc GROQ_API_KEY (xem đầu tệp).');
    process.exit(1);
  }
  const lines = ['| Bên | Việc | Đúng | p50 ms | p95 ms | Lỗi | Ghi chú |', '|---|---|---|---|---|---|---|'];
  const all = {};
  for (const [name, impl] of [['Jev', jev], ['Groq', groq]]) {
    if (!want[name.toLowerCase()]) continue;
    for (const task of ['intent', 'confirm', 'emergency']) {
      const rows = await runTask(name, task, impl);
      all[`${name}.${task}`] = rows;
      lines.push(fmt(name, task, score(rows, task)));
    }
  }
  console.log(lines.join('\n'));
  const file = join(dir, `result-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  writeFileSync(file, JSON.stringify(all, null, 1));
  console.log(`\nChi tiết từng câu: ${file}`);
  for (const [k, rows] of Object.entries(all)) {
    const wrong = rows.filter((r) => !r.error && r.label !== r.y);
    if (wrong.length) console.log(`\n[${k}] sai ${wrong.length}:\n` + wrong.slice(0, 12).map((r) => `  "${r.t}" → ${r.label} (đúng: ${r.y})${r.conf != null ? ` conf=${r.conf.toFixed(2)}` : ''}`).join('\n'));
  }
}
