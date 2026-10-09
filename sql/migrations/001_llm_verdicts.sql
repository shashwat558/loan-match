-- 001_llm_verdicts.sql
-- Cache for LLM eligibility verdicts so repeat batches don't re-judge
-- identical (product, profile) pairs.
--
-- Key design: product_key is the product's criteria_hash when present,
-- otherwise 'product:<product_id>' (seed rows have NULL hashes). When a
-- crawler run changes a product's text, its hash changes, old rows stop
-- matching lookups, and a periodic prune deletes the orphans:
--   DELETE FROM llm_verdicts WHERE decided_at < now() - interval '90 days';
--
-- Safe to run multiple times (IF NOT EXISTS). Apply to every database:
--   psql ... -f sql/migrations/001_llm_verdicts.sql

CREATE TABLE IF NOT EXISTS llm_verdicts (
    product_key   TEXT NOT NULL,
    product_id    BIGINT NOT NULL REFERENCES loan_products (product_id) ON DELETE CASCADE,
    income_band   INTEGER NOT NULL,
    score_band    INTEGER NOT NULL,
    employment    TEXT NOT NULL,
    eligible      BOOLEAN NOT NULL,
    decided_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_verdict UNIQUE (product_key, income_band, score_band, employment)
);

CREATE INDEX IF NOT EXISTS idx_verdicts_lookup
    ON llm_verdicts (product_key, income_band, score_band, employment);
