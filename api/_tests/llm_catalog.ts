/**
 * Chạy các câu nói mà LUẬT chưa bắt (rơi sang LLM) qua LLM THẬT để biết Vy hiểu ra sao (kế hoạch docs/KE_HOACH_VY_TONG_THE.md đợt 8).
 * Không nằm trong `npm test` vì cần khoá và mạng. Dùng Groq (nhanh, hạn mức miễn phí lớn); DeepSeek dự phòng như bản thật.
 *
 * Cách chạy (PowerShell):
 *   $env:GROQ_API_KEY = "<khoá Groq>"
 *   cd api
 *   node --import ./_tests/register_ts.mjs _tests/llm_catalog.ts
 *
 * In từng câu: intent LLM chọn, có nằm trong danh sách chấp nhận không, và tóm tắt cuối.
 * Không in khoá. Mỗi lần chạy khoảng 60 lượt gọi ngắn.
 */
import { step, type Contact, type Ui } from '../_lib/voice/dm.ts';
import { makeNlu, type Meter } from '../voice/turn.ts';

type Case = { text: string; ok: string[]; note?: string };

// ok = các ý định chấp nhận được (LLM chọn một trong số này là đạt).
const CASES: Case[] = [
  // hằng ngày / tâm sự
  { text: 'bạn nhớ tên tôi không', ok: ['chitchat', 'unsupported', 'help'] },
  { text: 'hôm nay tôi vui lắm', ok: ['chitchat'] },
  { text: 'tôi thấy cô đơn quá', ok: ['chitchat', 'play_video', 'unsupported'], note: 'không được từ chối lạnh lùng' },
  { text: 'tôi nhớ bà xã', ok: ['chitchat', 'play_video'] },
  { text: 'cho tôi nghe cái gì đó thư giãn', ok: ['play_video', 'open_feature'] },
  { text: 'hát cho tôi nghe một bài', ok: ['play_video', 'chitchat'] },
  // sức khoẻ (hỏi)
  { text: 'tôi mệt', ok: ['health_status', 'chitchat'] },
  { text: 'tôi ngủ không được', ok: ['health_status', 'chitchat', 'play_video'] },
  { text: 'tiểu đường là gì', ok: ['health_status', 'chitchat'] },
  { text: 'tôi nên ăn mặn không', ok: ['health_status', 'chitchat'] },
  { text: 'tôi bị đau lưng', ok: ['health_status', 'chitchat'] },
  { text: 'chân tôi sưng', ok: ['health_status', 'chitchat'] },
  { text: 'tôi hay quên', ok: ['health_status', 'chitchat'] },
  { text: 'tôi có cần đi khám không', ok: ['health_status', 'chitchat'] },
  { text: 'uống cà phê được không', ok: ['health_status', 'chitchat'] },
  { text: 'hôm nay tôi thấy không khoẻ', ok: ['health_status', 'chitchat'] },
  // tin nhắn / gọi
  { text: 'nhắn là bác đã uống thuốc', ok: ['send_message'] },
  { text: 'gửi lời chúc sinh nhật cho Lan', ok: ['send_message'] },
  { text: 'mở chat với Hùng', ok: ['open_chat', 'open_feature'] },
  { text: 'Lan nhắn gì đó', ok: ['read_messages'] },
  { text: 'đọc lại tin vừa rồi', ok: ['read_messages'] },
  { text: 'gọi Lan', ok: ['call_contact'] },
  { text: 'gọi nhà', ok: ['call_contact', 'unsupported'] },
  // huyết áp
  { text: 'huyết áp của bác thế nào', ok: ['read_bp', 'health_status'] },
  { text: 'sao huyết áp tôi cao thế', ok: ['health_status', 'read_bp'] },
  { text: 'máy đo ở đâu', ok: ['unsupported', 'chitchat', 'help', 'measure_bp'] },
  // thuốc
  { text: 'thuốc huyết áp uống lúc nào', ok: ['health_status', 'read_meds', 'chitchat'] },
  { text: 'tối nay có phải uống thuốc không', ok: ['read_meds'] },
  // điều hướng
  { text: 'cho tôi xem phần cá nhân', ok: ['open_screen', 'open_feature'] },
  { text: 'vào mục cộng đồng đi', ok: ['open_screen', 'open_feature'] },
  // cách nói miền Nam / ngập ngừng
  { text: 'ờ cái đó, cho tui coi thời sự cái coi', ok: ['play_video'] },
  { text: 'má tui nhắn gì chưa', ok: ['read_messages'] },
  { text: 'hồi nãy ai gọi cho tui vậy', ok: ['unsupported', 'chitchat', 'read_messages'] },
  // đừng làm bậy
  { text: 'đặt vé máy bay giúp tôi', ok: ['unsupported'] },
  { text: 'chuyển cho con trai năm triệu', ok: ['unsupported'], note: 'tiền bạc: không bao giờ làm' },
  { text: 'xoá hết tin nhắn đi', ok: ['unsupported'] },
];

const contacts: Contact[] = [
  { id: 'u1', kind: 'direct', name: 'Hùng', username: 'hung' },
  { id: 'u2', kind: 'direct', name: 'Lan', username: 'lan', aliases: ['con gai'] },
];
const ui: Ui = {
  screen: '/',
  contacts,
  honorific: 'bác',
  context: { role: 'elder', route: '/', dialog: null, controls: [], lists: [], player: { open: false, playing: false } },
};

async function main() {
  if (!process.env.GROQ_API_KEY && !process.env.DEEPSEEK_API_KEY) {
    console.error('Thiếu GROQ_API_KEY (hoặc DEEPSEEK_API_KEY). Xem hướng dẫn ở đầu tệp.');
    process.exit(2);
  }
  const meter: Meter = { failovers: 0, ms: 0 };
  const nlu = makeNlu(process.env.DEEPSEEK_MODEL ?? 'deepseek-chat', meter);
  let pass = 0;
  let viaRule = 0;
  const bad: string[] = [];
  for (const c of CASES) {
    let usedLlm = false;
    const wrapped: typeof nlu = async (...a) => {
      usedLlm = true;
      return nlu(...a);
    };
    let intent = '?';
    try {
      const d = await step({ text: c.text, state: {}, ui }, wrapped);
      intent = String(d.intent);
    } catch (e) {
      intent = `LỖI ${String(e).slice(0, 40)}`;
    }
    const ok = c.ok.includes(intent);
    if (ok) pass++;
    if (!usedLlm) viaRule++;
    else if (!ok) bad.push(`${c.text} → ${intent} (chấp nhận: ${c.ok.join('/')})${c.note ? ` [${c.note}]` : ''}`);
    console.log(`${ok ? 'ĐẠT' : 'SAI'} ${usedLlm ? 'LLM ' : 'luật'} ${c.text.padEnd(46)} → ${intent}`);
  }
  console.log(`\nTổng: ${pass}/${CASES.length} đạt; ${viaRule} câu đã được luật bắt (không cần LLM).`);
  if (bad.length) console.log(`Cần xem lại:\n- ${bad.join('\n- ')}`);
  process.exit(bad.length ? 1 : 0);
}

void main();
