-- Cadet Sync · 0002 · helpers, guards, RLS
-- Functions created from here on are NOT callable by clients unless explicitly granted (see 0003 bottom).
-- (PostgreSQL gives PUBLIC execute on new functions by default; that default is global, so it must be revoked without IN SCHEMA.)
alter default privileges revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon, authenticated;
create or replace function is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin' and status = 'active');
$$;
create or replace function is_teaching_cadet() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role in ('teaching_cadet','admin') and status = 'active');
$$;
create or replace function is_active_user() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'active');
$$;
-- Trusted = SQL editor / service role (no JWT), a workflow function that set the flag, or an admin.
create or replace function is_trusted() returns boolean language sql stable as $$
  select auth.uid() is null or coalesce(current_setting('app.internal', true), '') = 'on' or is_admin();
$$;
create or replace function get_setting(p_key text) returns jsonb language sql stable security definer set search_path = public as $$
  select value from admin_settings where key = p_key;
$$;
create or replace function audit(p_action text, p_entity text, p_entity_id uuid, p_before jsonb, p_after jsonb)
returns void language sql security definer set search_path = public as $$
  insert into audit_logs(actor_id, action, entity, entity_id, before_data, after_data)
  values (auth.uid(), p_action, p_entity, p_entity_id, p_before, p_after);
$$;
create or replace function notify(p_user uuid, p_type text, p_title text, p_body text, p_link text)
returns void language sql security definer set search_path = public as $$
  insert into notifications(user_id, type, title, body, link) values (p_user, p_type, p_title, p_body, p_link);
$$;
create or replace function notify_admins(p_type text, p_title text, p_body text, p_link text)
returns void language sql security definer set search_path = public as $$
  insert into notifications(user_id, type, title, body, link)
  select id, p_type, p_title, p_body, p_link from profiles where role = 'admin' and status = 'active';
$$;

-- Audit log is append-only.
create or replace function audit_immutable() returns trigger language plpgsql as $$
begin raise exception 'audit_logs is append-only'; end $$;
create trigger audit_no_update before update or delete on audit_logs for each row execute function audit_immutable();
create trigger audit_no_truncate before truncate on audit_logs for each statement execute function audit_immutable();

-- New auth user -> student profile. Role is NEVER taken from client metadata.
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
declare cid int; cad text;
begin
  -- Signup metadata is client-controlled: parse defensively so bad input can never break signup or pick a role.
  cid := case when new.raw_user_meta_data->>'college_id' ~ '^[0-9]{1,9}$' then (new.raw_user_meta_data->>'college_id')::int end;
  if cid is not null and not exists (select 1 from colleges where id = cid) then cid := null; end if;
  cad := nullif(left(trim(coalesce(new.raw_user_meta_data->>'cadet_id', '')), 32), '');
  if cid is not null and cad is not null and exists (select 1 from profiles where college_id = cid and cadet_id = cad) then
    cad := null;   -- already claimed by someone else; admin verification of the ID card resolves ownership
  end if;
  insert into profiles (id, full_name, email, phone, college_id, cadet_id)
  values (new.id,
          left(coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), split_part(new.email, '@', 1)), 120),
          new.email, left(new.raw_user_meta_data->>'phone', 20), cid, cad);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- Guards: users cannot self-promote or touch system-managed columns.
create or replace function guard_profiles() returns trigger language plpgsql as $$
begin
  if not is_trusted() then
    new.role := old.role; new.status := old.status; new.verification := old.verification; new.email := old.email;
    if old.verification = 'verified' then   -- verified identity cannot be edited by the user; contact an admin
      new.college_id := old.college_id; new.cadet_id := old.cadet_id; new.id_card_path := old.id_card_path; new.full_name := old.full_name;
    end if;
  end if;
  return new;
end $$;
create trigger guard_profiles before update on profiles for each row execute function guard_profiles();

