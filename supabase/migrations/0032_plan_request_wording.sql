-- Thanh toán chỉ tượng trưng: người dùng gửi yêu cầu nâng cấp, admin bấm Duyệt. Đổi lời nhắn mặc định cho khớp.
alter table public.plan_settings alter column pay_note set default 'Yêu cầu của bạn đang chờ Viegrand duyệt. Gói sẽ bật ngay khi được duyệt.';
update public.plan_settings set pay_note = 'Yêu cầu của bạn đang chờ Viegrand duyệt. Gói sẽ bật ngay khi được duyệt.'
 where pay_note = 'Sau khi đặt, hãy chuyển khoản theo hướng dẫn của Viegrand và ghi mã đơn. Gói sẽ bật khi Viegrand xác nhận đã nhận tiền.';
