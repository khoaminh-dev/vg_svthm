-- Tính năng Camera (demo): cờ bật/tắt từ xa, mặc định TẮT. Bật cho đợt quay demo:
--   update public.app_flags set enabled = true where key = 'camera';
insert into public.app_flags (key, enabled) values ('camera', false)
on conflict (key) do nothing;

-- Nơi để clip demo và tệp toạ độ nhận diện (xem docs/camera_demo). Đọc công khai, chỉ quản trị viên tải lên.
insert into storage.buckets (id, name, public)
values ('camera-demo', 'camera-demo', true)
on conflict (id) do nothing;
