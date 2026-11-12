-- Chỉ được tự thêm mình vào phòng do chính mình tạo (trước đây ai cũng vào được phòng bất kỳ)
drop policy "members join self" on public.room_members;
create policy "members join own room" on public.room_members for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.rooms r where r.id = room_id and r.created_by = auth.uid())
  );

-- Thành viên phòng mời người khác theo username
create function public.add_member_by_username(p_room uuid, p_username text) returns void
language plpgsql security definer set search_path = public as $$
declare
  target uuid;
begin
  if not public.is_room_member(p_room) then
    raise exception 'not a member of this room' using errcode = '42501';
  end if;
  select id into target from public.profiles where username = lower(trim(p_username));
  if target is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  insert into public.room_members (room_id, user_id) values (p_room, target)
  on conflict do nothing;
end $$;
revoke execute on function public.add_member_by_username(uuid, text) from public, anon;
grant execute on function public.add_member_by_username(uuid, text) to authenticated;

-- Giới hạn nội dung tin nhắn và tên phòng
alter table public.messages add constraint messages_content_len
  check (char_length(btrim(content)) between 1 and 2000);
alter table public.rooms add constraint rooms_name_len
  check (char_length(btrim(name)) between 1 and 50);
