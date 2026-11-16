-- Kiểm thử quyền truy cập của tính năng Gia đình ở mức cơ sở dữ liệu.
-- Chạy: supabase db query --linked --project-ref <ref> -f supabase/tests/family_rls.sql
-- Kết quả đúng là báo lỗi có chữ TEST_PASSED (cố ý, để toàn bộ dữ liệu thử bị huỷ). Thất bại thì báo lỗi khác.
do $$
declare
  a uuid := '00000000-0000-4000-8000-00000000f001'; -- cha mẹ
  b uuid := '00000000-0000-4000-8000-00000000f002'; -- con
  c uuid := '00000000-0000-4000-8000-00000000f003'; -- người lạ
  code text;
  n int;
  link uuid;
  err text;

begin
  insert into auth.users (id, email, aud, role) values
    (a, 'f001@test.invalid', 'authenticated', 'authenticated'),
    (b, 'f002@test.invalid', 'authenticated', 'authenticated'),
    (c, 'f003@test.invalid', 'authenticated', 'authenticated');
  insert into public.profiles (id, username, display_name) values
    (a, 'f_parent', 'Cha mẹ thử'), (b, 'f_child', 'Con thử'), (c, 'f_other', 'Người lạ')
  on conflict (id) do nothing;
  insert into public.bp_readings (user_id, systolic, diastolic, pulse) values (a, 150, 95, 70);
  insert into public.health_profile (user_id, birth_year, sex) values (a, 1950, 'male');

  -- A tạo mã
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  code := public.create_link_code();
  assert code ~ '^[0-9]{6}$', 'mã phải là 6 số';

  -- C không đọc được gì của A
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from public.bp_readings where user_id = a;
  assert n = 0, 'người lạ không được đọc huyết áp';
  select count(*) into n from public.family_links;
  assert n = 0, 'người lạ không thấy liên kết';

  -- B nhập sai mã, rồi nhập đúng
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from public.bp_readings where user_id = a;
  assert n = 0, 'chưa liên kết thì chưa đọc được';
  select r.error into err from public.redeem_link_code('000000', 'con') r;
  assert err = 'invalid_code', 'mã sai phải bị từ chối';
  select r.link_id, r.error into link, err from public.redeem_link_code(code, 'con') r;
  assert link is not null and err is null, 'nhập đúng mã phải có liên kết';
  select r.error into err from public.redeem_link_code(code, 'con') r;
  assert err = 'invalid_code', 'mã chỉ dùng một lần';

  -- B đọc được dữ liệu sức khoẻ của A, nhưng không đọc lịch sử hỏi Vy
  select count(*) into n from public.bp_readings where user_id = a;
  assert n = 1, 'con đọc được huyết áp của cha mẹ';
  select count(*) into n from public.health_profile where user_id = a;
  assert n = 1, 'con đọc được hồ sơ sức khoẻ';
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  execute 'reset role';
  insert into public.health_qa (user_id, topic, question, answer) values (a, 'general', 'hỏi thử', 'đáp thử');
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.health_qa where user_id = a;
  assert n = 0, 'lịch sử hỏi Vy mặc định tắt';

  -- B ghi huyết áp hộ A: được; ghi cho C: không; ghi mạo danh người khác: không
  insert into public.bp_readings (user_id, systolic, diastolic, recorded_by) values (a, 130, 85, b);
  begin
    insert into public.bp_readings (user_id, systolic, diastolic, recorded_by) values (c, 130, 85, b);
    assert false, 'không được ghi hộ người không liên kết';
  exception when insufficient_privilege or sqlstate '42501' then null;
  end;
  begin
    insert into public.bp_readings (user_id, systolic, diastolic, recorded_by) values (a, 130, 85, c);
    assert false, 'không được ghi với recorded_by của người khác';
  exception when insufficient_privilege or sqlstate '42501' then null;
  end;

  -- B không sửa được hồ sơ của A khi chưa có quyền profile_edit
  update public.health_profile set birth_year = 1990 where user_id = a;
  get diagnostics n = row_count;
  assert n = 0, 'chưa có quyền sửa hồ sơ';
  -- B không đổi được quyền của chính mình
  begin
    perform public.set_link_perms(link, '{"profile_edit": true}'::jsonb, null);
    assert false, 'con không được tự đổi quyền';
  exception when sqlstate 'P0002' then null;
  end;

  -- A bật profile_edit cho B: B sửa được
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.set_link_perms(link, '{"profile_edit": true, "khoa_la": true}'::jsonb, null);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  update public.health_profile set height_cm = 160 where user_id = a;
  get diagnostics n = row_count;
  assert n = 1, 'có quyền thì sửa được hồ sơ';

  -- A tắt quyền health: B mất quyền đọc ngay
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.set_link_perms(link, '{"health": false}'::jsonb, null);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from public.bp_readings where user_id = a;
  assert n = 0, 'tắt quyền health thì không đọc được';

  -- A bật lại rồi tạm dừng: không đọc được; tiếp tục: đọc được
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.set_link_perms(link, '{"health": true}'::jsonb, 'paused');
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from public.bp_readings where user_id = a;
  assert n = 0, 'tạm dừng thì không đọc được';
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.set_link_perms(link, null, 'active');
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from public.bp_readings where user_id = a;
  assert n = 2, 'tiếp tục thì đọc lại được (gồm số đo con ghi hộ)';

  -- my_family hai chiều; nhật ký chỉ chủ đọc được
  select count(*) into n from public.my_family() where role = 'carer' and other_id = a;
  assert n = 1, 'con thấy cha mẹ trong my_family';
  select count(*) into n from public.family_audit where owner_id = a;
  assert n = 0, 'con không đọc được nhật ký của cha mẹ';
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select count(*) into n from public.my_family() where role = 'owner' and other_id = b;
  assert n = 1, 'cha mẹ thấy con trong my_family';
  select count(*) into n from public.family_audit where owner_id = a;
  assert n >= 2, 'cha mẹ thấy nhật ký';

  -- A gỡ liên kết: B mất quyền ngay
  perform public.revoke_link(link);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from public.bp_readings where user_id = a;
  assert n = 0, 'bị gỡ thì không đọc được';
  select count(*) into n from public.my_family();
  assert n = 0, 'liên kết đã gỡ không còn hiện';
  begin
    insert into public.bp_readings (user_id, systolic, diastolic, recorded_by) values (a, 120, 80, b);
    assert false, 'bị gỡ thì không ghi hộ được';
  exception when insufficient_privilege or sqlstate '42501' then null;
  end;

  -- Tự liên kết với chính mình bị chặn; dò mã bị khoá sau 8 lần sai
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  code := public.create_link_code();
  select r.error into err from public.redeem_link_code(code, 'con') r;
  assert err = 'self_link', 'không tự liên kết với chính mình';
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  for i in 1..8 loop
    perform 1 from public.redeem_link_code('99999' || (i % 10)::text, 'con');
  end loop;
  select r.error into err from public.redeem_link_code(code, 'con') r;
  assert err = 'too_many_attempts', 'sau 8 lần sai phải bị khoá, kể cả khi nhập đúng mã';

  execute 'reset role';
  raise exception 'TEST_PASSED';
end $$;
