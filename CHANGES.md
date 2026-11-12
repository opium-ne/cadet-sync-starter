# Changes in Phase 1.1

Scope: (A) the new payment rule "access at payment verification", and (B) a full review of the four migrations.

## Files changed

| File | Size of change | Why |
|---|---|---|
| `0003_payment_workflows.sql` | rewritten (+145/−52) | Option B logic; global TrxID registry; locking order; new checks |
| `0002_helpers_rls.sql` | +121/−18 | Security and consistency fixes found in review |
| `0001_schema.sql` | +22/−2 | TrxID registry table, stricter constraints, `author_bkash` NOT NULL |
| `0004_storage_seed.sql` | +4/−2 | Active-account check on proof/ID uploads; seed note |
| `README.md` | rewritten | New payment rule, TrxID rules, decisions |
| *new* `SETUP_AND_TESTING.md`, `CHANGES.md`, `supabase/tests/phase1_checks.sql`, `tools/lint_sql.py` | new | Guide, change log, database checks, static checks |

Unchanged: `lib/*`, `app/api/notes/[id]/download/route.ts`, `tailwind.config.ts`, `styles/globals.css`, `.env.example`, `tests/money.test.ts`.
(The download route needed no change: it already relies only on `user_can_access_note()`, whose entitlement rule is the same.)

## A. Option B (your requirements 1–6)

| Requirement | Where |
|---|---|
| 1. Entitlement created at verification | `admin_verify_buyer_payment`: `insert into purchase_entitlements` |
| 2. `sales_count` +1 at the same point | same function: `update notes set sales_count = sales_count + 1` |
| 3. Payout stays pending, 90/10 | same function inserts `seller_payouts` (pending, `amount_due = author_share`); split frozen on the order |
| 4. Payout confirmation grants nothing | `admin_confirm_seller_payout`: no entitlement insert, no `sales_count`, no buyer notification; it now *checks* the entitlement already exists |
| 5. Notification wording | "Payment verified — your note is unlocked": *…is verified. The note is now available in your library.* Author is told the sale, their pending share and the platform's 10% |
| 6. Atomic | everything is one PL/pgSQL function = one transaction; any failure rolls back all of it. Rows are locked `order → submission` so two admins can't double-process; `UNIQUE(order_id)` on payout and entitlement and `UNIQUE(buyer,note)` are the backstops |

Order statuses: verify → `seller_payout_pending`; payout → `completed`. The enum values `payment_verified` and `seller_payout_completed`
are kept but never stored, because the order never rests in them.

## B. Review findings (all fixed unless noted)

**Duplicate TrxID (your focus item)**
- *Problem:* duplicate detection was read-then-write (`trx_in_use`) across two tables. Two simultaneous submissions of one TrxID, one as a
  fee and one as a purchase, could both pass; per-table unique indexes could not see each other. Seller payout TrxIDs weren't covered, so
  an author could replay their own payout TrxID as a "buyer payment".
- *Fix:* one `payment_trx_claims` registry + `claim_trx()` using `INSERT … ON CONFLICT DO NOTHING` on a partial unique index (race-free);
  covers publishing, buyer and payout; case/space normalised; rejections release the claim; the per-table indexes stay as a backstop.

**Security / integrity**
- Deleting a draft note could cascade-delete a *submitted* publishing-fee record (money evidence). Now blocked (`guard_note_delete`).
- A review could be edited to point at a different note, bypassing the "must have bought it" rule. Update limited to `rating, comment`.
- Payout destination could be swapped after approval, or fall back to the editable profile number. `notes.author_bkash` is now NOT NULL, locked after submission, and is the only number used.
- Suspended accounts could still edit notes, order, submit payments and download. Added `is_active_user()` to workflows, policies, downloads and uploads.
- Teaching Cadet approval could be done by direct UPDATE, leaving role and application out of sync, and applicants could set review fields. Approval is RPC-only; insert limited to applicant columns.
- Admin settings (where real money is sent) were unvalidated and unaudited. Now validated (`validate_setting`) and every change audited.
- An empty bKash number could reach payment pages. `create_order` / `start_publishing_payment` now refuse until it is set.
- Order amounts could in theory be edited; order financials are now immutable (except a price refresh on an *unpaid* order). Money rows can't be deleted; TRUNCATE/TRIGGER/REFERENCES revoked from client roles.
- Stale price: if a note's price changed while an unpaid order existed, buyer could pay the old amount. Now refreshed, and `price_changed` blocks the submit.
- `handle_new_user` could fail signup on bad metadata or let one person squat another's Cadet ID. Parsed defensively.
- Verified identity fields (college, cadet ID, ID card, name) can't be self-edited.
- `author_bkash` is hidden from clients, so admins couldn't see it. Added `admin_payout_queue` view (admin-only rows).
- Wishlist/cart accepted unapproved notes; own free note could be self-reviewed; `public_stats` counted admins. Fixed.
- Default function privileges revoked so future functions aren't accidentally public.

