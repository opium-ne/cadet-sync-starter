-- Cadet Sync · 0003 · manual payment workflows
--
-- PAYMENT RULE (Option B)
--   Admin verifies the buyer's bKash payment  ->  buyer gets access IMMEDIATELY (purchase_entitlements row),
--   sales_count +1, and a seller payout row is created as PENDING (author 90% / platform 10%).
--   Admin pays the author later and records it  ->  order becomes 'completed'. Nothing is unlocked or counted again.
--
-- Every status/money change happens inside ONE of these functions, in ONE transaction, with row locks.
-- Lock order is always: order -> (submission | payout) so two admins clicking at once cannot deadlock or double-process.
-- Admin functions must be called with the ADMIN'S OWN JWT (not the service role) so audit_logs.actor_id is the real admin.

---------------------------------------------------------------- internal helpers (not callable by clients)
create or replace function setting_numeric(p_key text) returns numeric language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  select value into v from admin_settings where key = p_key;
  if v is null or jsonb_typeof(v) <> 'number' then raise exception 'setting_missing: %', p_key; end if;
  return (v #>> '{}')::numeric;
end $$;

create or replace function require_payment_config() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(get_setting('bkash_number') #>> '{}', '') = '' then raise exception 'bkash_not_configured'; end if;
end $$;

create or replace function normalize_trx(p text) returns text language plpgsql immutable as $$
declare t text := upper(trim(coalesce(p, '')));
begin
  if t !~ '^[A-Z0-9]{8,14}$' then raise exception 'invalid_trx_format'; end if;
  return t;
end $$;

-- Race-free duplicate detection: the unique index on payment_trx_claims decides, not a read-then-write check.
-- Returns false if the TrxID is already active anywhere (publishing fee, buyer payment OR seller payout).
create or replace function claim_trx(p_trx text, p_kind text, p_ref uuid) returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into payment_trx_claims (trx_id, kind, ref_id) values (p_trx, p_kind, p_ref)
  on conflict (trx_id) where status = 'active' do nothing;
  get diagnostics n = row_count;
  return n = 1;
end $$;

create or replace function release_trx(p_kind text, p_ref uuid) returns void language sql security definer set search_path = public as $$
  update payment_trx_claims set status = 'released', released_at = now() where kind = p_kind and ref_id = p_ref and status = 'active';
$$;

-- Commission is rounded half-up to the paisa; the author receives the remainder, so the two always add up exactly.
create or replace function calc_split(p_price numeric, p_rate numeric)
returns table (commission numeric, author_share numeric) language sql immutable as $$
  select round(p_price * p_rate, 2), p_price - round(p_price * p_rate, 2);
$$;

---------------------------------------------------------------- publishing fee (৳15, per note)
create or replace function start_publishing_payment(p_note_id uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare n notes%rowtype; pp uuid;
begin
  if not is_teaching_cadet() then raise exception 'forbidden'; end if;
  perform require_payment_config();
  select * into n from notes where id = p_note_id and author_id = auth.uid();
  if not found then raise exception 'not_found'; end if;
  if n.status <> 'draft' then raise exception 'note_not_draft'; end if;
  insert into publishing_payments (note_id, author_id, fee_bdt)
  values (n.id, n.author_id, setting_numeric('publishing_fee_bdt'))
  on conflict (note_id) do nothing returning id into pp;
  if pp is null then select id into pp from publishing_payments where note_id = n.id; end if;
  return pp;
end $$;

create or replace function submit_publishing_payment(p_note_id uuid, p_trx_id text, p_screenshot_path text)
returns text language plpgsql security definer set search_path = public as $$
declare pp publishing_payments%rowtype; t text;
begin
  if not is_teaching_cadet() then raise exception 'forbidden'; end if;
  t := normalize_trx(p_trx_id);
  select * into pp from publishing_payments where note_id = p_note_id and author_id = auth.uid() for update;
  if not found then raise exception 'not_found'; end if;
  if pp.status not in ('awaiting_payment','rejected') then raise exception 'not_payable'; end if;
  if not exists (select 1 from notes where id = p_note_id and status = 'draft') then raise exception 'note_not_draft'; end if;
  if split_part(p_screenshot_path, '/', 1) <> auth.uid()::text then raise exception 'bad_upload_path'; end if;
  if not claim_trx(t, 'publishing', pp.id) then
    perform audit('duplicate_trx_attempt', 'publishing_payment', pp.id, null, jsonb_build_object('trx_id', t));
    perform notify_admins('duplicate_trx', 'Duplicate Transaction ID', 'A publishing fee claim reused ' || t, '/admin/publishing-payments');
    return 'duplicate_trx';
  end if;
  update publishing_payments set status = 'payment_submitted', trx_id = t, screenshot_path = p_screenshot_path,
         submitted_at = now(), rejection_reason = null, reviewed_by = null, reviewed_at = null where id = pp.id;
  perform audit('publishing_payment_submitted', 'publishing_payment', pp.id, jsonb_build_object('status', pp.status), jsonb_build_object('trx_id', t));
  perform notify_admins('publishing_payment', 'New publishing fee claim', 'Transaction ' || t, '/admin/publishing-payments');
  return 'ok';
end $$;

create or replace function admin_review_publishing_payment(p_id uuid, p_approve boolean, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare pp publishing_payments%rowtype;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  perform set_config('app.internal', 'on', true);
  select * into pp from publishing_payments where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if pp.status not in ('payment_submitted','under_verification') then raise exception 'already_reviewed'; end if;
  if p_approve then
    update publishing_payments set status = 'verified', reviewed_by = auth.uid(), reviewed_at = now() where id = pp.id;
    update notes set status = 'pending_review' where id = pp.note_id and status = 'draft';   -- enters moderation; NOT published
    perform notify(pp.author_id, 'publishing_approved', 'Publishing fee confirmed', 'Your note is now in review.', '/teaching/notes');
    perform notify_admins('note_submitted', 'Note ready for review', null, '/admin/notes');
  else
    if coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
    update publishing_payments set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), rejection_reason = p_reason where id = pp.id;
    perform release_trx('publishing', pp.id);                                                 -- author may submit a corrected claim
    perform notify(pp.author_id, 'publishing_rejected', 'Publishing payment rejected', p_reason, '/teaching/notes');
  end if;
  perform audit(case when p_approve then 'publishing_payment_approved' else 'publishing_payment_rejected' end,
                'publishing_payment', pp.id, jsonb_build_object('status', pp.status), jsonb_build_object('trx_id', pp.trx_id, 'reason', p_reason));
end $$;

create or replace function admin_moderate_note(p_note_id uuid, p_decision text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare n notes%rowtype;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  perform set_config('app.internal', 'on', true);
  select * into n from notes where id = p_note_id for update;
  if not found then raise exception 'not_found'; end if;
  if p_decision = 'approve' then
    if n.status not in ('pending_review','suspended') then raise exception 'bad_note_state'; end if;
    if not exists (select 1 from publishing_payments where note_id = n.id and status = 'verified') then raise exception 'publishing_fee_not_verified'; end if;
    update notes set status = 'approved', published_at = coalesce(published_at, now()), rejection_reason = null where id = n.id;
    perform notify(n.author_id, 'note_approved', 'Note published', n.title, '/notes/' || n.id);
  elsif p_decision = 'reject' then
    if n.status <> 'pending_review' then raise exception 'bad_note_state'; end if;
    if coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
    update notes set status = 'rejected', rejection_reason = p_reason where id = n.id;
    perform notify(n.author_id, 'note_rejected', 'Note rejected', p_reason, '/teaching/notes');
  elsif p_decision = 'suspend' then
    if n.status <> 'approved' then raise exception 'bad_note_state'; end if;
    if coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
    update notes set status = 'suspended', rejection_reason = p_reason where id = n.id;
    perform notify(n.author_id, 'note_suspended', 'Note suspended', p_reason, '/teaching/notes');
  else raise exception 'bad_decision'; end if;
  perform audit('note_' || p_decision, 'note', n.id, jsonb_build_object('status', n.status), jsonb_build_object('reason', p_reason));
end $$;

-- After a moderation rejection the fee stays paid; the author fixes the note and re-submits for review.
create or replace function resubmit_note(p_note_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_teaching_cadet() then raise exception 'forbidden'; end if;
  perform set_config('app.internal', 'on', true);
  update notes set status = 'pending_review', rejection_reason = null
   where id = p_note_id and author_id = auth.uid() and status = 'rejected'
     and exists (select 1 from publishing_payments where note_id = p_note_id and status = 'verified');
  if not found then raise exception 'cannot_resubmit'; end if;
  perform notify_admins('note_submitted', 'Note re-submitted for review', null, '/admin/notes');
end $$;

---------------------------------------------------------------- buyer purchase
create or replace function create_order(p_note_id uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare n notes%rowtype; o orders%rowtype; oid uuid; rate numeric; s record;
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if not is_active_user() then raise exception 'account_not_active'; end if;
  perform require_payment_config();
  select * into n from notes where id = p_note_id and status = 'approved';
  if not found then raise exception 'note_unavailable'; end if;
  if n.is_free then raise exception 'note_is_free'; end if;
  if n.author_id = auth.uid() then raise exception 'own_note'; end if;
  if exists (select 1 from purchase_entitlements where buyer_id = auth.uid() and note_id = n.id) then raise exception 'already_owned'; end if;
  rate := setting_numeric('commission_rate');
  if rate < 0 or rate > 0.5 then raise exception 'bad_commission_rate'; end if;
  select * into s from calc_split(n.price_bdt, rate);

  insert into orders (buyer_id, note_id, author_id, price_bdt, commission_rate, commission_bdt, author_share_bdt)
  values (auth.uid(), n.id, n.author_id, n.price_bdt, rate, s.commission, s.author_share)
  on conflict (buyer_id, note_id) do nothing returning id into oid;
  if oid is not null then return oid; end if;

  -- Order already exists. If it is still unpaid and the price changed meanwhile, refresh the frozen amounts.
  select * into o from orders where buyer_id = auth.uid() and note_id = n.id for update;
  if o.status in ('payment_awaiting','payment_rejected') and (o.price_bdt <> n.price_bdt or o.commission_rate <> rate) then
    perform set_config('app.internal', 'on', true);
    update orders set price_bdt = n.price_bdt, commission_rate = rate,
           commission_bdt = s.commission, author_share_bdt = s.author_share where id = o.id;
  end if;
  return o.id;
end $$;

create or replace function submit_buyer_payment(p_order_id uuid, p_trx_id text, p_screenshot_path text, p_confirmed boolean)
returns text language plpgsql security definer set search_path = public as $$
declare o orders%rowtype; n notes%rowtype; t text; sid uuid := gen_random_uuid();
begin
  if not is_active_user() then raise exception 'account_not_active'; end if;
  t := normalize_trx(p_trx_id);
  select * into o from orders where id = p_order_id and buyer_id = auth.uid() for update;
  if not found then raise exception 'order_not_found'; end if;
  if o.status not in ('payment_awaiting','payment_rejected') then raise exception 'order_not_payable'; end if;
  if not coalesce(p_confirmed, false) then raise exception 'confirmation_required'; end if;
  select * into n from notes where id = o.note_id;
  if n.status <> 'approved' then raise exception 'note_unavailable'; end if;
  if n.price_bdt <> o.price_bdt then raise exception 'price_changed'; end if;      -- buyer must reopen checkout (create_order refreshes the order)
  if split_part(p_screenshot_path, '/', 1) <> auth.uid()::text then raise exception 'bad_upload_path'; end if;
  if not claim_trx(t, 'buyer', sid) then
    perform audit('duplicate_trx_attempt', 'order', o.id, null, jsonb_build_object('trx_id', t));
    perform notify_admins('duplicate_trx', 'Duplicate Transaction ID', 'Order ' || o.order_no || ' reused ' || t, '/admin/buyer-payments');
    return 'duplicate_trx';
  end if;
  insert into buyer_payment_submissions (id, order_id, buyer_id, amount_bdt, trx_id, screenshot_path, confirmed_checkbox)
  values (sid, o.id, o.buyer_id, o.price_bdt, t, p_screenshot_path, true);
  update orders set status = 'payment_submitted' where id = o.id;
  perform audit('buyer_payment_submitted', 'order', o.id, jsonb_build_object('status', o.status), jsonb_build_object('trx_id', t));
  perform notify(o.buyer_id, 'purchase_submitted', 'Payment submitted', 'Order ' || o.order_no || ' is waiting for admin verification. The note unlocks as soon as your payment is verified.', '/dashboard/purchases');
  perform notify_admins('buyer_payment', 'New buyer payment', 'Order ' || o.order_no || ' · ৳' || o.price_bdt, '/admin/buyer-payments');
  return 'ok';
end $$;

create or replace function admin_start_review(p_kind text, p_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  if p_kind = 'buyer' then
    update orders set status = 'under_verification'
     where status = 'payment_submitted' and id = (select order_id from buyer_payment_submissions where id = p_id and status = 'pending');
  elsif p_kind = 'publishing' then
    update publishing_payments set status = 'under_verification' where id = p_id and status = 'payment_submitted';
  else raise exception 'bad_kind'; end if;
  perform audit('review_started', p_kind, p_id, null, null);
end $$;

create or replace function admin_reject_buyer_payment(p_submission_id uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare s buyer_payment_submissions%rowtype; o orders%rowtype; v_order uuid;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
  select order_id into v_order from buyer_payment_submissions where id = p_submission_id;
  if not found then raise exception 'not_found'; end if;
  select * into o from orders where id = v_order for update;                                  -- order first, always
  select * into s from buyer_payment_submissions where id = p_submission_id for update;
  if s.status <> 'pending' then raise exception 'already_reviewed'; end if;
  update buyer_payment_submissions set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), rejection_reason = p_reason where id = s.id;
  update orders set status = 'payment_rejected' where id = o.id;                              -- no entitlement exists, so nothing to unlock or revoke
  perform release_trx('buyer', s.id);                                                         -- buyer may submit a corrected claim
  perform notify(o.buyer_id, 'payment_rejected', 'Payment rejected', p_reason, '/dashboard/purchases');
  perform audit('buyer_payment_rejected', 'order', o.id, jsonb_build_object('status', o.status), jsonb_build_object('trx_id', s.trx_id, 'reason', p_reason));
end $$;

-- OPTION B: the admin has confirmed in the real bKash account that the money arrived.
-- ONE transaction: submission -> verified, order -> seller_payout_pending, payout row (pending, 90%), ENTITLEMENT, sales_count +1.
-- If any statement fails (e.g. a unique constraint), everything rolls back and nothing is half-done.
create or replace function admin_verify_buyer_payment(p_submission_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare s buyer_payment_submissions%rowtype; o orders%rowtype; v_order uuid; v_title text;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  perform set_config('app.internal', 'on', true);                                             -- lets this function bump notes.sales_count
  select order_id into v_order from buyer_payment_submissions where id = p_submission_id;
  if not found then raise exception 'not_found'; end if;
  select * into o from orders where id = v_order for update;                                  -- order first, always
  select * into s from buyer_payment_submissions where id = p_submission_id for update;
  if s.status <> 'pending' then raise exception 'already_reviewed'; end if;
  if o.status not in ('payment_submitted','under_verification') then raise exception 'bad_order_state'; end if;

  update buyer_payment_submissions set status = 'verified', reviewed_by = auth.uid(), reviewed_at = now() where id = s.id;
  update orders set status = 'seller_payout_pending', payment_verified_at = now() where id = o.id;
  insert into seller_payouts (order_id, author_id, amount_due_bdt) values (o.id, o.author_id, o.author_share_bdt);   -- UNIQUE(order_id)
  insert into purchase_entitlements (buyer_id, note_id, order_id) values (o.buyer_id, o.note_id, o.id);            -- UNIQUE(order_id), UNIQUE(buyer,note)
  update notes set sales_count = sales_count + 1 where id = o.note_id returning title into v_title;                 -- counted exactly once, here

  perform notify(o.buyer_id, 'payment_verified', 'Payment verified — your note is unlocked',
                 'Your payment for "' || v_title || '" (order ' || o.order_no || ') is verified. The note is now available in your library.',
                 '/dashboard/library');
  perform notify(o.author_id, 'sale_verified', 'New sale — buyer payment verified',
                 'Order ' || o.order_no || ' · ৳' || o.price_bdt || ' sale of "' || v_title || '". Your share ৳' || o.author_share_bdt
                 || ' is pending payout; Cadet Sync keeps ৳' || o.commission_bdt || '.', '/teaching/earnings');
  perform notify_admins('payout_pending', 'Seller payout awaiting', 'Order ' || o.order_no || ' · pay ৳' || o.author_share_bdt, '/admin/seller-payouts');
  perform audit('buyer_payment_verified', 'order', o.id, jsonb_build_object('status', o.status),
                jsonb_build_object('status', 'seller_payout_pending', 'trx_id', s.trx_id, 'gross', o.price_bdt,
                                   'commission', o.commission_bdt, 'author_share', o.author_share_bdt, 'entitlement_granted', true));
end $$;

-- The admin has manually sent the author's share by bKash and records it. Access was ALREADY granted at verification,
-- so this function deliberately creates no entitlement, changes no sales_count and notifies no buyer.
create or replace function admin_confirm_seller_payout(
  p_order_id uuid, p_payout_trx_id text, p_amount numeric, p_paid_on date, p_proof_path text, p_remarks text)
returns void language plpgsql security definer set search_path = public as $$
declare o orders%rowtype; po seller_payouts%rowtype; t text; bk text;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  t := normalize_trx(p_payout_trx_id);
  select * into o from orders where id = p_order_id for update;
  if not found then raise exception 'not_found'; end if;
  if o.status <> 'seller_payout_pending' then raise exception 'bad_order_state'; end if;
  select * into po from seller_payouts where order_id = o.id for update;
  if po.status <> 'pending' then raise exception 'already_paid'; end if;
  if not exists (select 1 from purchase_entitlements where order_id = o.id) then raise exception 'entitlement_missing'; end if;  -- invariant check
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount'; end if;
  if p_amount <> po.amount_due_bdt and coalesce(trim(p_remarks), '') = '' then raise exception 'remarks_required_when_amount_differs'; end if;
  if p_paid_on is not null and p_paid_on > current_date + 1 then raise exception 'paid_on_in_future'; end if;
  select author_bkash into bk from notes where id = o.note_id;
  if bk is null then raise exception 'author_bkash_missing'; end if;
  if not claim_trx(t, 'payout', po.id) then raise exception 'duplicate_trx'; end if;           -- payout TrxID must also be globally unique

  update seller_payouts set status = 'completed', payout_trx_id = t, amount_paid_bdt = p_amount, paid_to_bkash = bk,
         paid_on = coalesce(p_paid_on, current_date), proof_path = p_proof_path, admin_remarks = p_remarks,
         confirmed_by = auth.uid(), confirmed_at = now() where id = po.id;
  update orders set status = 'completed', completed_at = now() where id = o.id;
  perform notify(o.author_id, 'payout_completed', 'Payout sent', '৳' || p_amount || ' sent to ' || bk || ' · TrxID ' || t, '/teaching/payouts');
  perform audit('seller_payout_confirmed', 'order', o.id, jsonb_build_object('status', o.status),
                jsonb_build_object('status', 'completed', 'payout_trx_id', t, 'amount_paid', p_amount, 'amount_due', po.amount_due_bdt, 'to', bk));
end $$;

---------------------------------------------------------------- Teaching Cadet applications
create or replace function review_teaching_cadet_application(p_id uuid, p_approve boolean, p_note text) returns void language plpgsql security definer set search_path = public as $$
declare a teaching_cadet_applications%rowtype;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  select * into a from teaching_cadet_applications where id = p_id for update;
  if not found or a.status <> 'pending' then raise exception 'already_reviewed'; end if;
  update teaching_cadet_applications set status = case when p_approve then 'approved'::application_status else 'rejected'::application_status end,
         review_note = p_note, reviewed_by = auth.uid(), reviewed_at = now() where id = a.id;
  if p_approve then update profiles set role = 'teaching_cadet', verification = 'verified' where id = a.user_id and role = 'student';
  else update profiles set verification = 'rejected' where id = a.user_id; end if;
  perform notify(a.user_id, 'application_reviewed', case when p_approve then 'You are a Teaching Cadet' else 'Application not approved' end, p_note, '/dashboard');
  perform audit('application_' || case when p_approve then 'approved' else 'rejected' end, 'application', a.id, null, jsonb_build_object('note', p_note));
end $$;

---------------------------------------------------------------- admin read model
-- Admins need the author's bKash number and the payout amounts in one place. notes.author_bkash is hidden from every client
-- (public notes are readable by anyone), so this view is the only door, and it returns rows only for admins.
create or replace view admin_payout_queue as
  select p.id as payout_id, p.order_id, o.order_no, o.note_id, n.title as note_title,
         o.author_id, pr.full_name as author_name, n.author_bkash,
         o.price_bdt as gross_bdt, o.commission_bdt, p.amount_due_bdt, p.status,
         o.payment_verified_at, p.payout_trx_id, p.amount_paid_bdt, p.paid_on, p.confirmed_at
  from seller_payouts p
  join orders o on o.id = p.order_id
  join notes n on n.id = o.note_id
  join profiles pr on pr.id = o.author_id
  where is_admin();
revoke all on admin_payout_queue from anon;
grant select on admin_payout_queue to authenticated;

---------------------------------------------------------------- privileges
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function is_admin(), is_teaching_cadet(), is_active_user(), is_trusted(), public_stats() to anon, authenticated;
grant execute on function user_can_access_note(uuid), start_publishing_payment(uuid), submit_publishing_payment(uuid,text,text),
  create_order(uuid), submit_buyer_payment(uuid,text,text,boolean), resubmit_note(uuid),
  admin_start_review(text,uuid), admin_review_publishing_payment(uuid,boolean,text), admin_moderate_note(uuid,text,text),
  admin_reject_buyer_payment(uuid,text), admin_verify_buyer_payment(uuid),
  admin_confirm_seller_payout(uuid,text,numeric,date,text,text), review_teaching_cadet_application(uuid,boolean,text)
  to authenticated;
-- Internal only (reachable solely from the functions above): audit, notify, notify_admins, get_setting, setting_numeric,
-- require_payment_config, normalize_trx, claim_trx, release_trx, calc_split.
