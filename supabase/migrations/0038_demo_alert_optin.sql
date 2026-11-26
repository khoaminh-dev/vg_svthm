-- Cảnh báo khẩn cấp DEMO: người dùng tự bật/tắt "nhận cảnh báo thử nghiệm" trong Cài đặt (thay cho việc chủ dự án chèn SQL).
-- Chỉ tác động tới CHÍNH tài khoản đang đăng nhập: bật thì thêm mình vào demo_alert_targets, tắt thì đặt enabled = false.
-- Nhãn tự đặt theo tên đăng nhập (chữ thường, số, _ và -), không có thì dùng mã ngắn từ id.

create or replace function public.demo_alert_join(p_on boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_label text;
  v_fallback text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  if exists (select 1 from public.demo_alert_targets where user_id = v_uid) then
    update public.demo_alert_targets set enabled = coalesce(p_on, false) where user_id = v_uid;
  elsif coalesce(p_on, false) then
    v_fallback := 'u-' || substr(replace(v_uid::text, '-', ''), 1, 12);
    select left(regexp_replace(lower(coalesce(username, '')), '[^a-z0-9_-]', '-', 'g'), 30)
      into v_label from public.profiles where id = v_uid;
    if v_label is null or length(v_label) < 2 then v_label := v_fallback; end if;
    begin
      insert into public.demo_alert_targets (label, user_id) values (v_label, v_uid);
    exception when unique_violation then
      insert into public.demo_alert_targets (label, user_id) values (v_fallback, v_uid)
        on conflict (label) do update set user_id = excluded.user_id, enabled = true;
    end;
  end if;
  return public.demo_alert_me();
end $$;
revoke all on function public.demo_alert_join(boolean) from public, anon;
grant execute on function public.demo_alert_join(boolean) to authenticated;

-- Tài khoản này đang nhận cảnh báo DEMO không, và nhãn là gì (để đưa cho người chạy module).
create or replace function public.demo_alert_me()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_on boolean; v_label text;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select enabled, label into v_on, v_label from public.demo_alert_targets
   where user_id = auth.uid() order by enabled desc, label limit 1;
  return jsonb_build_object('on', coalesce(v_on, false), 'label', v_label);
end $$;
revoke all on function public.demo_alert_me() from public, anon;
grant execute on function public.demo_alert_me() to authenticated;
