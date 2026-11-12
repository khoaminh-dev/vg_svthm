-- Hàm trigger không cần gọi qua API
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- is_room_member chỉ dành cho người đã đăng nhập (RLS gọi bằng quyền authenticated)
revoke execute on function public.is_room_member(uuid) from public, anon;
grant execute on function public.is_room_member(uuid) to authenticated;