**A bug I introduced while fixing, found by re-reading:** `user_can_access_note` (a SQL function, checked at creation) called
`is_active_user()` before it was defined, which would have failed migration 0002. Reordered, and added a lint check for this class of mistake.

**Not fixed (needs your decision):** see "Decisions for the owner" in the README (revocation/undo, suspended-note access, cart behaviour).

---

# Final hardening pass (security review of Phase 1.1)

Scope: every SECURITY DEFINER function, `search_path`, object resolution, and any other critical issue. No business rule or architecture change.

## Files changed
`0001_schema.sql`, `0002_helpers_rls.sql`, `0003_payment_workflows.sql`, `supabase/tests/phase1_checks.sql`, `tools/lint_sql.py`,
`app/api/notes/[id]/download/route.ts`, `SETUP_AND_TESTING.md`, this file. Unchanged: `0004_storage_seed.sql` (it contains no functions and its policies bind objects at creation), README, `lib/`.

## 1. search_path (the main finding)
- **Before:** 29 SECURITY DEFINER functions used `set search_path = public`, and 9 invoker functions (triggers, `is_trusted`, `calc_split`, …) had none.
  A definer function runs with the owner's powers (BYPASSRLS, can write everything). With `public` on its path, any object an attacker manages to create in `public`
  (e.g. an operator or function overload with a "closer" type match) could hijack calls made *by that powerful function*. Exposure also depended on who can create objects in `public`.
- **Fix:** all 39 functions now use `set search_path = ''` and every table, type and function inside them is schema-qualified (`public.orders`, `public.audit(...)`, `public.application_status`).
  Built-ins (`now`, `upper`, `jsonb_build_object`, operators) always resolve from `pg_catalog`; `auth.uid()` was already qualified. Done by script, then verified by lint check H2
  (no unqualified project object remains in any function body) and negative controls.
- Policies, views, triggers and column defaults bind to objects at creation time, so they needed no change.
- `revoke create on schema public from public, anon, authenticated` closes the shadowing surface regardless; client roles also lose access to `order_seq`.

## 2. Other issues fixed
| Issue | Fix |
|---|---|
| `is_trusted()` treated "no user id" as trusted, including for the `anon` role | now only for server-side roles (SQL editor, service role); `anon`/`authenticated` never |
| Internal flag `app.internal` stayed on for the rest of the transaction after a workflow function or the rating trigger | every function saves and restores the previous value |
| Views run with owner rights and had no `security_barrier`; a crafted filter could in theory leak rows through error messages (incl. `admin_payout_queue`, which exposes bKash numbers) | `security_barrier = true` on `public_authors`, `author_sales`, `admin_payout_queue` |
| `notes.pdf_path` could be set to any string, and the download route signs it for the author (path-guessing could expose another author's PDF) | CHECK: `pdf_path`/`cover_path` must start with the author's own folder; same for profile `avatar_path`/`id_card_path` and application documents (`paths_owned_by`, executable by clients because CHECKs run with the caller's rights) |
| Course links could be `javascript:` URLs | CHECK: `http(s)://` only |
| Download route: unvalidated id, unbounded signed-URL lifetime from an env value | UUID check; TTL clamped to 10–300 s |

## 3. Reviewed, no change needed
`format()` in the RLS loop uses `%I`; there is no other dynamic SQL. Internal helpers (`audit`, `notify`, `claim_trx`, …) are not executable by clients. Money tables have no client write path. Definer functions all check `auth.uid()`/`is_admin()` before acting.

## 4. Remaining recommendations (not changed: they alter product behaviour)
- Authors can edit title/description after approval without re-moderation (price, PDF and payout number are locked).
- Escape all user text (note titles, notification bodies) in the UI; the database stores it verbatim.
- The bKash number and QR path are public settings, readable by anyone, by design for the payment page.
- Add admin undo functions (revoke access / cancel payout) before launch (see README).
