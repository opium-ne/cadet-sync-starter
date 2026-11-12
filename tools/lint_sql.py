"""Static consistency checks for the Cadet Sync migrations. This is NOT PostgreSQL: it only reads the text."""
import re, sys, glob
import os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "supabase", "migrations") + "/"
files = sorted(glob.glob(D + "*.sql")); src = {f.split('/')[-1]: open(f, encoding='utf-8').read() for f in files}
allsql = "\n".join(src.values()); fails = []; passes = []
def check(name, ok, detail=""):
    (passes if ok else fails).append(name + ("" if ok else f"  -> {detail}"))

# 1. balanced $$ and parentheses (ignoring strings/comments)
for n, s in src.items():
    check(f"{n}: even number of $$ markers", s.count("$$") % 2 == 0, s.count("$$"))
    depth = 0; i = 0; bad = False
    while i < len(s):
        c = s[i]
        if s.startswith("--", i):
            i = s.index("\n", i) if "\n" in s[i:] else len(s); continue
        if c == "'":
            i += 1
            while i < len(s):
                if s[i] == "'" and s[i+1:i+2] == "'": i += 2; continue
                if s[i] == "'": break
                i += 1
        elif c == "(": depth += 1
        elif c == ")":
            depth -= 1
            if depth < 0: bad = True
        i += 1
    check(f"{n}: parentheses balanced", depth == 0 and not bad, f"depth={depth}")

# 2. schema model
tables = {}
t0 = src["0001_schema.sql"]
for m in re.finditer(r"create table (\w+)\s*\(", t0):
    i = m.end(); d = 1; j = i
    while d:                                   # find the matching close paren (skip strings and comments)
        c = t0[j]
        if t0.startswith("--", j): j = t0.index("\n", j); continue
        if c == "'":
            j += 1
            while not (t0[j] == "'" and t0[j+1:j+2] != "'"): j += 2 if t0[j:j+2] == "''" else 1
        elif c == "(": d += 1
        elif c == ")": d -= 1
        j += 1
    body = re.sub(r"--[^\n]*", "", t0[i:j-1]); parts = []; dd = 0; cur = ""; instr = False
    for ch in body:
        if ch == "'": instr = not instr
        if not instr:
            if ch == "(": dd += 1
            if ch == ")": dd -= 1
        if ch == "," and dd == 0 and not instr: parts.append(cur); cur = ""
        else: cur += ch
    parts.append(cur); cols = set()
    for p in parts:
        p = p.strip()
        if not p or re.match(r"(constraint|unique|primary|check|foreign)\b", p, re.I): continue
        cols.add(p.split()[0])
    tables[m.group(1)] = cols
expected = set(re.findall(r"create table (\w+)", src["0001_schema.sql"]))
check(f"schema parser found all {len(expected)} tables", set(tables) == expected, expected - set(tables))

# 3. RLS enabled for every table
rls = re.search(r"foreach t in array array\[(.*?)\] loop", src["0002_helpers_rls.sql"], re.S).group(1)
rls_tables = set(re.findall(r"'(\w+)'", rls))
missing = set(tables) - rls_tables
check("RLS enabled on every table", not missing, missing)

# 4. column names in INSERT / UPDATE statements exist
for m in re.finditer(r"insert into (?:public\.)?(\w+)\s*\(([^)]*)\)", allsql):
    t, cols = m.group(1), [c.strip() for c in m.group(2).split(",")]
    if t in tables:
        bad = [c for c in cols if c not in tables[t]]
        check(f"insert into {t}: columns exist", not bad, bad)
for m in re.finditer(r"update (?:public\.)?(\w+) set (.*?)(?: where | returning |;|\n\s*(?:and|from))", allsql, re.S):
    t = m.group(1)
    if t in tables:
        assigns = re.findall(r"(?:^|,)\s*(\w+)\s*=", m.group(2))
        bad = [c for c in assigns if c not in tables[t]]
        check(f"update {t}: columns exist ({','.join(assigns)[:40]}...)", not bad, bad)

# 5. functions defined vs granted vs called
defs = {}
for m in re.finditer(r"create (?:or replace )?function (\w+)\((.*?)\)\s*returns", allsql, re.S):
    args = [a.strip() for a in m.group(2).split(",") if a.strip()]
    defs[m.group(1)] = len(args)
