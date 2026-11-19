# Thiết kế gói Premium/Free và Vy Live (GPT-Live)

Trạng thái: bản thiết kế, thống nhất với chủ dự án ngày 19/11/2026. Đợt A (thử nghiệm) đang làm. Mọi thay đổi giao diện hoặc tính năng khi triển khai phải ghi vào `docs/APP_MAP.md` như thường lệ.

## 0. Mục tiêu và nguyên tắc

1. Phần AI tốn tiền thật (OpenAI) chỉ dành cho gói trả phí. Free vẫn có Vy kiểu hiện tại (Groq/DeepSeek, giọng máy) nhưng giới hạn lượt.
2. **Tính năng cứu người luôn miễn phí:** SOS, nhắc thuốc, huyết áp, gia đình, chat.
3. Mọi quyết định về gói, hạn mức, an toàn nằm ở **server/DB**, không tin app.
4. Tốc độ là lý do chuyển sang GPT-Live, nên mọi thiết kế phải bảo vệ độ trễ.
5. Admin điều khiển được mọi thứ (bậc gói, từng tài khoản, công tắc tắt) mà không cần phát hành app.
6. Live lỗi, hết phút hay bị tắt thì tự về Vy thường, không bao giờ để người lớn tuổi nhìn màn hình lỗi.

## 1. Gói và quyền lợi

### 1.1 Bậc gói (`plan_tiers`, admin tự thêm/sửa/ẩn)
Mỗi bậc: mã, tên, thứ hạng, giá (VND), phút Live mỗi tháng (gói dùng chung), phút tối đa mỗi người, số lượt Vy mỗi ngày, số người lớn tuổi được phủ, trần mỗi phiên (giây), `features jsonb`, đang bán hay ẩn, thứ tự hiển thị. Ví dụ ban đầu: Free, Cơ bản, Gia đình, Cao cấp.

### 1.2 Phiên bản bậc và hai kiểu áp dụng
- Mỗi lần admin sửa bậc tạo một dòng `plan_tier_versions` mới (giới hạn bất biến).
- Gói (`subscriptions`) trỏ tới một phiên bản. Mặc định **giữ nguyên người cũ** (họ giữ quyền lợi lúc mua).
- Khi sửa, admin chọn **"áp cho mọi người ngay"** nếu phải bắt buộc (hạ phút vì chi phí, sửa lỗi): chuyển hàng loạt gói sang phiên bản mới. Ghi `plan_audit` kèm lý do.

### 1.3 Người trả và người hưởng
- Người con (carer) mua; người lớn tuổi (owner) đã liên kết (`family_links` đang `active`) được hưởng, tối đa số người theo bậc (mặc định 3).
- Phút Live **dùng chung theo gói** (mặc định 30 phút/tháng, mỗi người tối đa 15).
- Gói hết hạn hoặc huỷ liên kết thì người lớn tuổi tự về Free.

### 1.4 Vòng đời
`pending → active → grace (ân hạn 3 ngày) → expired`. Admin đặt thêm `suspended` (tạm khoá do lạm dụng) và `refunded`.

### 1.5 Quyền hưởng (`entitlements`, phi chuẩn hoá)
Một dòng mỗi người: `user_id, tier_version, payer_id, status, expires_at, limits jsonb, month_seconds_used`. Trigger và cron cập nhật khi gói/liên kết đổi. Đọc quyền = một lần tra khoá chính, không nối nhiều bảng mỗi lượt gọi.

## 2. Dữ liệu (migration `0029_plans.sql`, `0030_live.sql`)

- `plan_tiers`, `plan_tier_versions` (xem trên).
- `subscriptions(id, payer_id, tier_version_id, status, started_at, expires_at, source[manual|code|promo|play], limits_override jsonb, note)`.
- `plan_codes` (băm mã, bậc, số ngày, số lần dùng, hạn mã, tạo bởi) + RPC `redeem_plan_code(code)` chống dò mã như `redeem_link_code`, có khoá chống trùng.
- `entitlements` (mục 1.5).
- `live_sessions(id, user_id, payer_id, started_at, ended_at, seconds, end_reason[user|idle|cap|timeout|error|breaker], ttfa_ms, mode[R|C], openai_session_id)`; phân vùng theo tháng, giữ 90 ngày. Server ghi lúc cấp phiên và lúc đóng; số giây lấy từ đồng hồ server.
- `plan_audit` chỉ thêm, không sửa, không xoá: ai, lúc nào, trước/sau, lý do (bắt buộc).
- `voice_policy` thêm: `live_enabled`, `live_max_session_sec` (300), `live_idle_sec` (30), `live_global_minutes_per_day`, `live_max_concurrent`, `free_turns_per_day` (20), `live_breaker_until`.
- Cờ riêng từng người: `live_blocked` (chặn Live nhưng giữ Premium), tách khỏi `voice_tiers`.
- RLS: người dùng chỉ đọc gói của mình; mọi ghi qua hàm `security definer` hoặc service role (admin).

