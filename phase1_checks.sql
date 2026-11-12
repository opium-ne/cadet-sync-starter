-- Cadet Sync · Phase 1 database checks   (NOT YET RUN by the author: written without access to PostgreSQL)
-- Updated for the search_path hardening pass: checks 10a-10j and 11a/11 are new.
--
-- HOW TO USE (beginner): Supabase dashboard -> SQL Editor -> New query -> paste this WHOLE file -> Run.
--   * Use a throw-away/test project, never your production project.
--   * Everything happens inside a transaction that ends with ROLLBACK, so nothing is saved.
--   * If a check fails you get a red error naming the check. If everything passes you see the final row "ALL CHECKS PASSED".
--   * Run migrations 0001-0004 first.  If the very first INSERT into auth.users fails, create three test users in
--     Authentication -> Users, then replace the UUIDs below with theirs (search & replace the 3 ids).
--
-- Fixed test ids:  admin ...000a   author ...00b1   buyer1 ...00c1   buyer2 ...00c2   note1 (approved, ৳100)   note2 (draft)

begin;

-- ======================================================= SETUP (runs as the SQL-editor user: no JWT, so guards trust it)
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'admin@test.invalid',  '{"full_name":"Test Admin"}'),
  ('aaaaaaaa-0000-0000-0000-0000000000b1', 'author@test.invalid', '{"full_name":"Test Author"}'),
  ('aaaaaaaa-0000-0000-0000-0000000000c1', 'buyer1@test.invalid', '{"full_name":"Test Buyer 1"}'),
  ('aaaaaaaa-0000-0000-0000-0000000000c2', 'buyer2@test.invalid', '{"full_name":"Test Buyer 2"}');

update profiles set role = 'admin' where id = 'aaaaaaaa-0000-0000-0000-00000000000a';
update profiles set role = 'teaching_cadet', verification = 'verified', bkash_number = '01711111111' where id = 'aaaaaaaa-0000-0000-0000-0000000000b1';
update admin_settings set value = '"01799999999"'::jsonb where key = 'bkash_number';

insert into notes (id, author_id, subject_id, class_level, title, price_bdt, author_bkash, status, published_at) values
  ('11111111-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-0000000000b1', (select id from subjects where slug = 'physics'), 10, 'Test Physics Notes', 100, '01711111111', 'approved', now()),
  ('11111111-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-0000000000b1', (select id from subjects where slug = 'physics'), 10, 'Draft Chemistry Notes', 50, '01711111111', 'draft', null);

-- ======================================================= 1. buyer1 buys note1 and submits a bKash payment
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  perform set_config('test.order1', create_order('11111111-0000-0000-0000-000000000001')::text, true);
  assert user_can_access_note('11111111-0000-0000-0000-000000000001') = false, 'CHECK 1a: buyer must NOT have access before payment is verified';
  assert submit_buyer_payment(current_setting('test.order1')::uuid, 'TRX0000001', 'aaaaaaaa-0000-0000-0000-0000000000c1/proof.png', true) = 'ok', 'CHECK 1b: payment submission should succeed';
  assert user_can_access_note('11111111-0000-0000-0000-000000000001') = false, 'CHECK 1c: submitting a screenshot must NOT unlock the note';
end $$;
reset role;
do $$ begin
  assert (select status from orders where id = current_setting('test.order1')::uuid) = 'payment_submitted', 'CHECK 1d: order should be payment_submitted';
  assert (select count(*) from purchase_entitlements) = 0, 'CHECK 1e: no entitlement may exist yet';
end $$;

