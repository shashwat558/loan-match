# loan-match — Recording Checklist

## Pre-recording checklist

### Services running (verify each, in order)
- [ ] Docker: `docker ps` shows `app-postgres` (Up) and `n8n` (Up, port 5678).
- [ ] Tunnel: ngrok (or equivalent) forwarding to `:5678`; open `<tunnel>/healthz` → `{"status":"ok"}`.
- [ ] Tunnel URL matches `N8N_WEBHOOK_URL` in the deployed Lambda env. Tunnel URLs rotate on restart — if it changed, update `.env` and `serverless deploy` again.
- [ ] n8n workflows **Active** (green toggle, page refreshed to confirm): A, B, C. Production webhooks (`/webhook/...`) 404 unless active; test URLs don't count.
- [ ] Quick webhook ping: `curl -X POST <tunnel>/webhook/loan-match -d '{"batch_id":"ping","valid_rows":1}'` → expect the n8n "not registered" error to be GONE (a workflow error is fine; 404-not-registered is not).
- [ ] AWS: `aws sts get-caller-identity` works; stack `loan-engine-dev` exists; endpoint `GET .../upload-url` returns JSON in under a second.

### State reset (clean demo data, keep tables)
Run against RDS (replace host/vars from `.env`):
```sql
TRUNCATE matches, users;   -- must list both: matches has FKs to users
```
Leave `loan_products` (seeded catalog) and `upload_batches` alone — or reset a stuck batch with:
```sql
UPDATE upload_batches SET status='uploaded', total_rows=0, inserted_rows=0,
  skipped_rows=0, error_message=NULL WHERE batch_id='<id>';
```
Confirm: `SELECT count(*) FROM users;` → 0, `SELECT count(*) FROM matches;` → 0.

