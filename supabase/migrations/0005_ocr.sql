-- Ảnh gốc của kết quả OCR: bucket riêng tư, mỗi người chỉ truy cập thư mục mang user id của mình
insert into storage.buckets (id, name, public) values ('ocr-images', 'ocr-images', false)
on conflict (id) do nothing;

create policy "ocr images read own" on storage.objects for select to authenticated
  using (bucket_id = 'ocr-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "ocr images write own" on storage.objects for insert to authenticated
  with check (bucket_id = 'ocr-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "ocr images delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'ocr-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- Tiêu đề do người dùng đặt; index cho danh sách lịch sử
alter table public.ocr_records add column title text;
create index ocr_records_user_created_idx on public.ocr_records (user_id, created_at desc);