-- ======================================================= 2. duplicate TrxID, same table (buyer2 reuses buyer1's TrxID)
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  perform set_config('test.order2', create_order('11111111-0000-0000-0000-000000000001')::text, true);
  assert submit_buyer_payment(current_setting('test.order2')::uuid, 'trx0000001', 'aaaaaaaa-0000-0000-0000-0000000000c2/p.png', true) = 'duplicate_trx', 'CHECK 2: reused TrxID (even in lower case) must be refused';
end $$;
reset role;
do $$ begin
  assert (select status from orders where id = current_setting('test.order2')::uuid) = 'payment_awaiting', 'CHECK 2b: refused claim must not change the order';
  assert exists (select 1 from audit_logs where action = 'duplicate_trx_attempt'), 'CHECK 2c: duplicate attempt must be in the audit log';
end $$;

-- ======================================================= 3. duplicate TrxID ACROSS tables (author reuses a buyer TrxID as a publishing-fee claim)
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  perform start_publishing_payment('11111111-0000-0000-0000-000000000002');
  assert submit_publishing_payment('11111111-0000-0000-0000-000000000002', 'TRX0000001', 'aaaaaaaa-0000-0000-0000-0000000000b1/fee.png') = 'duplicate_trx', 'CHECK 3: a buyer TrxID must not be accepted as a publishing fee TrxID';
end $$;
reset role;

-- ======================================================= 4. admin verifies buyer1's payment  -> OPTION B: access immediately
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
do $$ declare sid uuid; begin
  select id into sid from buyer_payment_submissions where order_id = current_setting('test.order1')::uuid;
  perform set_config('test.sub1', sid::text, true);
  perform admin_verify_buyer_payment(sid);
  assert (select status from orders where id = current_setting('test.order1')::uuid) = 'seller_payout_pending', 'CHECK 4a: order should be seller_payout_pending';
  assert (select count(*) from purchase_entitlements where order_id = current_setting('test.order1')::uuid) = 1, 'CHECK 4b: exactly one entitlement';
  assert (select sales_count from notes where id = '11111111-0000-0000-0000-000000000001') = 1, 'CHECK 4c: sales_count must be 1';
  assert (select amount_due_bdt from seller_payouts where order_id = current_setting('test.order1')::uuid) = 90, 'CHECK 4d: author share must be 90';
  assert (select status from seller_payouts where order_id = current_setting('test.order1')::uuid) = 'pending', 'CHECK 4e: payout must still be pending';
  assert (select commission_bdt from orders where id = current_setting('test.order1')::uuid) = 10, 'CHECK 4f: platform commission must be 10';
end $$;
-- verifying twice must fail
do $$ begin
  begin
    perform admin_verify_buyer_payment(current_setting('test.sub1')::uuid);
    raise exception 'NO_ERROR';
  exception when others then
    assert sqlerrm = 'already_reviewed', 'CHECK 4g: second verification must fail with already_reviewed, got: ' || sqlerrm;
  end;
end $$;
reset role;
do $$ begin
  assert exists (select 1 from notifications where user_id = 'aaaaaaaa-0000-0000-0000-0000000000c1' and type = 'payment_verified'
                 and body like '%is verified. The note is now available in your library.%'), 'CHECK 4h: buyer notification must say verified + in library';
end $$;

-- ======================================================= 5. buyer1 now has access; and cannot cheat
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  assert user_can_access_note('11111111-0000-0000-0000-000000000001') = true, 'CHECK 5a: buyer must have access right after verification';
  -- cannot promote self
  update profiles set role = 'admin' where id = 'aaaaaaaa-0000-0000-0000-0000000000c1';
  assert (select role from profiles where id = 'aaaaaaaa-0000-0000-0000-0000000000c1') = 'student', 'CHECK 5b: self-promotion must be ignored';
  -- cannot write orders directly
  begin
    insert into orders (buyer_id, note_id, author_id, price_bdt, commission_rate, commission_bdt, author_share_bdt)
    values ('aaaaaaaa-0000-0000-0000-0000000000c1', '11111111-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-0000000000b1', 1, 0.1, 0, 1);
    raise exception 'NO_ERROR';
  exception when insufficient_privilege then null;
  end;
  -- cannot read the PDF path
  begin
    perform pdf_path from notes limit 1;
    raise exception 'NO_ERROR';
  exception when insufficient_privilege then null;
  end;
  -- cannot call admin functions
  begin
    perform admin_confirm_seller_payout(current_setting('test.order1')::uuid, 'HACK000001', 90, current_date, null, null);
    raise exception 'NO_ERROR';
  exception when others then
    assert sqlerrm = 'forbidden', 'CHECK 5c: admin function must say forbidden, got: ' || sqlerrm;
  end;
end $$;
reset role;

-- ======================================================= 6. admin pays the author later -> NO second entitlement, NO second sales_count
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  perform admin_confirm_seller_payout(current_setting('test.order1')::uuid, 'PAYOUT0001', 90, current_date, null, 'test payout');
  assert (select status from orders where id = current_setting('test.order1')::uuid) = 'completed', 'CHECK 6a: order should be completed';
  assert (select count(*) from purchase_entitlements where order_id = current_setting('test.order1')::uuid) = 1, 'CHECK 6b: still exactly one entitlement';
  assert (select sales_count from notes where id = '11111111-0000-0000-0000-000000000001') = 1, 'CHECK 6c: sales_count must still be 1';
  assert (select status from seller_payouts where order_id = current_setting('test.order1')::uuid) = 'completed', 'CHECK 6d: payout completed';
  begin
    perform admin_confirm_seller_payout(current_setting('test.order1')::uuid, 'PAYOUT0002', 90, current_date, null, null);
    raise exception 'NO_ERROR';
  exception when others then
    assert sqlerrm = 'bad_order_state', 'CHECK 6e: second payout must fail with bad_order_state, got: ' || sqlerrm;
  end;
end $$;
reset role;

-- ======================================================= 7. payout TrxID cannot be reused as a buyer payment claim
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  assert submit_buyer_payment(current_setting('test.order2')::uuid, 'PAYOUT0001', 'aaaaaaaa-0000-0000-0000-0000000000c2/p.png', true) = 'duplicate_trx', 'CHECK 7: a payout TrxID must not be accepted as a buyer TrxID';
end $$;
reset role;

-- ======================================================= 8. fake payment: reject, buyer stays locked out, corrected claim is allowed
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  assert submit_buyer_payment(current_setting('test.order2')::uuid, 'TRX0000002', 'aaaaaaaa-0000-0000-0000-0000000000c2/p.png', true) = 'ok', 'CHECK 8a: claim accepted for review';
end $$;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
do $$ begin
  perform admin_reject_buyer_payment((select id from buyer_payment_submissions where trx_id = 'TRX0000002' and status = 'pending'), 'No such transaction in bKash');
end $$;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
do $$ begin
  assert user_can_access_note('11111111-0000-0000-0000-000000000001') = false, 'CHECK 8b: rejected buyer must not have access';
  assert (select status from orders where id = current_setting('test.order2')::uuid) = 'payment_rejected', 'CHECK 8c: order should be payment_rejected';
  assert submit_buyer_payment(current_setting('test.order2')::uuid, 'TRX0000002', 'aaaaaaaa-0000-0000-0000-0000000000c2/p2.png', true) = 'ok', 'CHECK 8d: after rejection the TrxID is released for a corrected claim';
end $$;
reset role;

-- ======================================================= 9. settings are validated; audit log is append-only
do $$ begin
  begin
    update admin_settings set value = '0.9'::jsonb where key = 'commission_rate';
    raise exception 'NO_ERROR';
  exception when others then
    assert sqlerrm like 'commission_rate%', 'CHECK 9a: out-of-range commission must be refused, got: ' || sqlerrm;
  end;
  begin
    delete from audit_logs;
    raise exception 'NO_ERROR';
  exception when others then
    assert sqlerrm like '%append-only%', 'CHECK 9b: audit log must refuse deletes, got: ' || sqlerrm;
  end;
  assert exists (select 1 from audit_logs where action = 'buyer_payment_verified'), 'CHECK 9c: verification must be in the audit log';
  assert exists (select 1 from audit_logs where action = 'seller_payout_confirmed'), 'CHECK 9d: payout must be in the audit log';
end $$;

-- ======================================================= 10. hardening: catalog-level checks (run as the SQL-editor user)
do $$ begin
  assert not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')            -- ignore extension-owned functions
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c where c like 'search_path=%' and c not like '%public%')
  ), 'CHECK 10a: every function in schema public must pin an empty search_path';
  assert (select count(*) from pg_class where relnamespace = 'public'::regnamespace
            and relname in ('public_authors','author_sales','admin_payout_queue') and 'security_barrier=true' = any(reloptions)) = 3,
         'CHECK 10b: the three views must be security_barrier';
  assert not has_schema_privilege('anon', 'public', 'create') and not has_schema_privilege('authenticated', 'public', 'create'),
         'CHECK 10c: clients must not be able to create objects in schema public';
  assert not has_function_privilege('anon',          'public.claim_trx(text,text,uuid)', 'execute'), 'CHECK 10d: anon must not run claim_trx';
  assert not has_function_privilege('authenticated', 'public.claim_trx(text,text,uuid)', 'execute'), 'CHECK 10e: clients must not run claim_trx';
  assert not has_function_privilege('authenticated', 'public.audit(text,text,uuid,jsonb,jsonb)', 'execute'), 'CHECK 10f: clients must not write the audit log directly';
  assert not has_function_privilege('authenticated', 'public.notify(uuid,text,text,text,text)', 'execute'), 'CHECK 10g: clients must not send notifications directly';
  assert not has_function_privilege('anon',          'public.admin_verify_buyer_payment(uuid)', 'execute'), 'CHECK 10h: anon must not run admin functions';
  assert has_function_privilege('authenticated', 'public.create_order(uuid)', 'execute'), 'CHECK 10i: buyers must be able to run create_order';
  assert has_function_privilege('authenticated', 'public.paths_owned_by(text[],uuid)', 'execute'), 'CHECK 10j: clients need execute on paths_owned_by (used by a CHECK constraint)';
end $$;

-- ======================================================= 11. a file path must stay inside its owner's folder; the internal flag must not leak
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  begin
    update notes set pdf_path = 'aaaaaaaa-0000-0000-0000-0000000000c1/stolen.pdf' where id = '11111111-0000-0000-0000-000000000002';
    raise exception 'NO_ERROR';
  exception when check_violation then null;
  end;
  update notes set pdf_path = 'aaaaaaaa-0000-0000-0000-0000000000b1/own.pdf' where id = '11111111-0000-0000-0000-000000000002';   -- own folder is fine
  assert coalesce(current_setting('app.internal', true), '') <> 'on', 'CHECK 11a: internal flag must not be left on';
end $$;
reset role;

rollback;                                   -- nothing above is kept
select 'ALL CHECKS PASSED (and everything was rolled back)' as result;