## 3. Quản trị (web admin)

- Tìm theo username/email → thẻ chi tiết: gói, nguồn, hạn, phút đã dùng, 10 phiên gần nhất, liên kết gia đình, nút hành động.
- Hành động trên một tài khoản bất kỳ: cấp, gia hạn, đổi bậc, thu hồi ngay, tặng/đặt lại phút, chặn riêng Live, ghi đè giới hạn, khoá (`suspended`).
- Bậc gói: thêm/sửa/ẩn, chọn kiểu áp dụng (giữ người cũ / áp mọi người).
- Mã kích hoạt: tạo hàng loạt, xuất CSV.
- Chi phí Live so với doanh thu theo ngày, cảnh báo người dùng bất thường (gấp nhiều lần trung vị), nút tắt Live toàn hệ thống (`live_enabled`, tác dụng trong 15 giây).
- **Mọi thao tác đi qua một hàm SQL duy nhất** và ghi `plan_audit`. Tách tài khoản admin theo người (hiện dùng chung một cặp `ADMIN_USER/ADMIN_PASS`) để nhật ký biết "ai".

## 4. Nền tảng chạy server

Hiện có 12 hàm Vercel (`APP_MAP` ghi giới hạn Hobby là 12; tài liệu Vercel đã đọc không xác nhận, cần kiểm tra bằng deploy thử). Cũng chưa xác nhận Hobby có cấm dùng thương mại không; phải kiểm trước khi thu tiền.

- **A. Hàm router duy nhất:** gộp các hàm vào một file điều phối, `rewrites` trong `vercel.json` giữ nguyên URL cũ. Không tốn tiền, không đổi nền tảng.
- **B. Supabase Edge Functions:** gói miễn phí tối đa 100 hàm, CPU 2 giây/yêu cầu, chờ 150 giây. Hợp cho tạo phiên Live, nhập mã (gần DB).
- **C. Cloudflare Workers (dự phòng):** miễn phí 100.000 yêu cầu/ngày, CPU 10 ms/yêu cầu, ít trễ khởi động. Dùng nếu B chưa đạt độ trễ.
- **Trong Đợt A:** không thêm hàm mới, chỉ thêm `mode: "live_start"` vào `api/voice/turn.ts`.

## 5. Kiến trúc Vy Live

### 5.1 Kết nối (đã đọc tài liệu OpenAI)
- App tạo cuộc gọi WebRTC (micro + kênh dữ liệu `oai-events`), tạo SDP offer, gửi cho **server của mình**.
- Server (khoá `OPENAI_API_KEY` giữ ở server) kiểm đăng nhập, quyền, hạn mức rồi `POST https://api.openai.com/v1/live/sessions` với `session` (model `gpt-live-1`, chỉ dẫn, kiểu ủy quyền) và `transport: {type: "webrtc", sdp}`. Trả về `session.id` và SDP answer; app đặt làm remote description.
- Chờ sự kiện `session.started`. Kết thúc: gửi `session.close`, chờ `session.closed` (có thống kê dùng) rồi mới đóng kết nối.
- Phí: tính theo giây khi mở phiên; khởi tạo WebRTC tính trước 15 giây (được trừ vào phí chạy). Phí mô hình/tool phía sau tính riêng.
- Không có "khoá tạm" cho app: server là cầu nối SDP duy nhất.

### 5.2 Hai chế độ ủy quyền (Đợt A phải đo cả hai)
GPT-Live lo hội thoại, việc cần làm được "ủy quyền" cho backend.

