# Độ trễ và độ hiểu của Vy: số đo, thay đổi, đề xuất

Đo ngày 17/11/2026 từ bảng `voice_turns` (13/11 đến 17/11, 149 lượt, người dùng thử 48H). Bảng này **không lưu lời người dùng**, nên nhóm lỗi hiểu bên dưới suy ra từ kết quả (`outcome`), ý định và độ dài âm thanh.

## 1. Số đo TRƯỚC (đo ở server, từ lúc có chữ đến lúc có quyết định; chưa gồm xác thực, mạng, đọc TTS)

| Khâu | p50 | p95 | Mẫu |
|---|---|---|---|
| Tổng `total_ms` (mọi lượt) | 384 ms | 2526 ms | 149 |
| Nhận dạng giọng nói (Groq Whisper) | 326 ms | 447 ms | 147 |
| Hiểu ý bằng mô hình, Groq | 557 ms | 882 ms | 56 |
| Hiểu ý bằng mô hình, DeepSeek (dự phòng) | 2206 ms | 3365 ms | 12 |
| Tổng lượt có gọi mô hình, Groq / DeepSeek | 907 / 2558 ms | 1519 / 3687 ms | 56 / 12 |

Phát hiện chính:
- 46% lượt (69/149) gọi mô hình; **12/68 lần (18%) Groq lỗi rồi phải nhờ DeepSeek, chậm gấp ~4 lần**. Nguyên nhân khả dĩ: gpt-oss "nghĩ" bằng chính trần 300 token (trung bình 183 token ra), JSON bị cắt → lỗi phân tích. Chưa chứng minh được (trước đây không ghi mã lỗi); nay có `nlu_fail`.
- Các khâu không được đo trước đây: xác thực (gọi Supabase Auth), giới hạn tần suất (2 lần gọi DB nối đuôi nhau), đọc chính sách, mạng, TTS, và phần máy làm trước khi gửi (`_loadPrefs`, `_contacts`).
- Vùng: Vercel `hnd1` (Tokyo) cùng vùng với Supabase `ap-northeast-1`, không có độ trễ giữa hai bên. Groq/ElevenLabs ở Mỹ, DeepSeek ở Trung Quốc: không đổi được bằng vùng.

## 2. Thay đổi đã làm (không đổi giao diện, có test)

1. Đo từng khâu, trả về trong `meta.timings` và ghi vào props `voice_turn`: `rtt_ms`, `auth_ms`, `rate_ms`, `stt_ms`, `nlu_ms`, `dm_ms`, `health_ms`, `server_ms`, `fast`, `nlu_fail`.
2. Xác thực và đọc chính sách chạy song song; giới hạn phút/ngày chạy song song (ước tính bớt 30-80 ms mỗi lượt).
3. Groq gpt-oss `reasoning_effort: low` + trần 600 token (tự thử lại không có tham số nếu Groq trả 400); hạn Groq 3,5 giây thay 8 giây trước khi sang DeepSeek. Mục tiêu: giảm tỉ lệ rơi sang DeepSeek và giảm p50 của khâu hiểu ý.
4. Luật nhanh không gọi mô hình: nhắn tin (người nhận khớp danh bạ), chào hỏi, cảm ơn, việc chưa hỗ trợ. Mỗi lượt trúng luật nhanh bớt 0,6 đến 2,3 giây.
5. Độ hiểu: gợi ý từ vựng cho nhận dạng giọng nói ("Vy, nhắn tin, huyết áp"); thêm 7 câu Whisper hay bịa vào danh sách loại.

**Số SAU: chưa có.** Thay đổi chưa phát hành. Sau khi phát hành, chạy truy vấn ở mục 5 trên sự kiện `voice_turn` mới để điền bảng sau.

## 3. Nhóm lỗi hiểu (từ dữ liệu)

