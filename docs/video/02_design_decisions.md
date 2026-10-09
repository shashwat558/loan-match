# loan-match — Design Decisions

Each decision is told as Problem → What I did → Why → Trade-off. All file and node names are the real ones.

## 1. Presigned S3 upload instead of uploading through API Gateway

- **Problem:** Applicant CSVs are ~1 MB per 10,000 rows and growing. API Gateway caps payloads around 10 MB and times out after ~29 seconds, so big files would fail at the front door, and every byte would pass through (and be billed by) the Lambda.
- **What I did:** `GET /upload-url` (`lambdas/get_upload_url/handler.py`) only mints a 5-minute presigned PUT signed for exactly `Content-Type: text/csv`. The browser in `ui/index.html` PUTs the raw file straight to S3. The API never touches file bytes.
- **Why:** Uploads scale to any size S3 accepts, can't time out the 15-second Lambda, and cost almost nothing (S3 bandwidth instead of Lambda GB-seconds).
- **Trade-off:** The client must send byte-exact headers (`Content-Type: text/csv`, no `Authorization`, no `FormData`) or S3 answers `SignatureDoesNotMatch`. The UI hardcodes this, but any new client must know the rule. Also, `file://` pages send `Origin: null`, which API Gateway won't answer CORS for — the page must be served over `http://localhost`.

## 2. Event-driven S3 trigger, streaming CSV parsing, chunked bulk upserts

- **Problem:** 10,000 rows must go from an S3 object to validated database rows without running out of Lambda memory or time, and without manual steps.
- **What I did:** The bucket's `NotificationConfiguration` (`serverless.yml`) fires `processCsv` (300 s timeout, 512 MB) on every `uploads/*.csv` arrival. The handler streams the object (`codecs.getreader("utf-8-sig")`, so BOM-prefixed Excel exports work), validates row by row in `validate_row()`, and writes with `execute_values` in `CHUNK_SIZE = 1000` chunks.
- **Why:** Streaming keeps memory flat no matter the file size; 1,000-row chunks balance round-trips against transaction size; the trigger makes ingestion fully automatic the second the upload lands.
- **Trade-off:** A giant file still risks the 300 s ceiling (mitigation would be SQS fan-out per chunk — not built). Chunk commits mean a mid-file crash can leave earlier chunks saved; the batch stays `processing` (never silently `done`), and re-running re-upserts the same rows harmlessly (see next decision).

## 3. Idempotency (claim_batch, ON CONFLICT, unique constraints)

- **Problem:** S3 delivers events at-least-once, Lambdas retry, and humans re-click. Without guards, one upload could insert users or matches twice.
- **What I did:** Three layers. (1) `claim_batch()` in `process_csv`: `UPDATE ... WHERE status='uploaded'` — only an unclaimed batch flips to `processing` (`cur.rowcount == 1`); anything else logs "already claimed, skipping". (2) `ON CONFLICT (user_id) DO UPDATE` on users, `ON CONFLICT (user_id, product_id) DO NOTHING` on matches, `ON CONFLICT (product_name, source) DO UPDATE` on products — replays converge instead of duplicating. (3) Unique constraints in `sql/schema.sql` enforce it at the database level even if code is bypassed.
- **Why:** Retries become safe by construction; operators can re-fire any step while debugging without fear.
- **Trade-off:** A crash between claim and finish leaves the batch stuck in `processing` (only `'uploaded'` rows are claimable), needing a manual `UPDATE ... SET status='uploaded'` reset. And `handler()` always returns `{"status": "ok"}`, so a skipped re-run *looks* identical to a successful one in logs.

## 4. The Optimization Treasure Hunt (17,348 SQL matches measured)

The assignment's core challenge: match ~10,000 users against N products without a 10,000×N nested loop and without thousands of LLM calls. The pipeline hunts the optimum in stages, cheapest first.