for m in re.finditer(r"grant execute on function (.*?)\n?\s*to ", allsql, re.S):
    for g in re.finditer(r"(\w+)\(([^)]*)\)", m.group(1)):
        name, args = g.group(1), [a for a in g.group(2).split(",") if a.strip()]
        check(f"grant {name}({len(args)}) matches a definition", defs.get(name) == len(args), f"defined with {defs.get(name)} args")
called = set(re.findall(r"perform (?:public\.)?(\w+)\(", allsql))
BUILTIN = {"set_config"}
check("every `perform fn()` target is defined", not (called - set(defs) - BUILTIN), called - set(defs) - BUILTIN)

# 6. every admin_* / review_* function checks is_admin()
def body(name):
    m = re.search(rf"create or replace function {name}\(.*?\$\$(.*?)\$\$;", src["0003_payment_workflows.sql"], re.S)
    return m.group(1) if m else ""
for fn in [f for f in defs if f.startswith("admin_") or f.startswith("review_")]:
    check(f"{fn}: begins with is_admin() check", re.search(r"if not (?:public\.)?is_admin\(\) then raise exception 'forbidden'", body(fn)) is not None)

# 7. OPTION B invariants
INS_ENT = re.compile(r"insert into (?:public\.)?purchase_entitlements")
v, p = body("admin_verify_buyer_payment"), body("admin_confirm_seller_payout")
check("B1 verify creates purchase_entitlements", INS_ENT.search(v) is not None)
check("B2 verify increments sales_count", "sales_count = sales_count + 1" in v)
check("B3 verify creates the pending payout row from author_share_bdt", re.search(r"insert into (?:public\.)?seller_payouts", v) is not None and "o.author_share_bdt" in v)
check("B4 payout does NOT insert entitlements", "purchase_entitlements" in p and not INS_ENT.search(p))
check("B4 payout does NOT touch sales_count", "sales_count" not in p)
check("B5 verify notification says verified + available in library", "is verified. The note is now available in your library" in v)
check("B6 verify uses row locks on order and submission", v.count("for update") == 2)
check("B6 verify does all writes in one function (no commit/savepoint)", not re.search(r"\b(commit|rollback|savepoint)\b", v, re.I))
for n in ("0003_payment_workflows.sql",):
    others = re.sub(r"create or replace function admin_verify_buyer_payment.*?\$\$;", "", src[n], flags=re.S)
    check("entitlements are inserted ONLY by admin_verify_buyer_payment", not INS_ENT.search(others))
    check("sales_count is incremented ONLY by admin_verify_buyer_payment", "sales_count + 1" not in others)

# 8. TrxID registry coverage
for fn, kind in (("submit_publishing_payment", "publishing"), ("submit_buyer_payment", "buyer"), ("admin_confirm_seller_payout", "payout")):
    check(f"{fn} claims TrxID in global registry ({kind})", f"claim_trx(t, '{kind}'" in body(fn))
check("rejections release the claim", "release_trx('buyer'" in body("admin_reject_buyer_payment") and "release_trx('publishing'" in body("admin_review_publishing_payment"))
check("no leftover trx_in_use()", "trx_in_use" not in allsql)

# 9. clients can't call internal helpers
granted_blob = " ".join(re.findall(r"grant execute on function (.*?) to ", allsql, re.S))
for internal in ("audit", "notify", "notify_admins", "get_setting", "claim_trx", "release_trx", "setting_numeric", "normalize_trx", "calc_split"):
    check(f"{internal}() not granted to clients", not re.search(rf"\b{internal}\(", granted_blob))


# 10. definition-before-use (SQL-language functions, policies, views and triggers are validated by PostgreSQL when created)
order_src = "\n".join(src[k] for k in sorted(src)); pos = {}
for m in re.finditer(r"create (?:or replace )?function (\w+)\(", order_src): pos.setdefault(m.group(1), m.start())
stmts = []
i = 0
while True:                                            # one statement at a time: functions via their $$ ... $$; span
    m = re.compile(r"create (?:or replace )?(function|policy|view|trigger) ").search(order_src, i)
    if not m: break
    st = m.start()
    if m.group(1) == "function":
        o = order_src.index("$$", st); c = order_src.index("$$", o + 2); end = order_src.index(";", c) + 1
        header = order_src[st:o]
        if re.search(r"language\s+sql", header, re.I) or re.search(r"language\s+sql", order_src[c:end], re.I):
            stmts.append((st, order_src[st:end], header))
    else:
        end = order_src.index(";", st) + 1
        stmts.append((st, order_src[st:end], ""))
    i = end
