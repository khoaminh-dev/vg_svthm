-- Username "còn trống" cũng tính khi đó chính là username của người đang đăng nhập,
-- để thao tác hoàn tất hồ sơ có thể thử lại an toàn nếu lần trước chỉ thành công một nửa.
create or replace function public.is_username_available(p_username text) returns boolean
language sql security definer set search_path = public stable as $$
  select not exists (
    select 1 from public.profiles
     where username = lower(p_username)
       and id is distinct from auth.uid()
  );
$$;