- **Chế độ R: Responses delegation + hàm tuỳ chỉnh.** OpenAI chạy backend (mặc định `gpt-6-luna`, thử `gpt-6-sol`). Ta khai báo các hàm (`open_feature`, `video_control`, `prepare_message`, `read_bp`...). Model chọn hàm và tham số, app nhận `function_call` trong `response.event`, thực thi, trả `function_call_output` rồi `response.create`. Ít bộ phận chạy, không cần NLU riêng; phụ thuộc chất lượng tiếng Việt của Luna.
- **Chế độ C: client delegation.** Sự kiện `session.delegation.created` **không có nội dung yêu cầu**, chỉ có mã. App phải tự suy ra ý định từ `session.input_transcript.delta` (lớp quyết định, xem mục 6), rồi trả kết quả bằng `session.commentary.append` (nói ra) hoặc `session.thinking.append` (im lặng), giới hạn 500 token mỗi lần. Kiểm soát tối đa, tái dùng `step()` hiện có; đổi lại nhiều logic ở app hơn.
- Chế độ chọn **khi tạo phiên**, muốn đổi phải mở phiên mới. Server quyết định chế độ theo cấu hình để thử A/B.

### 5.3 Quy tắc chung
- Người lớn tuổi nói → GPT-Live; mọi hành động có tác dụng phụ đều qua app (mục 7).
- Chỉ dẫn GPT-Live: nói tiếng Việt, xưng hô theo `honorific`, ngắn gọn, không tự làm việc, không đưa lời khuyên y tế, mọi yêu cầu có hành động thì ủy quyền, đọc đúng kết quả.
- Nạp ngữ cảnh lúc mở phiên bằng `session.thinking.append` (`delegation_id: null`): tên, honorific, danh bạ rút gọn, số đo huyết áp gần nhất; cập nhật khi đổi màn hình.
- Chống nói đệm không mong muốn: `delegation.acknowledgement_delay_ms` (chế độ C).

## 6. Hệ thống tốc độ

Mục tiêu đo: từ lúc người dùng ngừng nói đến âm thanh đầu tiên: **< 0,5 s xã giao, < 1,2 s hành động**.

| Lớp | Việc | Độ trễ mục tiêu |
|---|---|---|
| 0. GPT-Live | Xã giao, nhịp hội thoại, nói đệm khi chờ | gần như không |
| 1. Luật cố định trong app (Dart) | Lệnh ngắn quen thuộc, "ừ/không/thôi", tên trong danh bạ khớp chuẩn | vài chục ms |
| 2. Mô hình quyết định (Jev hoặc Groq nhỏ) | Câu mơ hồ, xác nhận khó, khẩn cấp, "có nói với Vy không" | 0,1–0,5 s |
| 3. Server (`step()`, số liệu sức khoẻ) | Câu cần số liệu thật, ghi dữ liệu | ~1 s, GPT-Live nói đệm |

Tối ưu hạ tầng (cũng có lợi cho Vy thường): kiểm JWT cục bộ (bỏ một vòng tới Supabase Auth), gộp hai lượt rate-limit thành một RPC, đặt server cùng vùng với Supabase, giữ kết nối tái dùng, nạp sẵn ngữ cảnh vào phiên, chỉ nạp trước thông tin kết nối chứ không mở phiên sớm (phí tính theo thời gian mở).

### Jev (TypeSafe AI, ra mắt 15/9/2026)
Mô hình phân loại/quyết định, không sinh văn bản. Trả xác suất và độ tin cậy cho câu hỏi đáp án cố định (đúng/sai, chọn một, chấm điểm). Hãng công bố 70–500 ms; bên bán lại nêu 0,042 USD/1M token vào. **Hãng nói mạnh nhất ở tiếng Anh; chưa có số liệu tiếng Việt.** Dùng cho lớp 2 (chọn người nhận, xác nhận có/không/khác, khẩn cấp, "có nói với Vy không"). Chỉ dùng sau khi bộ đo Đợt A cho kết quả tốt trên tiếng Việt; nếu không, dùng Groq nhỏ.

## 7. An toàn (cơ chế bắt buộc)

