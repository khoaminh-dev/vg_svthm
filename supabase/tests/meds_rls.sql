-- Kiểm thử quyền và logic của tính năng Thuốc ở mức cơ sở dữ liệu.
-- Chạy: supabase db query --linked --project-ref <ref> -f supabase/tests/meds_rls.sql
-- Kết quả đúng là báo lỗi có chữ TEST_PASSED (cố ý, để dữ liệu thử bị huỷ).
do $$
declare
  a uuid := '00000000-0000-4000-8000-00000000d001'; -- cha mẹ
  b uuid := '00000000-0000-4000-8000-00000000d002'; -- con (có liên kết)
  c uuid := '00000000-0000-4000-8000-00000000d003'; -- người lạ
  plan uuid; plan2 uuid; ev uuid; n int; bags int; st text; lk uuid;
  body jsonb := '{
    "title": "Đơn thử", "slots": [
      {"label": "Sáng", "time": "07:00", "mode": "list", "bags_remaining": 5,
       "items": [{"name": "Amlodipin", "strength": "5mg", "qty": 1, "unit": "viên"}, {"name": "Aspirin", "qty": 1, "source": "jar"}]},
      {"label": "Tối", "time": "19:00", "mode": "bag"}
    ], "prn": [{"name": "Nitroglycerin", "instruction": "Ngậm 1 viên khi đau ngực", "max_per_day": 3}]}';
