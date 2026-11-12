# Setup and testing guide (beginner)

Use a **test** Supabase project for everything below. Never run this on a project with real users or money.

## What has and hasn't been tested

| Check | Status | How |
|---|---|---|
| 117 text-level consistency checks on the 4 migrations (balanced `$$`/parentheses, every table has RLS, every column named in INSERT/UPDATE exists, every `GRANT` matches a defined function, definition-before-use, Option B rules, TrxID registry coverage, **all 39 functions pin an empty `search_path`, no unqualified table/type/function reference inside any function body, security-barrier views, flag restore, file-path ownership constraints**) | **EXECUTED here: 117 pass** | `python3 tools/lint_sql.py` |
| Negative controls: lint run against the old Phase 1 files, and against copies with one defect deliberately re-introduced (definer function back on `search_path = public`, unqualified table, unqualified helper call, unpinned trigger function, view without `security_barrier`, flag not restored, `is_trusted` trusting "no user id") | **EXECUTED here: all 7 hardening defects caught**; old files fail as before | one-off |
| Money split (৳100→90/10, ৳250→225/25, ৳99.99→89.99/10.00, parts always sum) | **EXECUTED here: pass**, using a plain-Node copy of `lib/money.ts` | one-off |
| Any SQL against **PostgreSQL / Supabase** (migrations, triggers, RLS, storage policies, atomic functions, `phase1_checks.sql`) | **NOT EXECUTED**. No database was available. The lint reads text; it cannot prove the SQL runs | you, below |
| `tests/money.test.ts` under Vitest | **NOT EXECUTED** (Vitest not installed here); the Node copy above stands in | `npx vitest` |
| `route.ts` changes (UUID check, TTL clamp), TypeScript compile | **NOT EXECUTED** (no Next.js project / type-checker here); read-reviewed only | `npm run build` |
| Download route, auth flow, storage upload limits, concurrency (two admins at once) | **NOT EXECUTED / recommended** | later phases |

So: the logic has been reviewed and statically checked, not proven. The first real test is Step 3.

## Step 1 — Create a test project
1. supabase.com → New project (name it `cadet-sync-test`). Wait until it is ready.
2. Settings → API: note the **Project URL**, **anon key**, **service_role key**. The service_role key is a master key: never put it in browser code or share it.

## Step 2 — Apply the migrations (in order)
SQL Editor → New query. For each file **in this order**, paste the whole file and press Run:
`0001_schema.sql` → `0002_helpers_rls.sql` → `0003_payment_workflows.sql` → `0004_storage_seed.sql`.
Each should end with **Success**. **If one errors, stop**, copy the error text, and don't run the next file. (If you already ran an older version, create a fresh project instead of re-running.)

## Step 3 — Run the database checks
1. New query → paste all of `supabase/tests/phase1_checks.sql` → Run.
2. Pass: a final row **ALL CHECKS PASSED**. Fail: a red error such as `CHECK 4c: sales_count must be 1`. Send me that line.
3. It saves nothing (ends in `ROLLBACK`). If the first `insert into auth.users` fails, create 3 users in Authentication → Users and replace the UUIDs as the file's header explains.

What it covers (45 checks, including the hardening checks 10a–10j and 11): no access before verification; screenshot doesn't unlock; verify → access + `sales_count`=1 + payout pending ৳90 + commission ৳10;
verify twice refused; payout later creates **no** second entitlement/sale count; payout twice refused; reused TrxID refused (same table, across tables,
payout-as-buyer, lower-case); rejection keeps buyer locked out and releases the TrxID; self-promotion ignored; direct order insert refused; PDF path unreadable;
non-admin refused; out-of-range commission refused; audit log can't be deleted.

## Step 4 — Create the app and run the money tests
```bash
node -v                                   # need 18 or newer
npx create-next-app@latest cadet-sync --ts --tailwind --app
cd cadet-sync && npm i @supabase/ssr @supabase/supabase-js server-only && npm i -D vitest
```
Copy this project's files over the new folder (don't overwrite `package.json`). Copy `.env.example` to `.env.local`, fill in the three keys.
Run `npx vitest` (money tests) and `python3 tools/lint_sql.py`.

## Step 5 — Make yourself admin and configure bKash
1. Authentication → Users → Add user (your email).
2. SQL Editor: `update profiles set role = 'admin' where lower(email) = 'you@example.com';`
3. Set the bKash number (checkout refuses until set): `update admin_settings set value = '"01XXXXXXXXX"' where key = 'bkash_number';`
4. Upload your QR image to Storage → `qr`, then `update admin_settings set value = '"your-file.png"' where key = 'bkash_qr_path';`
5. Turn on MFA for the admin account.

## Error words you may see
`forbidden` not an admin · `already_reviewed` someone already approved/rejected it · `bad_order_state` order isn't in the right step ·
`duplicate_trx` TrxID already used (also returned as a normal result, not an error, from the two submit functions) ·
`bkash_not_configured` admin hasn't set the number · `price_changed` buyer must reopen checkout · `account_not_active` account suspended ·
`invalid_trx_format` TrxID not 8–14 letters/digits · `entitlement_missing` payout attempted on an order that was never verified (should never happen).

## Before real money
Backups on (Supabase → Database → Backups), run Step 3 on the *production* schema copy, and have a second person try to break the flow.