1. **Nghe không rõ chiếm 33% lượt (49/149, `low_confidence`)**. 21/49 có âm thanh dưới 1 giây (nhỏ nhất 643 ms), trong khi mọi lượt thành công dài từ 1,9 giây trở lên (p10 = 2,7 giây). Tức là app đang gửi đoạn ngắn toàn tiếng ồn; 29/49 có độ tin cậy 0,8+ nhưng bị loại do khớp "câu bịa" của Whisper. Hướng sửa ở **phía app** (xem đề xuất).
2. **"Không hỗ trợ" 13% lượt (19/149)**: người dùng nhờ việc ngoài khả năng (gọi điện, thời tiết, giờ giấc là các ứng viên). Đã thêm luật cho nhóm này; muốn biết đúng người ta hỏi gì cần ghi câu bị từ chối (xem đề xuất).
3. **"Chitchat" 18% (27/149)**: chào hỏi/hỏi thăm đi qua mô hình tốn 0,6-2,3 giây. Đã thêm luật cho chào hỏi và cảm ơn.
4. **Ngắt lời (`voice_barge_in` 19 lần), không nghe thấy (`voice_no_speech` 9 lần), `voice_error` 1 lần** so với 139 `voice_turn`: tỉ lệ ngắt lời 14% gợi ý Vy nói dài hoặc micro bật lại quá sớm.
5. **"Dừng" bị bắt thành Hủy**: luật Hủy (`dừng`, `dừng lại`) chạy trước điều khiển video nên "dừng" khi đang xem video có thể bị hiểu là hủy lệnh thay vì tạm dừng. Chưa sửa vì cần biết app xử lý `cancel` khi đang phát video thế nào.

## 4. Đề xuất cần người dùng quyết định (không tự đổi)

| Đề xuất | Lý do / lợi ích ước tính | Chi phí |
|---|---|---|
| Vercel: đổi vùng `hnd1` sang `sin1` (Singapore) | Gần Việt Nam hơn khoảng 40-60 ms mỗi chiều; nhưng Supabase ở Tokyo nên mỗi lần gọi DB thêm ~70 ms. Chỉ có lợi nếu cũng chuyển DB. **Không khuyến nghị** | Miễn phí, nhưng đổi cấu hình |
| Bật Fluid compute / giữ instance nóng (Vercel Pro) | Cắt khởi động nguội (thường 300-800 ms với Node + TypeScript) ở lượt đầu sau lúc rảnh. Mẫu hiện nay (149 lượt/4 ngày) đủ thưa để nhiều lượt gặp khởi động nguội | Vercel Pro |
| Dùng JWKS xác thực JWT tại chỗ thay vì gọi Supabase Auth mỗi lượt | Bớt ~30-80 ms mỗi lượt. Cần đổi cách kiểm tra token | Công sức, không tốn tiền |
| App: tối thiểu 1,0 giây âm thanh mới gửi (và cắt đuôi im lặng) | Bỏ ~14% lượt vô ích (âm thanh <1 giây toàn tiếng ồn), mỗi lượt tiết kiệm ~0,4-0,9 giây + đỡ hạn mức Groq. Cần kiểm thử với câu trả lời ngắn như "có", "gửi" | Đổi hành vi app |
| App: nạp song song `_loadPrefs` và `_contacts` trước khi gửi | Bớt thời gian chờ phía máy (chưa đo) | Công sức nhỏ |
| Ghi mẫu câu bị `unsupported`/`low_confidence` (đã bỏ tên và số, và có sự đồng ý của người dùng) | Để biết chính xác nhóm lỗi hiểu và thêm luật đúng chỗ. Hiện không có cách nào xem lời người dùng | Cần người dùng đồng ý về quyền riêng tư |
| DeepSeek: tắt chế độ suy nghĩ cho lượt hiểu ý | p50 2,2 giây của DeepSeek là quá cao cho JSON ngắn; chưa kiểm thử tham số nên chưa bật | Cần thử trực tiếp (không có khoá trong máy này) |
| Migration thêm cột jsonb `timings` vào `voice_turns` | Truy vấn p50/p95 từng khâu dễ hơn đọc từ `events.props` | Áp dụng migration lên CSDL thật |

## 5. Truy vấn lấy số SAU (chạy trên `events`, tên `voice_turn`, có `props->>'server_ms'`)

```sql
select count(*) n,
  percentile_cont(0.5)  within group (order by (props->>'rtt_ms')::int)    rtt_p50,
  percentile_cont(0.95) within group (order by (props->>'rtt_ms')::int)    rtt_p95,
  percentile_cont(0.5)  within group (order by (props->>'server_ms')::int) srv_p50,
  percentile_cont(0.95) within group (order by (props->>'server_ms')::int) srv_p95,
  avg((props->>'fast')::int) fast_ratio,
  count(*) filter (where props->>'nlu_fail' <> '') nlu_fail_n
from events where name = 'voice_turn' and props ? 'server_ms';
```
