-- Cadet Sync · 0001 · schema
-- Order statuses 'payment_verified' and 'seller_payout_completed' are kept in the enum for compatibility,
-- but under the current rule (access at payment verification) an order is never left in either of them:
-- verify -> 'seller_payout_pending' (buyer already has access) -> payout confirmed -> 'completed'.
create type user_role as enum ('student','teaching_cadet','admin');
create type account_status as enum ('active','suspended');
create type verification_status as enum ('unverified','pending','verified','rejected');
create type application_status as enum ('pending','approved','rejected');
create type note_status as enum ('draft','pending_review','approved','rejected','suspended');
create type publishing_payment_status as enum ('awaiting_payment','payment_submitted','under_verification','verified','rejected');
create type order_status as enum ('payment_awaiting','payment_submitted','under_verification','payment_rejected','payment_verified','seller_payout_pending','seller_payout_completed','completed');
create type submission_status as enum ('pending','verified','rejected');
create type payout_status as enum ('pending','completed');

create table colleges (
  id serial primary key, name text not null unique, short_name text, logo_path text  -- logo_path: official emblem file supplied by the owner
);
create table subjects (
  id serial primary key, name text not null unique, slug text not null unique, sort_order int not null default 0
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role user_role not null default 'student',
  status account_status not null default 'active',
  verification verification_status not null default 'unverified',
  full_name text not null,
  email text not null,
  phone text,
  college_id int references colleges(id),
  cadet_id text,
  id_card_path text,                       -- private bucket
  bkash_number text check (bkash_number ~ '^01[3-9][0-9]{8}$'),
  avatar_path text,
  created_at timestamptz not null default now(),
  unique (college_id, cadet_id)
);
create unique index profiles_email_key on profiles (lower(email));

create table teaching_cadet_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  current_class smallint not null check (current_class between 6 and 12),
  academic_performance text, previous_results text,
  document_paths text[] not null default '{}',
  status application_status not null default 'pending',
  review_note text, reviewed_by uuid references profiles(id), reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index one_open_application on teaching_cadet_applications(user_id) where status = 'pending';

create table notes (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references profiles(id),
  subject_id int not null references subjects(id),
  class_level smallint not null check (class_level between 6 and 12),
  title text not null check (char_length(title) between 3 and 150),
  description text,
  price_bdt numeric(10,2) not null default 0 check (price_bdt >= 0),
  is_free boolean generated always as (price_bdt = 0) stored,
  cover_path text,
  pdf_path text,                            -- private bucket; never exposed to clients
  page_count int,
  preview_pages int not null default 3 check (preview_pages between 0 and 20),
  author_bkash text not null check (author_bkash ~ '^01[3-9][0-9]{8}$'),   -- payout destination; locked once the note is submitted
  status note_status not null default 'draft',
  rejection_reason text,
  published_at timestamptz,
  avg_rating numeric(3,2) not null default 0,
  rating_count int not null default 0,
  sales_count int not null default 0,
  created_at timestamptz not null default now()
);
create index notes_listing_idx on notes (status, published_at desc);
create index notes_author_idx on notes (author_id);
create index notes_subject_idx on notes (subject_id, class_level);
create index notes_search_idx on notes using gin (to_tsvector('simple', title || ' ' || coalesce(description,'')));

create table publishing_payments (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null unique references notes(id) on delete cascade,
  author_id uuid not null references profiles(id),
  fee_bdt numeric(10,2) not null check (fee_bdt > 0),     -- snapshot of the fee at creation
  status publishing_payment_status not null default 'awaiting_payment',
  trx_id text check (trx_id ~ '^[A-Z0-9]{8,14}$'),
  screenshot_path text, submitted_at timestamptz,
  reviewed_by uuid references profiles(id), reviewed_at timestamptz, rejection_reason text,
  created_at timestamptz not null default now()
);
create unique index pubpay_active_trx on publishing_payments(trx_id)
  where trx_id is not null and status in ('payment_submitted','under_verification','verified');

create sequence order_seq;
create table orders (
  id uuid primary key default gen_random_uuid(),
  order_no text not null unique default ('CS-' || to_char(now(),'YYMM') || '-' || lpad(nextval('order_seq')::text, 6, '0')),
  buyer_id uuid not null references profiles(id),
  note_id uuid not null references notes(id),
  author_id uuid not null references profiles(id),
  price_bdt numeric(10,2) not null check (price_bdt > 0),
  commission_rate numeric(5,4) not null,
  commission_bdt numeric(10,2) not null,
  author_share_bdt numeric(10,2) not null,
  status order_status not null default 'payment_awaiting',
  payment_verified_at timestamptz, completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint split_adds_up check (commission_bdt + author_share_bdt = price_bdt),
  constraint amounts_sane check (commission_bdt >= 0 and author_share_bdt >= 0 and commission_rate between 0 and 1),
  unique (buyer_id, note_id)                -- one order per buyer per note: no duplicate purchases
);
create index orders_status_idx on orders(status);
create index orders_author_idx on orders(author_id);