- **Phân loại hàm và danh sách cho phép:** chỉ đọc, điều hướng, ghi (cần xác nhận), **cấm** (SOS, xoá, thanh toán, đổi cài đặt, đổi gói, chia sẻ dữ liệu sức khoẻ).
- **Bộ xác nhận là mã Dart cố định, không để model quyết.** Mã xác nhận dùng một lần, có hạn; chỉ chấp nhận khi có một lượt nói thật của người dùng khớp "đồng ý" (luật + lớp 2 có độ tin cậy đủ) hoặc bấm nút trên màn hình. Model tự gọi xác nhận mà không có lượt nói thật thì bị chặn. Khoá chống trùng để một tin không gửi hai lần.
- Hành động có ghi luôn cần xác nhận (TV/người khác nói có thể kích hoạt phiên nghe liên tục). Giữ bộ lọc độ tin cậy kiểu `isReliable` cho văn bản.
- **Khẩn cấp bằng từ khoá ngay trong app** ("cứu", "đau ngực", "ngã"): hiện nút gọi người nhà, độc lập với model. Không bao giờ tự bấm SOS.
- Tên liên hệ và nội dung tin là dữ liệu, không phải lệnh; nội dung tin được đọc lại trước khi gửi.
- **Câu y tế/khẩn cấp phải nguyên văn:** nếu GPT-Live không ép được đọc nguyên văn, tạm tắt giọng GPT-Live và dùng đường TTS hiện có.
- **Cầu chì:** OpenAI lỗi nhiều lần/phút thì cả hệ thống về Vy thường 5 phút (`live_breaker_until`). Mỗi người một phiên tại một thời điểm.
- Chặn chi phí: trần phút theo người và gói, ngân sách ngày, cảnh báo bất thường, hạn mức chi tiêu cứng ở bảng điều khiển OpenAI (chủ dự án tự đặt).
- Quyền riêng tư: server không lưu lời nói/transcript, chỉ số đo; màn đồng ý rõ trước lần Live đầu (giọng nói và câu hỏi sức khoẻ đi tới OpenAI), cập nhật điều khoản; dữ liệu sức khoẻ là dữ liệu nhạy cảm theo Nghị định 13/2023, cần rà soát pháp lý.
- Tình huống cần xử lý: mất mạng, app xuống nền, cuộc gọi đến, mất quyền micro, tai nghe/Bluetooth, hết pin, hết hạn giữa phiên (nối lại), OpenAI 429/5xx.

## 8. Mở rộng tới ~1 triệu người dùng

Thiết kế ngay từ đầu: bảng `entitlements` phi chuẩn hoá; heartbeat chỉ đọc cache, không ghi DB (DB chỉ ghi lúc bắt đầu và kết thúc); bộ đếm ngân sách chung chia mảnh (hoặc Redis); lease có hạn cho giới hạn đồng thời; `live_sessions` phân vùng theo tháng.
Làm khi tới ngưỡng: kiểm JWT cục bộ; xin nâng giới hạn phiên đồng thời của OpenAI (Build 50, Launch 300, Grow 500; hàng nghìn phiên cần bậc cao hơn); gói Supabase trả phí; hết chỗ thì app về Vy thường.
Ước tính (giả định): 5% trong 1 triệu người là Premium, 20 phút/người/tháng → khoảng 50.000 USD/tháng chi phí Live, doanh thu khoảng 94.000 USD ở giá 49.000đ. Biên mỏng, nên trần phút phải chặt.

## 9. Đợt A: thử nghiệm (đang làm)

Không đụng người dùng thật: chỉ chạy cho tài khoản trong `LIVE_ALLOWED_USERS` (biến môi trường), ẩn khỏi giao diện thường.
1. **Tiếng Việt của GPT-Live:** nghe/nói, tên người, số huyết áp (chủ dự án thử trong OpenAI Playground).
2. **Nói đệm khi chờ ủy quyền** có hoạt động không.
3. **Độ trễ thật** (đo trong app): xã giao, lệnh qua chế độ R, lệnh qua chế độ C.
4. **Chế độ R so với C** về chất lượng chọn hàm/tham số tiếng Việt.
5. **Jev so với Groq** trên 50–100 câu lệnh tiếng Việt (bộ đo trong `scripts/nlu_compare/`).
6. `flutter_webrtc` trên máy Android thật: khử vọng, âm lượng, định tuyến loa.

Tiêu chí đạt: tiếng Việt hiểu đúng ≥ 90% câu lệnh mẫu; độ trễ trong mục tiêu mục 6; không có lần "model tự xác nhận" nào trong 50 lượt thử.

## 10. Các đợt tiếp theo

- **B. Gói và hạn mức** (không cần OpenAI): migration, `entitlements`, nhập mã, màn "Gói của tôi", admin, siết Free 20 lượt/ngày.
- **C. Live phía server:** `start/heartbeat/end`, trừ phút nguyên tử, cron dọn phiên treo, cầu chì.
- **D. Live trong app:** `LiveVoiceController`, tách bộ thực thi lệnh dùng chung với `VoiceController`, overlay, đồng ý quyền riêng tư.
- **E. Củng cố:** bảng chi phí admin, kiểm thử, `APP_MAP`, phát hành cho 3–5 gia đình thử nghiệm.
- Sau đó: thanh toán tự động (Play Billing hoặc cổng nội địa) khi lên Play Store.
