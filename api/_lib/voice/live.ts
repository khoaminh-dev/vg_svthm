import { createHash } from 'node:crypto';

// Phần thuần (không import nội bộ, kiểm thử bằng `node --test`) của Vy Live, Đợt A.
// Xử lý yêu cầu nằm ở live_start.ts. Xem docs/PREMIUM_LIVE_DESIGN.md.

export type LiveMode = 'R' | 'C'; // R = Responses delegation (hàm tuỳ chỉnh), C = client delegation

const HONORIFICS = ['bác', 'cô', 'chú', 'ông', 'bà', 'anh', 'chị'];
const honorificOf = (v: string): string => (HONORIFICS.includes(v) ? v : 'bác');

/** Tài khoản được thử Live qua biến môi trường (danh sách id, cách nhau bằng dấu phẩy). Rỗng = không ai. */
export function liveAllowed(uid: string, env: string | undefined = process.env.LIVE_ALLOWED_USERS): boolean {
  return (env ?? '').split(',').map((s) => s.trim()).filter(Boolean).includes(uid);
}

/** Định danh ẩn danh gửi kèm yêu cầu (không đưa id người dùng thật cho bên thứ ba). */
export function safetyId(uid: string): string {
  return createHash('sha256').update(`vg-live:${uid}`).digest('hex').slice(0, 32);
}

export function validSdp(sdp: unknown): sdp is string {
  return typeof sdp === 'string' && sdp.length > 50 && sdp.length <= 30_000 && sdp.startsWith('v=0');
}

export function pickMode(v: unknown, fallback: string | undefined = process.env.LIVE_MODE): LiveMode {
  const m = typeof v === 'string' ? v : fallback;
  return m === 'C' ? 'C' : 'R';
}

export const ACK_DELAY_MS = 3000;

/** Chế độ C: ứng dụng (Vy cũ) lo hành động, GPT-Live chỉ là giọng. Cần đọc nguyên văn và chuyển mọi câu trả lời kế tiếp. */
const clientExtra = (hon: string) => `
- Bạn CHỈ tự trả lời chào hỏi, cảm ơn, tạm biệt. MỌI câu khác của ${hon} (mở, bật, phát, nghe nhạc, dừng, tiếp, quay lại, xem, đọc, nhắn, gửi, hỏi về sức khoẻ, hay bất cứ điều gì bạn chưa chắc) đều phải giao ngay cho phần xử lý phía sau. Không hỏi lại ${hon} (ví dụ hỏi thể loại nhạc), không nói "con sẽ mở/làm", không nói "để con nhờ phần xử lý", không đoán.
- Khi phần xử lý phía sau gửi lời cần nói, hãy đọc lại NGUYÊN VĂN lời đó, không thêm, không bớt, không diễn đạt lại.
- Nếu phần xử lý vừa hỏi ${hon} một câu (nhắn cho ai, nhắn gì, có gửi không, chọn ai...), thì MỌI câu ${hon} nói kế tiếp, kể cả "ừ", "không", "gửi", "sửa", một cái tên hay nội dung tin nhắn, đều phải giao cho phần xử lý. Không tự trả lời, không tự xác nhận.
- Nếu phần xử lý báo không cần nói gì thì hãy giữ im lặng, đừng tự nói thêm.`;

const frontInstructions = (hon: string, mode: LiveMode = 'R') => `Bạn là Vy, trợ lý giọng nói tiếng Việt cho người cao tuổi trong ứng dụng Viegrand.
- Luôn nói tiếng Việt, giọng ấm áp, chậm rãi, câu ngắn, lễ phép. Tự xưng "con", gọi người dùng là "${hon}".
- Chỉ tự trả lời chào hỏi, hỏi thăm ngắn. Mọi yêu cầu cần làm gì trong ứng dụng (mở màn hình, xem hoặc đọc huyết áp, nhắn tin, xem video, quay lại) hãy giao cho phần xử lý phía sau, đừng tự nói đã làm xong khi chưa có kết quả.
- Không chẩn đoán, không khuyên uống hay đổi thuốc, không đưa lời khuyên y tế. Câu hỏi về sức khoẻ thì giao cho phần xử lý phía sau.
- Nếu ${hon} có dấu hiệu khẩn cấp (đau ngực, khó thở, ngã, choáng) hãy bình tĩnh nhắc ${hon} bấm nút gọi người nhà trên màn hình. Không bao giờ tự nói là đã gọi cấp cứu.
- Nếu chưa nghe rõ, hãy hỏi lại một cách nhẹ nhàng thay vì đoán.${mode === 'C' ? clientExtra(hon) : ''}`;