bad = []
for st, text, _ in stmts:
    own = re.match(r"create (?:or replace )?function (\w+)", text)
    for name, p in pos.items():
        if own and own.group(1) == name: continue
        if re.search(rf"\b{name}\(|execute function {name}\b", text) and p > st: bad.append((text[:60].replace("\n", " "), name))
check(f"definition-before-use ({len(stmts)} SQL functions/policies/views/triggers checked)", not bad, bad[:5])


# 11. SECURITY HARDENING ---------------------------------------------------------------------------------------------
fn_stmts = []                                          # (name, header, body) for every function in every migration
for n_, s_ in src.items():
    for m in re.finditer(r"create (?:or replace )?function (\w+)\(", s_):
        o = s_.index("$$", m.start()); c = s_.index("$$", o + 2)
        fn_stmts.append((m.group(1), s_[m.start():o], s_[o+2:c]))
check(f"H1 all {len(fn_stmts)} functions pin search_path to the empty string",
      all(re.search(r"set search_path = ''", h) for _, h, _ in fn_stmts), [n for n, h, _ in fn_stmts if "set search_path = ''" not in h])
check("H1b no search_path that includes public remains", not re.search(r"search_path\s*=\s*(?!'')\S*public", allsql))
definers = [n for n, h, _ in fn_stmts if "security definer" in h]
check(f"H1c {len(definers)} SECURITY DEFINER functions all pinned", all("set search_path = ''" in h for n, h, _ in fn_stmts if "security definer" in h))

def strip(b):                                          # remove comments and string literals, keep code
    out, i = [], 0
    while i < len(b):
        if b.startswith("--", i): j = b.find("\n", i); i = len(b) if j < 0 else j
        elif b[i] == "'":
            j = i + 1
            while True:
                if b[j] == "'" and b[j+1:j+2] == "'": j += 2; continue
                if b[j] == "'": break
                j += 1
            i = j + 1
        else: out.append(b[i]); i += 1
    return "".join(out)
proj_funcs = sorted({n for n, _, _ in fn_stmts}, key=len, reverse=True)
enum_names = re.findall(r"create type (\w+)", src["0001_schema.sql"])
bare = []
for n, _, b in fn_stmts:
    code = strip(b)
    for t in tables:
        if re.search(rf"(?<![\w.]){t}(?![\w])", code): bare.append((n, t))
    for t in enum_names:
        if re.search(rf"(?<![\w.]){t}(?![\w])", code): bare.append((n, t))
    for f_ in proj_funcs:
        if re.search(rf"(?<![\w.]){f_}\s*\(", code): bare.append((n, f_ + "()"))
check("H2 no unqualified table / type / function reference in any function body", not bare, bare[:6])

for v_ in ("public_authors", "author_sales", "admin_payout_queue"):
    check(f"H3 view {v_} is security_barrier", re.search(rf"create (?:or replace )?view {v_} with \(security_barrier = true\)", allsql) is not None)
for n, h, b in fn_stmts:
    if re.search(r"set_config\('app\.internal',\s*'on'", b):
        check(f"H4 {n}: restores app.internal after raising it", "set_config('app.internal', coalesce(v_prev" in b)
check("H5 is_trusted() no longer trusts 'no user id' for anon/authenticated", "current_user not in ('anon', 'authenticated')" in allsql)
check("H6 CREATE on schema public revoked from clients", "revoke create on schema public from public, anon, authenticated" in allsql)
check("H7 stored file paths must be inside the owner's folder (notes, profiles, applications)",
      all(x in src["0001_schema.sql"] for x in ("pdf_in_author_folder", "cover_in_author_folder", "id_card_in_own_folder", "avatar_in_own_folder", "paths_owned_by(document_paths, user_id)")))
check("H8 paths_owned_by() (used in a CHECK) is executable by clients", "paths_owned_by(text[], uuid)" in src["0003_payment_workflows.sql"])
check("H9 course links limited to http(s)", "url_is_http" in src["0001_schema.sql"])

print(f"PASSED {len(passes)}   FAILED {len(fails)}")
for f in fails: print("FAIL:", f)
sys.exit(1 if fails else 0)