begin
  insert into auth.users (id, email, aud, role) values
    (a, 'd001@test.invalid', 'authenticated', 'authenticated'),
    (b, 'd002@test.invalid', 'authenticated', 'authenticated'),
    (c, 'd003@test.invalid', 'authenticated', 'authenticated');
  insert into public.profiles (id, username, display_name) values (a, 'd_parent', 'Cha mẹ'), (b, 'd_child', 'Con'), (c, 'd_other', 'Lạ')
    on conflict (id) do nothing;

  -- A tự tạo đơn
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  plan := public.save_med_plan(a, body, false);
  assert plan is not null, 'tạo đơn phải trả về id';
  select count(*) into n from public.dose_events where owner_id = a;
  assert n between 6 and 8, 'sinh lịch 4 ngày x 2 cữ, thực tế: ' || n;
  select count(*) into n from public.med_items where owner_id = a;
  assert n = 2, 'đủ 2 thuốc trong cữ Sáng';
  select count(*) into n from public.med_prn where owner_id = a;
  assert n = 1, 'có thuốc khi cần';
  -- cữ đã qua giờ lúc tạo đơn không bị tính là chưa uống
  select count(*) into n from public.dose_events where owner_id = a and status = 'pending' and window_end < now();
  assert n = 0, 'cữ đã quá cửa sổ khi tạo đơn không được để pending';

  -- Người lạ không đọc, không ghi được
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from public.med_plans where owner_id = a;
  assert n = 0, 'người lạ không thấy đơn';
  select count(*) into n from public.dose_events where owner_id = a;
  assert n = 0, 'người lạ không thấy lịch uống';
  begin
    perform public.save_med_plan(a, body, false);
    assert false, 'người lạ không được tạo đơn cho người khác';
  exception when insufficient_privilege or sqlstate '42501' then null;
  end;

  -- Liên kết con (quyền mặc định: xem và sửa thuốc)
  execute 'reset role';
  insert into public.family_links (owner_id, carer_id) values (a, b) returning id into lk;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.med_plans where owner_id = a;
  assert n = 1, 'con thấy đơn của cha mẹ';
  select count(*) into n from public.dose_events where owner_id = a;
  assert n >= 6, 'con thấy lịch uống';

  -- Con sửa đơn hộ: được, có nhật ký; đơn mới thay đơn cũ
  plan2 := public.save_med_plan(a, jsonb_set(body, '{title}', '"Đơn mới"'), true);
  select status into st from public.med_plans where id = plan;
  assert st = 'ended', 'đơn cũ phải kết thúc khi thay';
  select count(*) into n from public.med_plans where owner_id = a and status = 'active';
  assert n = 1, 'chỉ còn một đơn đang dùng';
  select count(*) into n from public.dose_events where owner_id = a and plan_id = plan and status = 'pending' and due_at > now();
  assert n = 0, 'lịch tương lai của đơn cũ phải bị xoá';
  execute 'reset role';
  select count(*) into n from public.family_audit where owner_id = a and action = 'edit_meds';
  assert n = 1, 'con sửa đơn phải để lại nhật ký';
  execute 'set local role authenticated';

  -- Ghi nhận uống: túi trừ khi uống, hoàn tác thì cộng lại
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select id into ev from public.dose_events where owner_id = a and plan_id = plan2 and status = 'pending' and slot_label = 'Sáng' order by due_at desc limit 1;
  assert ev is not null, 'có một lần Sáng chưa uống ở tương lai';
  perform public.set_dose(ev, 'taken');
  select status into st from public.dose_events where id = ev;
  assert st = 'taken', 'đã đánh dấu uống';
  select bags_remaining into bags from public.med_slots where plan_id = plan2 and label = 'Sáng';
  assert bags = 4, 'túi giảm một khi uống, thực tế: ' || bags;
  perform public.set_dose(ev, 'pending');
  select bags_remaining into bags from public.med_slots where plan_id = plan2 and label = 'Sáng';
  assert bags = 5, 'hoàn tác thì túi cộng lại';
  perform public.set_dose(ev, 'taken');
  perform public.set_dose(ev, 'taken'); -- lặp lại không trừ thêm
  select bags_remaining into bags from public.med_slots where plan_id = plan2 and label = 'Sáng';
  assert bags = 4, 'bấm uống hai lần chỉ trừ một túi';

  -- Nhắc lại: chỉ chính chủ
  select id into ev from public.dose_events where owner_id = a and plan_id = plan2 and status = 'pending' order by due_at limit 1;
  perform public.set_dose(ev, null, 15);
  select (snoozed_until is not null) into st from public.dose_events where id = ev;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  begin
    perform public.set_dose(ev, null, 15);
    assert false, 'con không được bấm nhắc lại thay cha mẹ';
  exception when insufficient_privilege or sqlstate '42501' then null;
  end;
  -- Con xác nhận hộ được
  perform public.set_dose(ev, 'skipped');
  -- Người lạ không đụng được
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  begin
    perform public.set_dose(ev, 'taken');
    assert false, 'người lạ không được ghi nhận uống';
  exception when insufficient_privilege or sqlstate '42501' then null;
  end;

  -- Cha mẹ rút quyền sửa thuốc: con còn xem nhưng không sửa được
  execute 'reset role';
  update public.family_links set perms = jsonb_set(perms, '{meds_edit}', 'false') where id = lk;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.med_plans where owner_id = a;
  assert n >= 1, 'vẫn xem được khi chỉ mất quyền sửa';
  begin
    perform public.end_med_plan(plan2);
    assert false, 'mất quyền sửa thì không kết thúc đơn được';
  exception when insufficient_privilege or sqlstate '42501' then null;
  end;
  execute 'reset role';
  update public.family_links set perms = jsonb_set(perms, '{meds_view}', 'false') where id = lk;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.med_plans where owner_id = a;
  assert n = 0, 'mất quyền xem thì không thấy gì';

  -- Việc định kỳ: quá cửa sổ thì đánh dấu chưa uống
  execute 'reset role';
  insert into public.dose_events (owner_id, slot_label, due_date, due_at, window_end)
    values (a, 'Thử', current_date, now() - interval '5 hours', now() - interval '1 hour') returning id into ev;
  perform public.maintain_doses();
  select status into st from public.dose_events where id = ev;
  assert st = 'missed', 'quá cửa sổ phải thành missed';

  raise exception 'TEST_PASSED';
end $$;
