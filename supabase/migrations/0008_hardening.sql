-- 1) Client chỉ được tạo phòng nhóm; phòng 1-1 chỉ tạo qua RPC (chặn chiếm direct_key của người khác).
drop policy if exists "rooms create" on public.rooms;
create policy "rooms create group" on public.rooms for insert to authenticated
  with check (created_by = auth.uid() and type = 'group' and direct_key is null);

-- Dọn các phòng 1-1 mồ côi (không có thành viên) có thể đã bị tạo trước đó.
delete from public.rooms r
 where r.type = 'direct'
   and not exists (select 1 from public.room_members m where m.room_id = r.id);

-- 2) Tạo phòng nhóm nguyên tử: phòng + thành viên đầu tiên trong một giao dịch.
create or replace function public.create_group_room(p_name text)
returns table (id uuid, name text, type text, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  clean text := btrim(coalesce(p_name, ''));
  new_id uuid;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if char_length(clean) < 1 or char_length(clean) > 50 then raise exception 'invalid_name'; end if;
  insert into public.rooms (name, created_by, type) values (clean, uid, 'group') returning rooms.id into new_id;
  insert into public.room_members (room_id, user_id) values (new_id, uid);
  return query select r.id, r.name, r.type, r.created_at from public.rooms r where r.id = new_id;
end $$;
revoke all on function public.create_group_room(text) from public, anon;
grant execute on function public.create_group_room(text) to authenticated;

-- 3) Cho phép xoá tài khoản: xoá kéo theo dữ liệu của user.
alter table public.rooms drop constraint rooms_created_by_fkey,
  add constraint rooms_created_by_fkey foreign key (created_by) references auth.users(id) on delete cascade;
alter table public.messages drop constraint messages_user_id_fkey,
  add constraint messages_user_id_fkey foreign key (user_id) references auth.users(id) on delete cascade;
alter table public.ocr_records drop constraint ocr_records_user_id_fkey,
  add constraint ocr_records_user_id_fkey foreign key (user_id) references auth.users(id) on delete cascade;

-- 4) Analytics: tên sự kiện/props có khuôn dạng và kích thước giới hạn, và giới hạn tần suất ghi.
alter table public.events
  add constraint events_name_format check (name ~ '^[a-z][a-z0-9_]{0,39}$'),
  add constraint events_props_object check (jsonb_typeof(props) = 'object'),
  add constraint events_props_size check (octet_length(props::text) <= 1024);

create or replace function public.events_rate_limit() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (select count(*) from public.events
       where user_id = new.user_id and created_at > now() - interval '1 minute') >= 120 then
    raise exception 'rate_limited';
  end if;
  return new;
end $$;
drop trigger if exists events_rate_limit on public.events;
create trigger events_rate_limit before insert on public.events
  for each row execute function public.events_rate_limit();
