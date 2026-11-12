-- Trigger đếm cần đọc bảng events, nhưng role authenticated không có quyền SELECT: chạy với quyền chủ hàm.
-- (Lỗi này khiến mọi lần ghi sự kiện từ app bị "permission denied" sau migration 0008.)
create or replace function public.events_rate_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.events
       where user_id = new.user_id and created_at > now() - interval '1 minute') >= 120 then
    raise exception 'rate_limited';
  end if;
  return new;
end $$;
revoke all on function public.events_rate_limit() from public, anon, authenticated;