create table buyer_payment_submissions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id),
  buyer_id uuid not null references profiles(id),
  amount_bdt numeric(10,2) not null,        -- expected amount, copied from the order server-side
  trx_id text not null check (trx_id ~ '^[A-Z0-9]{8,14}$'),
  screenshot_path text not null,
  confirmed_checkbox boolean not null check (confirmed_checkbox),
  status submission_status not null default 'pending',
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references profiles(id), reviewed_at timestamptz, rejection_reason text
);
create unique index buyerpay_active_trx on buyer_payment_submissions(trx_id) where status <> 'rejected';
create unique index buyerpay_one_pending on buyer_payment_submissions(order_id) where status = 'pending';

create table seller_payouts (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references orders(id),   -- exactly one payout per order
  author_id uuid not null references profiles(id),
  amount_due_bdt numeric(10,2) not null,
  status payout_status not null default 'pending',
  payout_trx_id text unique,
  amount_paid_bdt numeric(10,2), paid_to_bkash text, paid_on date,
  proof_path text, admin_remarks text,
  confirmed_by uuid references profiles(id), confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint completed_has_proof_of_payment check (status = 'pending' or (payout_trx_id is not null and amount_paid_bdt is not null and confirmed_by is not null))
);

create table purchase_entitlements (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references profiles(id),
  note_id uuid not null references notes(id),
  order_id uuid not null unique references orders(id),
  granted_at timestamptz not null default now(),
  unique (buyer_id, note_id)
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  type text not null, title text not null, body text, link text,
  read_at timestamptz, created_at timestamptz not null default now()
);
create index notifications_user_idx on notifications(user_id, read_at, created_at desc);

create table wishlists  (user_id uuid references profiles(id) on delete cascade, note_id uuid references notes(id) on delete cascade, created_at timestamptz default now(), primary key (user_id, note_id));
create table cart_items (user_id uuid references profiles(id) on delete cascade, note_id uuid references notes(id) on delete cascade, created_at timestamptz default now(), primary key (user_id, note_id));

create table courses (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references profiles(id),
  subject_id int references subjects(id),
  title text not null, description text, cover_path text,
  class_level smallint check (class_level between 6 and 12),
  -- Paid courses are NOT enabled. Drop this check only when the owner turns the feature on.
  price_bdt numeric(10,2) not null default 0 check (price_bdt = 0),
  is_published boolean not null default false,
  created_at timestamptz not null default now()
);
create table course_materials (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references courses(id) on delete cascade,
  title text not null, kind text not null default 'link', url text, sort_order int not null default 0
);

create table reviews (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references notes(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text, created_at timestamptz not null default now(),
  unique (note_id, user_id)
);
create table reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references profiles(id),
  note_id uuid references notes(id) on delete cascade,
  reason text not null, status text not null default 'open',
  created_at timestamptz not null default now()
);
create table admin_settings (
  key text primary key, value jsonb not null, is_public boolean not null default false,
  updated_by uuid references profiles(id), updated_at timestamptz not null default now()
);
create table audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid, action text not null, entity text not null, entity_id uuid,
  before_data jsonb, after_data jsonb, created_at timestamptz not null default now()
);
create index audit_entity_idx on audit_logs(entity, entity_id);

-- One registry for EVERY bKash TrxID the system has seen, across publishing fees, buyer payments and seller payouts.
-- A TrxID can be 'active' only once, globally. Rejected claims are 'released' so a corrected resubmission is possible.
-- This closes the race where the same TrxID is submitted to two different tables at the same moment.
create table payment_trx_claims (
  id uuid primary key default gen_random_uuid(),
  trx_id text not null check (trx_id ~ '^[A-Z0-9]{8,14}$'),
  kind text not null check (kind in ('publishing','buyer','payout')),
  ref_id uuid not null,                       -- publishing_payments.id | buyer_payment_submissions.id | seller_payouts.id
  status text not null default 'active' check (status in ('active','released')),
  created_at timestamptz not null default now(),
  released_at timestamptz
);
create unique index claims_one_active_per_trx on payment_trx_claims (trx_id) where status = 'active';
create index claims_ref_idx on payment_trx_claims (kind, ref_id);
