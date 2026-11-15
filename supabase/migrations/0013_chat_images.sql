-- 0013: Gửi ảnh trong chat (kèm chú thích tùy chọn), ảnh tự hết hạn sau 90 ngày.
-- Thay đổi chỉ thêm cột/bucket/ràng buộc; tin nhắn cũ giữ nguyên.

-- 1) Cột cho ảnh ---------------------------------------------------------------------------------
alter table public.messages
  add column if not exists image_path text,
  add column if not exists image_expired_at timestamptz;

-- Chữ không bắt buộc khi có ảnh (chú thích là tùy chọn).
alter table public.messages drop constraint if exists messages_content_len;
alter table public.messages add constraint messages_content_len
  check (char_length(btrim(content)) <= 2000);
alter table public.messages add constraint messages_has_body
  check (char_length(btrim(content)) >= 1 or image_path is not null or image_expired_at is not null);
-- Ảnh phải nằm đúng thư mục "<phòng>/<người gửi>/" nên không thể gắn ảnh của người khác / phòng khác.
alter table public.messages add constraint messages_image_path_ok
  check (image_path is null or (
    starts_with(image_path, room_id::text || '/' || user_id::text || '/')
    and char_length(image_path) <= 160
  ));

-- Người dùng không được tự đặt trạng thái "đã hết hạn" (chỉ máy chủ dọn ảnh mới đặt).
drop policy if exists "messages send member" on public.messages;
create policy "messages send member" on public.messages for insert to authenticated
  with check (user_id = auth.uid() and public.is_room_member(room_id) and image_expired_at is null);

-- Giới hạn 30 ảnh / người / 24 giờ (chống làm đầy dung lượng).
create index if not exists messages_image_user_idx on public.messages (user_id, created_at)
  where image_path is not null;
-- Phục vụ job dọn ảnh hết hạn.
create index if not exists messages_image_expiry_idx on public.messages (created_at)
  where image_path is not null;

create or replace function public.messages_image_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.image_path is not null and (
    select count(*) from public.messages
    where user_id = new.user_id and image_path is not null and created_at > now() - interval '24 hours'
  ) >= 30 then
    raise exception 'image_limit' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke execute on function public.messages_image_limit() from public, anon, authenticated;
drop trigger if exists messages_image_limit on public.messages;
create trigger messages_image_limit before insert on public.messages
  for each row execute function public.messages_image_limit();

-- 2) Kho lưu trữ ---------------------------------------------------------------------------------
-- Riêng tư, tối đa 5 MB, chỉ jpeg/png/webp. Đường dẫn: <room_id>/<user_id>/<tên file>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-images', 'chat-images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- Tên thư mục đầu tiên có phải là phòng mà mình là thành viên không (an toàn với chuỗi không phải uuid).
create or replace function public.chat_image_room_ok(p text) returns boolean
language sql security definer set search_path = public stable as $$
  select case
    when p ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then public.is_room_member(p::uuid)
    else false
  end;
$$;
revoke execute on function public.chat_image_room_ok(text) from public, anon;
grant execute on function public.chat_image_room_ok(text) to authenticated;

drop policy if exists "chat images read member" on storage.objects;
create policy "chat images read member" on storage.objects for select to authenticated
  using (bucket_id = 'chat-images' and public.chat_image_room_ok((storage.foldername(name))[1]));

drop policy if exists "chat images write member" on storage.objects;
create policy "chat images write member" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-images'
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.chat_image_room_ok((storage.foldername(name))[1])
  );

drop policy if exists "chat images delete own" on storage.objects;
create policy "chat images delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'chat-images' and (storage.foldername(name))[2] = auth.uid()::text);