create or replace function guard_notes() returns trigger language plpgsql as $$
begin
  if not is_trusted() then
    new.status := old.status; new.author_id := old.author_id; new.avg_rating := old.avg_rating;
    new.rating_count := old.rating_count; new.sales_count := old.sales_count;
    new.published_at := old.published_at; new.rejection_reason := old.rejection_reason;
    -- Price, file and payout number are frozen while the note is in review, published or suspended.
    -- (Stops "approve cheap, edit later" and payout-number swapping. An admin can change them if there is a real reason.)
    if old.status in ('pending_review','approved','suspended')
       and (new.price_bdt <> old.price_bdt or new.pdf_path is distinct from old.pdf_path
            or new.author_bkash is distinct from old.author_bkash) then
      raise exception 'note_locked: price, PDF and payout number cannot change while the note is in review, published or suspended';
    end if;
  end if;
  return new;
end $$;
create trigger guard_notes before update on notes for each row execute function guard_notes();

create or replace function refresh_note_rating() returns trigger language plpgsql security definer set search_path = public as $$
declare n uuid := coalesce(new.note_id, old.note_id);
begin
  perform set_config('app.internal','on',true);
  update notes set avg_rating = coalesce((select round(avg(rating),2) from reviews where note_id = n),0),
                   rating_count = (select count(*) from reviews where note_id = n) where id = n;
  return null;
end $$;
create trigger reviews_rating after insert or update or delete on reviews for each row execute function refresh_note_rating();

-- Access check used by the download route (call with the USER's JWT, not the service role).
create or replace function user_can_access_note(p_note_id uuid) returns boolean language sql stable security definer set search_path = public as $$
  select is_active_user() and exists (
    select 1 from notes n where n.id = p_note_id and (
      is_admin()
      or n.author_id = auth.uid()
      or (n.status = 'approved' and n.is_free)
      -- Paid notes: the entitlement row (created when the admin verifies the buyer's payment) is the ONLY key.
      or (n.status in ('approved','suspended') and exists (
            select 1 from purchase_entitlements e where e.buyer_id = auth.uid() and e.note_id = n.id))
    ));
$$;

create or replace function public_stats() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'notes',           (select count(*) from notes where status = 'approved'),
    'active_cadets',   (select count(*) from profiles where status = 'active' and role in ('student','teaching_cadet')),
    'teaching_cadets', (select count(*) from profiles where role = 'teaching_cadet' and status = 'active'),
    'avg_rating',      (select round(avg(rating),1) from reviews));
$$;


-- Financial fields of an order never change after creation. The only exception is a price refresh on an order that has
-- not been paid yet (create_order sets app.internal for that).
create or replace function guard_orders() returns trigger language plpgsql as $$
begin
  if (new.buyer_id, new.note_id, new.author_id, new.price_bdt, new.commission_rate, new.commission_bdt, new.author_share_bdt)
     is distinct from
     (old.buyer_id, old.note_id, old.author_id, old.price_bdt, old.commission_rate, old.commission_bdt, old.author_share_bdt) then
    if not (old.status in ('payment_awaiting','payment_rejected') and coalesce(current_setting('app.internal', true), '') = 'on') then
      raise exception 'order_financials_immutable';
    end if;
  end if;
  return new;
end $$;
create trigger guard_orders before update on orders for each row execute function guard_orders();

-- Money records are never deleted (even by the service role or the SQL editor).
create or replace function forbid_delete() returns trigger language plpgsql as $$
begin raise exception '% rows cannot be deleted', tg_table_name; end $$;
create trigger no_delete before delete on orders                    for each row execute function forbid_delete();
create trigger no_delete before delete on buyer_payment_submissions for each row execute function forbid_delete();
create trigger no_delete before delete on seller_payouts            for each row execute function forbid_delete();
create trigger no_delete before delete on payment_trx_claims        for each row execute function forbid_delete();

-- Deleting a note must never take a submitted publishing-fee record with it (ON DELETE CASCADE would).
create or replace function guard_note_delete() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from publishing_payments where note_id = old.id and status <> 'awaiting_payment') then
    raise exception 'note_has_payment_record';
  end if;
  return old;
end $$;
create trigger guard_note_delete before delete on notes for each row execute function guard_note_delete();