const backendInstructions = `Bạn xử lý yêu cầu của một trợ lý giọng nói tiếng Việt cho người cao tuổi. Phiên âm lời nói có thể sai, thiếu hoặc được sửa lại sau; dùng ngữ cảnh gần nhất.
- Chọn đúng một hàm khi người dùng muốn thao tác trong ứng dụng. Chưa rõ thì hỏi lại, đừng đoán.
- Nhắn tin: chỉ gọi prepare_message (chuẩn bị), không bao giờ tự gửi. Ứng dụng sẽ đọc lại và hỏi người dùng xác nhận.
- Không bao giờ bấm SOS, xoá, thanh toán hay đổi cài đặt.
- Trả kết quả ngắn gọn bằng tiếng Việt, đúng sự thật: chỉ nói đã làm xong khi hàm xác nhận thành công.`;

type FnDef = { type: 'function'; name: string; description: string; parameters: Record<string, unknown> };

const fn = (name: string, description: string, properties: Record<string, unknown> = {}, required: string[] = []): FnDef => ({
  type: 'function', name, description, parameters: { type: 'object', properties, required, additionalProperties: false },
});

/** Hàm app tự chạy khi dùng chế độ R. Mọi hàm chỉ đọc hoặc điều hướng, trừ prepare_message (chỉ chuẩn bị). */
export const LIVE_TOOLS: FnDef[] = [
  fn('open_feature', 'Mở một mục của ứng dụng.', { feature: { type: 'string', enum: ['chat', 'ocr', 'bp', 'fun', 'home'], description: 'chat=tin nhắn, ocr=chụp máy đo huyết áp, bp=huyết áp, fun=giải trí/video, home=trang chủ' } }, ['feature']),
  fn('go_back', 'Quay lại màn hình trước.'),
  fn('go_home', 'Về trang chủ.'),
  fn('show_bp', 'Mở màn xem lịch sử và biểu đồ huyết áp.'),
  fn('read_bp', 'Đọc kết quả đo huyết áp gần nhất của người dùng.'),
  fn('play_video', 'Tìm và phát video hoặc nhạc.', { query: { type: 'string', description: 'từ khoá tìm kiếm' } }, ['query']),
  fn('video_control', 'Điều khiển video đang phát.', { action: { type: 'string', enum: ['pause', 'play', 'next', 'previous', 'louder', 'quieter'] } }, ['action']),
  fn('prepare_message', 'Chuẩn bị tin nhắn cho một người trong danh bạ. Không gửi; ứng dụng sẽ xác nhận với người dùng.', {
    recipient: { type: 'string', description: 'người nhận như người dùng nói, ví dụ "con trai"' },
    content: { type: 'string', description: 'nội dung tin nhắn nếu đã nói' },
  }, ['recipient']),
];

/** Giá trị cũ đã chạy được (lần thử 19/11), dùng dự phòng nếu OpenAI từ chối giá trị mới. */
export const ACK_DELAY_FALLBACK_MS = 800;
/** Thử từ lớn đến nhỏ: 3000 ms bị OpenAI từ chối (20/11), chưa rõ trần là bao nhiêu nên dò dần, lấy giá trị lớn nhất được nhận. */
export const ACK_DELAY_LADDER = [ACK_DELAY_MS, 2000, 1500, 1200, ACK_DELAY_FALLBACK_MS];

export function buildLiveSession(
  mode: LiveMode,
  honorific: string,
  env: NodeJS.ProcessEnv = process.env,
  ackMs: number = ACK_DELAY_MS,
): Record<string, unknown> {
  const hon = honorificOf(honorific);
  const session: Record<string, unknown> = { model: 'gpt-live-1', instructions: frontInstructions(hon, mode) };
  if (mode === 'C') {
    // Lời "đệm" tự động của Live (kiểu "Dạ, con hiểu rồi...") chỉ nên chen vào khi phần xử lý thật sự chậm. Đo thực tế:
    // từ lúc ủy quyền đến lúc có câu trả lời mất ~1,0–1,4 giây, nên 800 ms làm Live nói chen/nói đè lên câu trả lời.
    session.delegation = { type: 'client', acknowledgement_delay_ms: ackMs };
  } else {
    let extra: Record<string, unknown> = {};
    try {
      const o = env.LIVE_RESPONSES_EXTRA ? JSON.parse(env.LIVE_RESPONSES_EXTRA) : {};
      if (o && typeof o === 'object' && !Array.isArray(o)) extra = o as Record<string, unknown>;
    } catch {
      // cấu hình thêm hỏng: bỏ qua
    }
    session.delegation = {
      type: 'responses',
      responses: {
        model: env.LIVE_BACKEND_MODEL || 'gpt-6-luna',
        instructions: backendInstructions,
        tools: LIVE_TOOLS,
        tool_choice: 'auto',
        ...extra,
      },
    };
  }
  return session;
}