### Browser tabs, in order
1. Architecture diagram (rendered Mermaid).
2. n8n → workflow A (canvas).
3. n8n → workflow B (canvas).
4. n8n → workflow C (canvas).
5. n8n → Executions list (you'll flip here after the upload).
6. `http://localhost:8000` — the UI served via `cd ui && python3 -m http.server 8000` (never `file://`; browsers send `Origin: null` for files and API Gateway won't answer CORS for it).
7. Gmail test inbox (one of the `+one/+two/+three` aliases).
8. AWS console → CloudWatch Logs for `loan-engine-dev-processCsv` (optional; a terminal works too).

### Terminal windows (commands pre-typed, don't hit Enter yet)
- T1 (repo root): `venv/bin/python test_get_upload_url.py` — spare manual upload-URL check.
- T2 (repo root): `SELECT match_stage, count(*) FROM matches GROUP BY 1;` via psql to RDS — the money query. Full form:
  `docker exec -i app-postgres psql "postgresql://<RDS_USER>:<RDS_PASS>@<RDS_HOST>:5432/loan_engine" -c "SELECT match_stage, count(*) FROM matches GROUP BY 1;"`
- T3: `curl` for the API health check: `curl -s -o /dev/null -w '%{http_code}\n' https://<api-id>.execute-api.ap-south-1.amazonaws.com/upload-url`.

### Test file + inbox + silence + secrets
- [ ] Demo CSV ready: 10,000-row users file with the 7 required columns (`user_id,email,name,monthly_income,credit_score,employment_status,age`).
- [ ] Gmail test inbox open and logged in.
- [ ] OS notifications silenced (Do Not Disturb), phone away, unrelated tabs closed.
- [ ] Secrets hidden: `.env` never on screen; n8n credential screens never opened on camera; workflow JSONs contain committed API keys — do NOT scroll the HTTP Request nodes' header sections; API Gateway IDs are fine to show.

## If something fails live

| Failure | On-camera recovery (10 seconds) | Recorded fallback to cut to |
|---|---|---|
| Upload button does nothing / "Failed to fetch" | Say "the page needs its API address — let me confirm it," hard-refresh localhost tab; if still failing, open DevTools Console once to show the message, then cut. | Pre-recorded 20 s clip of a working upload ending on the batch ID. |
| PUT to S3 fails (403/AccessDenied) | Say "that signed link expired — links live five minutes," `GET /upload-url` fresh in T3, re-upload. | Screenshot of a 200 PUT response headers. |
| Batch stuck in `processing` | Say "a retry collided with the first run — the claim guard held, I'll reset it," run the `UPDATE ... SET status='uploaded'` reset off-camera, re-fire. | Screenshot of a `done` batch row with counters. |
| n8n executions don't appear | Check Active toggles + tunnel URL live on camera (30 s max); if dead, say "the tunnel rotated — this is the documented limitation," then cut. | Pre-recorded B-then-C green executions. |
| Webhook 404 in `error_message` | Point at the `error_message` column and say "that's the tunnel/activation signal I documented — ingestion still completed." | Screenshot of the executions list with a green B run. |
| No email arrives | Show the `notified` flags query (`SELECT count(*) FROM matches WHERE notified;`) to prove the send path ran, then cut. | Pre-recorded Gmail message open. |
| RDS unreachable | Say "the demo database is taking a break," switch to local Postgres counts (same schema) and keep going. | Screenshot of the `GROUP BY match_stage` result. |

General rule: narrate the failure in one honest sentence using the doc's vocabulary ("claim guard", "five-minute link", "tunnel rotated"), then cut to the fallback. Never debug silently on camera.

## 10 reviewer questions (with answers from the real code)

1. **Why not upload the CSV through the API?** API Gateway caps payloads (~10 MB) and times out (~29 s); our files are ~1 MB per 10k rows and growing. The API only mints a 5-minute presigned PUT (`lambdas/get_upload_url/handler.py`), and bytes go browser→S3 directly.
2. **How do you avoid processing the same file twice?** `claim_batch()` flips `uploaded`→`processing` only from `uploaded`, plus `ON CONFLICT` upserts on users/matches/products and unique constraints in `schema.sql`. Replays converge; the handler logs "already claimed, skipping".
3. **What happens if the Lambda crashes mid-file?** Earlier 1,000-row chunks stay committed, the batch stays `processing` (never fake-`done`), and `error_message` keeps the first error samples. An operator resets that one row to `uploaded` and re-runs.
4. **Why top-3 per user, and why score = 100 − rate?** One SQL statement (`ROW_NUMBER() ... rn <= 3`) replaces 10,000 app-level queries and produced 17k+ matches in milliseconds; cheapest rate first is the applicant-optimal ranking, encoded as a score.
5. **Why band users instead of judging each one with the LLM?** Cost and time: banding `(income/25k, score/50, employment)` collapses 10,000 users into ≤40 profiles (`LIMIT 40`), so a batch costs a handful of Groq calls, not thousands. Trade-off: edge users share a verdict.
6. **How do you stop the LLM from inventing matches?** Three gates: throwaway `p1…pn` labels with an `idMap` (model never sees real IDs), a UUID-regex + label-membership check in "Code in JavaScript2", and `ON CONFLICT DO NOTHING` on write. Score is fixed at 75, not model-chosen.
7. **Why does the crawler hash page text?** `criteria_hash` (sha256) is stored per product so re-crawls can detect real changes — though today nothing reads it back, so every run re-processes everything (listed as an improvement).
8. **Why do emails go to test aliases, and when are rows marked notified?** The demo must never mail real applicants, so `Email_template` routes to 3 plus-addressed inboxes. `notified=true` is written only after SES success, so failures retry instead of vanishing.
9. **What breaks when the tunnel URL changes?** `N8N_WEBHOOK_URL` is baked into Lambda env at deploy; a rotated tunnel gives `webhook failed: 404` in `error_message` while batches still complete. Fix: update `.env`, redeploy.
10. **What would you change for production?** Private VPC + Secrets Manager, pin UI origin in CORS, flip C to real addresses without `LIMIT 3`, activate stale-product deactivation in A, and move Exa/Groq keys from workflow JSON into n8n credentials (they're committed today — rotate them).