- **Stage 1 — set-based SQL pre-filter with top-3 per user.** Problem: per-user application code would be 10,000+ queries. What: one INSERT…SELECT joining the batch to active products on all six bounds (NULL bound = no restriction), scoring `100 − interest_rate` (cheapest loan scores highest, null rate scores as 20), keeping 3 rows per user (`ROW_NUMBER() ... rn <= 3`). Why: the database does in milliseconds what code would do in minutes. Measured: **17,348 SQL matches** on a reference 10k-user batch (a later run: 19,855 SQL + 759 LLM = 20,614 total). Trade-off: SQL only understands numbers — nuanced wording ("stable income", "3x EMI cover") is invisible to it, which is why flagged products are excluded here (`NOT p.needs_llm_check`) and handled next.
- **Stage 2 — profile banding (thousands of users → at most 40).** Problem: sending every user to the LLM costs thousands of calls. What: "Fetch LLM candidates" groups users by `(income rounded to 25k, score rounded to 50, employment)` with `array_agg(user_id)`, biggest groups first, `LIMIT 40`. Why: users in the same band are interchangeable for a judgment call, so one verdict can cover hundreds of people. Real batches collapsed to a handful of profiles. Trade-off: banding is an approximation — users near a band edge share a verdict that might differ if judged individually.
- **Stage 3 — one Groq call per flagged product.** Problem: per-user LLM calls are slow and expensive. What: "Build LLM prompt" groups profiles by product, labels them `p1…pn` with an `idMap` back to real user IDs (the LLM never sees real IDs), and one temperature-0 `json_object` call judges all profiles for that product. Why: a 10k-user batch costs a few LLM calls total instead of thousands. Trade-off: one malformed JSON response loses a whole product's verdicts (mitigated: the parse Code node drops just that product, everything else proceeds).
- **Stage 4 — validation of LLM output.** Problem: LLMs hallucinate IDs. What: "Code in JavaScript2" keeps only `eligible === true` entries whose label exists in `idMap` and whose user IDs pass a UUID regex, then writes via `json_to_recordset` with `ON CONFLICT DO NOTHING` at fixed score 75. Why: defense in depth — even a misbehaving model cannot invent users, products, or duplicates.

## 5. Crawler design (search, text extraction, LLM to JSON, validation, upsert)

- **Problem:** The product catalog goes stale; hand-maintaining bank offers doesn't scale.
- **What I did (workflow A, daily 18:00):** constrained domains → Exa search (3 hits each, 8,000 chars of clean page text) → drop pages under 200 chars → strict system prompt ("ONLY JSON, max 5 products, never invent values, null when unstated") → Groq `json_object` extraction → Code-node sanitizing (trim, rate clamped 1–50%, employment mapped to a closed list, sha256 `criteria_hash`) → upsert on `(product_name, source)`.
- **Why this split:** Exa for retrieval (clean text, no HTML parsing), LLM only for structuring (typed fields from prose), code as the final gatekeeper (LLM output is never trusted directly). Each stage does what it's best at.
- **Trade-off:** Only 3 domains × 3 results with one generic query, so yield is thin (aggregator pages often extract to nothing — correctly, by design). The hash is stored but never compared, so unchanged pages are re-processed daily, and withdrawn offers are never deactivated (`is_active` is always set true). See issues file for the fix list.

## 6. Notification design (test inbox override, SES sandbox, mark notified after send)

- **Problem:** Demo emails must never reach real applicants, but the send path must be genuinely exercised.
- **What I did (workflow C):** pick the top 3 users by match count (`LIMIT 3`), build one email per user in `Email_template`, route every address to 3 Gmail plus-alias test inboxes (never the applicant's real email), send via SES, then `UPDATE matches SET notified = true` for exactly the emailed `match_ids`. Empty input returns `[]` and the workflow stops before SES.
- **Why:** Plus-addressing keeps one test mailbox while proving per-user routing; marking *after* success (not before) means a failed send is retried next run instead of silently lost; the partial index on `notified = false` keeps the lookup fast.
- **Trade-off:** Production needs the opposite default (real addresses, all users, not top-3) — the test override and the `LIMIT 3` are demo settings that must be flipped deliberately, and SES sandbox mode requires every recipient verified.

## 7. Security choices and honest limitations

- **Least-privilege IAM:** the Lambda role allows only `s3:PutObject/s3:GetObject` on `<bucket>/uploads/*` plus logs. Presigned URLs inherit the signer's rights, so minimalism here is load-bearing, not cosmetic.
- **No public S3 access:** all four public-access blocks are on; uploads work purely through signed URLs. CORS allows browser PUTs with `*` origins — acceptable for a demo, too loose for production (pin the UI origin).
- **Validation in two places:** Python row checks mirror the Postgres CHECKs (email shape, income ≥ 0, score 300–900, age 18–100), so bad data is rejected with row-level reasons before it can violate constraints.
- **Honest limitations:** RDS is publicly reachable with a wide-open security group for the demo (production: private subnets, Lambda in the VPC, Secrets Manager, no env-var passwords). The free tunnel URL rotates on restart, silently breaking `N8N_WEBHOOK_URL` (batches then record `webhook failed: 404` while staying `done`). The banded LLM verdict is an approximation (see Stage 2). The crawler yields few products and never deactivates stale ones. API keys for Exa/Groq are committed in the workflow JSON — rotate them and move to n8n credentials (see issues file).