-- Settings control where real money is sent, so they are validated and every change is audited.
create or replace function validate_setting() returns trigger language plpgsql as $$
declare v jsonb := new.value;
begin
  if new.key = 'commission_rate' then
    if jsonb_typeof(v) <> 'number' then raise exception 'commission_rate must be a number'; end if;
    if (v #>> '{}')::numeric < 0 or (v #>> '{}')::numeric > 0.5 then raise exception 'commission_rate must be between 0 and 0.5'; end if;
  elsif new.key = 'publishing_fee_bdt' then
    if jsonb_typeof(v) <> 'number' then raise exception 'publishing_fee_bdt must be a number'; end if;
    if (v #>> '{}')::numeric <= 0 or (v #>> '{}')::numeric > 1000 then raise exception 'publishing_fee_bdt must be between 1 and 1000'; end if;
  elsif new.key = 'bkash_number' then
    if jsonb_typeof(v) <> 'string' then raise exception 'bkash_number must be text'; end if;
    if (v #>> '{}') <> '' and (v #>> '{}') !~ '^01[3-9][0-9]{8}$' then raise exception 'bkash_number must look like 01XXXXXXXXX'; end if;
  elsif new.key = 'bkash_qr_path' then
    if jsonb_typeof(v) not in ('string','null') then raise exception 'bkash_qr_path must be text or null'; end if;
  elsif new.key = 'publishing_instructions' then
    if jsonb_typeof(v) <> 'array' then raise exception 'publishing_instructions must be a list'; end if;
  end if;
  new.updated_at := now(); new.updated_by := auth.uid();
  return new;
end $$;
create trigger validate_setting before insert or update on admin_settings for each row execute function validate_setting();

create or replace function audit_setting() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform audit('setting_changed', 'setting', null,
                case when tg_op = 'UPDATE' then jsonb_build_object('key', old.key, 'value', old.value) end,
                jsonb_build_object('key', new.key, 'value', new.value));
  return null;
end $$;
create trigger audit_setting after insert or update on admin_settings for each row execute function audit_setting();

-- RLS everywhere. Money tables get NO client write policies: writes happen only inside workflow functions.
do $$ declare t text; begin
  foreach t in array array['colleges','subjects','profiles','teaching_cadet_applications','notes','publishing_payments','orders',
    'buyer_payment_submissions','seller_payouts','purchase_entitlements','notifications','wishlists','cart_items','courses',
    'course_materials','reviews','reports','admin_settings','audit_logs','payment_trx_claims'] loop
    execute format('alter table %I enable row level security', t);
  end loop; end $$;

create policy ref_read_colleges on colleges for select using (true);
create policy ref_read_subjects on subjects for select using (true);
create policy ref_admin_colleges on colleges for all using (is_admin()) with check (is_admin());
create policy ref_admin_subjects on subjects for all using (is_admin()) with check (is_admin());

create policy profiles_read   on profiles for select using (id = auth.uid() or is_admin());
create policy profiles_update on profiles for update using (id = auth.uid() or is_admin()) with check (id = auth.uid() or is_admin());
create view public_authors as
  select id, full_name, college_id, avatar_path, verification from profiles
  where role = 'teaching_cadet' and status = 'active' and verification = 'verified';
grant select on public_authors to anon, authenticated;

create policy apps_read   on teaching_cadet_applications for select using (user_id = auth.uid() or is_admin());
create policy apps_insert on teaching_cadet_applications for insert with check (user_id = auth.uid() and status = 'pending' and is_active_user());
-- Approval/rejection goes ONLY through review_teaching_cadet_application() so role and application status cannot disagree.
revoke insert, update, delete on teaching_cadet_applications from anon, authenticated;
grant insert (user_id, current_class, academic_performance, previous_results, document_paths) on teaching_cadet_applications to authenticated;

create policy notes_read   on notes for select using (status = 'approved' or author_id = auth.uid() or is_admin());
create policy notes_insert on notes for insert with check (author_id = auth.uid() and is_teaching_cadet() and status = 'draft');
create policy notes_update on notes for update using ((author_id = auth.uid() and is_teaching_cadet()) or is_admin());
create policy notes_delete on notes for delete using ((author_id = auth.uid() and is_teaching_cadet() and status in ('draft','rejected')) or is_admin());
-- pdf_path is hidden from clients; the server reads it with the service role after an entitlement check.
revoke all on notes from anon, authenticated;
grant select (id,author_id,subject_id,class_level,title,description,price_bdt,is_free,cover_path,page_count,preview_pages,status,
              rejection_reason,published_at,avg_rating,rating_count,sales_count,created_at) on notes to anon, authenticated;
grant insert (author_id,subject_id,class_level,title,description,price_bdt,cover_path,pdf_path,page_count,preview_pages,author_bkash) on notes to authenticated;
grant update (subject_id,class_level,title,description,price_bdt,cover_path,pdf_path,page_count,preview_pages,author_bkash) on notes to authenticated;
grant delete on notes to authenticated;

create policy pubpay_read    on publishing_payments       for select using (author_id = auth.uid() or is_admin());
create policy orders_read    on orders                    for select using (buyer_id = auth.uid() or is_admin());
create policy buyerpay_read  on buyer_payment_submissions for select using (buyer_id = auth.uid() or is_admin());
create policy payouts_admin  on seller_payouts            for select using (is_admin());
create policy entitle_read   on purchase_entitlements     for select using (buyer_id = auth.uid() or is_admin());

-- Authors see their sales only through this view: no buyer identity, no screenshots.
create view author_sales as
  select o.order_no, o.note_id, o.price_bdt as gross_bdt, o.commission_bdt, o.author_share_bdt,
         o.payment_verified_at, o.completed_at, p.status as payout_status,
         p.payout_trx_id, p.paid_on, p.amount_paid_bdt
  from orders o join seller_payouts p on p.order_id = o.id
  where o.author_id = auth.uid() and o.status in ('seller_payout_pending','completed');
grant select on author_sales to authenticated;

create policy notif_read on notifications for select using (user_id = auth.uid());
create policy notif_mark on notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke update on notifications from authenticated;
grant update (read_at) on notifications to authenticated;

create policy wish_own on wishlists  for all using (user_id = auth.uid())
  with check (user_id = auth.uid() and is_active_user() and exists (select 1 from notes n where n.id = wishlists.note_id and n.status = 'approved'));
create policy cart_own on cart_items for all using (user_id = auth.uid())
  with check (user_id = auth.uid() and is_active_user() and exists (select 1 from notes n where n.id = cart_items.note_id and n.status = 'approved'));

create policy courses_read  on courses for select using (is_published or author_id = auth.uid() or is_admin());
create policy courses_write on courses for all
  using ((author_id = auth.uid() and is_teaching_cadet()) or is_admin())
  with check ((author_id = auth.uid() and is_teaching_cadet()) or is_admin());
create policy cmat_read  on course_materials for select using (exists (select 1 from courses c where c.id = course_id and (c.is_published or c.author_id = auth.uid() or is_admin())));
create policy cmat_write on course_materials for all using (exists (select 1 from courses c where c.id = course_id and (c.author_id = auth.uid() or is_admin())));

create policy reviews_read  on reviews for select using (true);
create policy reviews_write on reviews for insert with check (user_id = auth.uid() and is_active_user() and (
  exists (select 1 from purchase_entitlements e where e.buyer_id = auth.uid() and e.note_id = reviews.note_id)
  or exists (select 1 from notes n where n.id = reviews.note_id and n.is_free and n.status = 'approved' and n.author_id <> auth.uid())));
-- Only rating/comment are editable: a review cannot be re-pointed at a note the user never bought.
create policy reviews_edit  on reviews for update using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke update on reviews from anon, authenticated;
grant update (rating, comment) on reviews to authenticated;
create policy reports_insert on reports for insert with check (reporter_id = auth.uid() and is_active_user());
create policy reports_read   on reports for select using (reporter_id = auth.uid() or is_admin());
create policy reports_admin  on reports for update using (is_admin());

create policy settings_read  on admin_settings for select using (is_public or is_admin());
create policy settings_admin on admin_settings for all using (is_admin()) with check (is_admin());
create policy audit_admin    on audit_logs for select using (is_admin());
create policy claims_admin   on payment_trx_claims for select using (is_admin());

-- Belt and braces: money tables are writable ONLY through the workflow functions, whatever the default grants are.
revoke insert, update, delete on publishing_payments, orders, buyer_payment_submissions, seller_payouts,
                                 purchase_entitlements, payment_trx_claims from anon, authenticated;
revoke insert, update, delete, truncate on audit_logs from anon, authenticated;
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;   -- TRUNCATE ignores RLS
revoke all on author_sales from anon;
