-- Loại phòng: nhóm hoặc chat 1-1. Phòng 1-1 có direct_key duy nhất (hai user id sắp xếp) để không tạo trùng.
alter table public.rooms
  add column type text not null default 'group' check (type in ('group', 'direct')),
  add column direct_key text unique;

-- Mở (hoặc tạo nếu chưa có) cuộc trò chuyện riêng với một username. Trả về id phòng.
create function public.create_or_get_direct_room(p_username text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  target uuid;
  key text;
  room uuid;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select id into target from public.profiles where username = lower(trim(p_username));
  if target is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  if target = me then
    raise exception 'cannot chat with yourself' using errcode = '22023';
  end if;

  key := least(me, target)::text || ':' || greatest(me, target)::text;
  select id into room from public.rooms where direct_key = key;
  if room is null then
    insert into public.rooms (name, created_by, type, direct_key)
    values ('Chat riêng', me, 'direct', key)
    on conflict (direct_key) do nothing
    returning id into room;
    if room is null then
      select id into room from public.rooms where direct_key = key;
    else
      insert into public.room_members (room_id, user_id) values (room, me), (room, target);
    end if;
  end if;
  return room;
end $$;
revoke execute on function public.create_or_get_direct_room(text) from public, anon;
grant execute on function public.create_or_get_direct_room(text) to authenticated;

-- Không được mời thêm người vào phòng 1-1
create or replace function public.add_member_by_username(p_room uuid, p_username text) returns void
language plpgsql security definer set search_path = public as $$
declare
  target uuid;
begin
  if not public.is_room_member(p_room) then
    raise exception 'not a member of this room' using errcode = '42501';
  end if;
  if exists (select 1 from public.rooms where id = p_room and type = 'direct') then
    raise exception 'cannot add members to a direct chat' using errcode = '22023';
  end if;
  select id into target from public.profiles where username = lower(trim(p_username));
  if target is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  insert into public.room_members (room_id, user_id) values (p_room, target)
  on conflict do nothing;
end $$;

-- Danh sách phòng của tôi, kèm thông tin người kia nếu là chat 1-1 (chạy dưới quyền người gọi, tôn trọng RLS)
create function public.my_rooms() returns table (
  id uuid,
  name text,
  type text,
  created_at timestamptz,
  peer_id uuid,
  peer_name text,
  peer_username text,
  peer_avatar_url text
)
language sql security invoker set search_path = public stable as $$
  select r.id, r.name, r.type, r.created_at,
         p.id, p.display_name, p.username, p.avatar_url
  from public.rooms r
  left join lateral (
    select pr.id, pr.display_name, pr.username, pr.avatar_url
    from public.room_members m
    join public.profiles pr on pr.id = m.user_id
    where m.room_id = r.id and m.user_id <> auth.uid()
    limit 1
  ) p on r.type = 'direct'
  order by r.created_at desc;
$$;
revoke execute on function public.my_rooms() from public, anon;
grant execute on function public.my_rooms() to authenticated;

-- Realtime: để phòng mới hiện ngay khi được mời
alter publication supabase_realtime add table public.room_members;
