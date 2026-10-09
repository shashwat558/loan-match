# loan-match — Issues Found (code review, ranked)

All findings are from reading the actual files. Secrets are described, never printed. Severity: P0 fix before demo, P1 fix soon, P2 polish.

## P0 — Secrets committed to the repo

- **Exa + Groq API keys inline in `n8n/workflows/workflow A.json`** ("HTTP Request" headers, "HTTP Request1" headers). Anyone with repo access can spend your quotas. Move to n8n credentials/`$env` and **rotate both keys**; the committed ones must be treated as burned.
- **Same class, smaller blast radius:** `ui/index.html` hardcodes the live API endpoint (not a secret, but it pins the demo to one deployment); `.env` holds the RDS password and lives next to the code (it is git-ignored per `package.patterns`, but there is no `.env.example` documenting required keys — new clones must guess them from `serverless.yml`).

## P0 — Repo workflow JSONs are stale vs the live instance

- **Truncated Groq key in `n8n/workflows/workflow B.json`** ("HTTP Request1" Authorization ends mid-string). With this file as-is, every LLM call 401s — yet live runs produced 759 `llm` matches, so the running workflow differs from the repo copy. Re-export B (and diff A/C) so the repo matches production, then rotate the key per above.
- **Model strings disagree:** A calls `qwen/qwen3-27b`-family as `qwen/qwen3.8-27b`, B as `qwen/qwen3-27b` (plus B's node sets `specifyBody: "=json"` with an empty `bodyParameters` alongside `jsonBody` — works, but fragile). Pin one model ID in both.

## P1 — Real bugs in code

- **Corrupted error string, `lambdas/process_csv/handler.py:53`:** the message reads `"age ohttp://localhost:5678/ut of range"` — a URL got pasted into the middle of `"age out of range"`. Logic unaffected, but any age-rejected row logs garbage, and it suggests an unreviewed edit.
- **Local Postgres never self-initializes:** `docker-compose.yml` mounts the schema at `/docker-entrypoint-initdb.db/schema.sql`, but Postgres only executes `/docker-entrypoint-initdb.d/` — so a fresh `docker compose up` starts an **empty** database and every local run fails until someone applies `schema.sql` by hand.
- **`match_count` excludes LLM matches:** workflow B's "Code in JavaScript3" counts only items carrying `match_id` from the SQL insert, but the notify POST reuses that count as the batch total — so the "match_count 0" the demo once showed understated reality whenever LLM rows existed. Count both stages (or rename the field `sql_match_count`).
- **`needs_llm_check` is write-only from the crawler:** workflow A never sets the column (its INSERT omits it → always false), so crawled products can never take the LLM path that B built for them — only hand-seeded rows (Premium) can. Set it when extraction yields no usable numbers.
- **`test_process_csv.py` points at the old bucket** (`loanmatch-dev-uploads-shashwat`), but deploys and the UI use `loanmatch-dev-uploads-shashwat-2026`. The local test silently targets the wrong bucket.

## P1 — Demo leftovers that will bite on camera

- **Workflow C `LIMIT 3` + hardcoded test inboxes** (`Email_template`, `testInboxes`): correct for demo, but there is no flag or comment marking them as demo-only — a future "just run it" will silently mail 3 people and stop. At minimum comment both; ideally gate on an env/option.
- **`match_stage` allows `'rules'`** (`schema.sql` CHECK), but nothing in the codebase ever writes it — the documented pipeline is sql → llm only. Either implement the rules stage or drop it from the constraint before a reviewer asks.
- **Stuck-batch UX:** `claim_batch` only claims `'uploaded'`, yet `handler()` always returns `{"status": "ok"}` — a no-op re-run is indistinguishable from success in logs. Return per-record `claimed/skipped` so stuck batches are visible.

## P2 — Fragile but working today

- **Unused `from urllib3.util import url`** (`process_csv/handler.py:13`): harmless with the pinned urllib3, but that import path has been removed upstream before — one `pip install -U` away from an ImportError that kills the whole Lambda at import time. Delete it (nothing references `url`).
- **Python-3.12-only f-string** (`process_csv/handler.py:168`, nested same-quote f-string): fine on `runtime: python3.12`, instant `SyntaxError` if anyone downgrades the runtime. Rewrite without nesting.
- **`user_id` format validated only by the database:** `validate_row()` checks presence, not UUID shape, while `users.user_id` is `uuid` type — a non-UUID id burns a whole chunk into a `failed` batch instead of one skipped row. Validate with a regex (B already has one — reuse the pattern).
- **`gen_random_uuid()` default with no `CREATE EXTENSION pgcrypto`:** `schema.sql` never enables the extension. Invisible today (the Lambda always supplies `batch_id`), fatal the first time anything relies on the default on a vanilla Postgres.
- **C's `queryReplacement` carries dead parameters** (batch_id twice; the query uses `{{ }}` templating instead): harmless, but the next editor will "fix" the wrong layer. Remove it.
- **`.env.example` doesn't exist** although setup docs imply it: add one listing every key `serverless.yml` and compose reference, with empty values.

## Mismatches vs the assignment (for the author to reconcile)

- The brief says notification sends **only to test aliases** — implemented (plus-addressed Gmail in `Email_template`), but undiscoverable without reading the Code node; one comment would save reviewer questions.
- The brief's "no more than 40 profiles" cap is implemented as `LIMIT 40` in "Fetch LLM candidates" — present and correct.
- Production hardening from the brief (private RDS, narrow security group, stable tunnel, secrets out of JSON) is **not done** — all four are listed as known limitations in `02_design_decisions.md` instead. Say that sentence on camera before a reviewer does.
