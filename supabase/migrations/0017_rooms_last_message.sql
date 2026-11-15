-- Danh sách phòng: kèm tin nhắn gần nhất (để hiện xem trước + giờ) và sắp theo hoạt động mới nhất.
-- Bản app cũ đọc theo tên cột nên các cột thêm vào không ảnh hưởng.
drop function if exists public.my_rooms();

create function public.my_rooms() returns table (
  id uuid,
  name text,
  type text,
  created_at timestamptz,
  peer_id uuid,
  peer_name text,
  peer_username text,
  peer_avatar_url text,
  last_content text,
  last_has_image boolean,
  last_is_mine boolean,
  last_at timestamptz
)
language sql security invoker set search_path = public stable as $$
  select r.id, r.name, r.type, r.created_at,
         p.id, p.display_name, p.username, p.avatar_url,
         lm.content,
         (lm.image_path is not null or lm.image_expired_at is not null),
         (lm.user_id = auth.uid()),
         lm.created_at
  from public.rooms r
  left join lateral (
    select pr.id, pr.display_name, pr.username, pr.avatar_url
    from public.room_members m
    join public.profiles pr on pr.id = m.user_id
    where m.room_id = r.id and m.user_id <> auth.uid()
    limit 1
  ) p on r.type = 'direct'
  left join lateral (
    select m.content, m.image_path, m.image_expired_at, m.user_id, m.created_at
    from public.messages m
    where m.room_id = r.id
    order by m.created_at desc
    limit 1
  ) lm on true
  order by coalesce(lm.created_at, r.created_at) desc;
$$;
revoke execute on function public.my_rooms() from public, anon;
grant execute on function public.my_rooms() to authenticated;
