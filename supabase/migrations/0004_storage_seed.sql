-- Cadet Sync · 0004 · storage buckets, storage policies, seed data
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('covers',         'covers',         true,  3145728,  array['image/jpeg','image/png','image/webp']),
  ('qr',             'qr',             true,  2097152,  array['image/jpeg','image/png','image/webp']),
  ('note-pdfs',      'note-pdfs',      false, 26214400, array['application/pdf']),
  ('payment-proofs', 'payment-proofs', false, 5242880,  array['image/jpeg','image/png','image/webp']),
  ('id-cards',       'id-cards',       false, 5242880,  array['image/jpeg','image/png','image/webp']),
  ('payout-proofs',  'payout-proofs',  false, 5242880,  array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Convention: object path = '<user uuid>/<filename>'. No UPDATE/DELETE policies for proofs: evidence is immutable.
create policy "covers read"        on storage.objects for select using (bucket_id = 'covers');
create policy "covers write"       on storage.objects for insert to authenticated with check (bucket_id = 'covers' and (storage.foldername(name))[1] = auth.uid()::text and is_teaching_cadet());
create policy "qr read"            on storage.objects for select using (bucket_id = 'qr');
create policy "qr admin"           on storage.objects for all to authenticated using (bucket_id = 'qr' and is_admin()) with check (bucket_id = 'qr' and is_admin());
create policy "pdf insert"         on storage.objects for insert to authenticated with check (bucket_id = 'note-pdfs' and (storage.foldername(name))[1] = auth.uid()::text and is_teaching_cadet());
-- Buyers have NO storage read policy on note-pdfs; they get 60-second signed URLs from the server route after user_can_access_note().
create policy "pdf author/admin"   on storage.objects for select to authenticated using (bucket_id = 'note-pdfs' and ((storage.foldername(name))[1] = auth.uid()::text or is_admin()));
create policy "proof insert"       on storage.objects for insert to authenticated with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text and is_active_user());
create policy "proof read"         on storage.objects for select to authenticated using (bucket_id = 'payment-proofs' and ((storage.foldername(name))[1] = auth.uid()::text or is_admin()));
create policy "idcard insert"      on storage.objects for insert to authenticated with check (bucket_id = 'id-cards' and (storage.foldername(name))[1] = auth.uid()::text and is_active_user());
create policy "idcard read"        on storage.objects for select to authenticated using (bucket_id = 'id-cards' and ((storage.foldername(name))[1] = auth.uid()::text or is_admin()));
create policy "payout proof admin" on storage.objects for all to authenticated using (bucket_id = 'payout-proofs' and is_admin()) with check (bucket_id = 'payout-proofs' and is_admin());

-- Subjects
insert into subjects (name, slug, sort_order) values
  ('English','english',1), ('Bangla','bangla',2), ('Mathematics','mathematics',3), ('Physics','physics',4),
  ('Chemistry','chemistry',5), ('Biology','biology',6), ('ICT','ict',7),
  ('Bangladesh & Global Studies','bgs',8), ('General Knowledge','general-knowledge',9)
on conflict do nothing;

-- Starter college list (logo_path left empty on purpose). VERIFY this list against the official one and add logos from the owner's files.
insert into colleges (name) values
  ('Faujdarhat Cadet College'), ('Mirzapur Cadet College'), ('Jhenaidah Cadet College'), ('Rajshahi Cadet College'),
  ('Sylhet Cadet College'), ('Rangpur Cadet College'), ('Mymensingh Cadet College'), ('Barisal Cadet College'),
  ('Cumilla Cadet College'), ('Pabna Cadet College')
on conflict do nothing;

-- Admin-editable settings (validated and audited by triggers from 0002; numbers must be stored as JSON numbers, not strings).
-- Note: the seeded instruction text mentions ৳15; if you change publishing_fee_bdt, update that text too.
-- Admin-editable settings. bkash_number is intentionally EMPTY: checkout and publishing payment pages must refuse to render until the admin sets it.
insert into admin_settings (key, value, is_public) values
  ('publishing_fee_bdt', '15', true),
  ('commission_rate',    '0.10', true),
  ('bkash_number',       '""', true),
  ('bkash_qr_path',      'null', true),
  ('publishing_instructions', '["Open your bKash application.","Scan the official QR code or use the displayed payment number.","Send ৳15 to Cadet Sync.","Copy the Transaction ID.","Return to Cadet Sync.","Submit your Transaction ID and payment screenshot."]', true)
on conflict (key) do nothing;
