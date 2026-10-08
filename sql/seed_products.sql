-- seed_products.sql
-- Curated loan-product catalog for the loan-match pipeline.
--
-- These 4 products were ranked by measured match coverage against 10,000
-- real uploaded users (matches / avg score in comments). Together they cover
-- entry-level, broad mid-market, salaried-mid, and premium segments so a
-- fresh database never matches zero rows.
--
-- Idempotent: safe to run multiple times. Rows are matched on the
-- uq_product_source (product_name, source) constraint; re-running updates
-- the criteria in place instead of duplicating. product_id is left to the
-- sequence (no matches exist yet on a fresh DB, so stable IDs don't matter).
--
-- Usage:
--   psql -U loan_user -d loan_engine -f sql/seed_products.sql
--
-- Products are listed best-coverage first.

-- 1. Basic Personal Loan (seed) — 10,000 matches, avg score 85.50.
--    Broadest mid-market product: low income bar, wide age band, three
--    employment types. The backbone of the catalog; keep active.
INSERT INTO loan_products
    (product_name, source, source_url, interest_rate,
     min_income, min_credit_score, max_credit_score, min_age, max_age,
     employment_status, is_active, criteria_text, criteria_hash, needs_llm_check)
VALUES
    ('Basic Personal Loan', 'seed', NULL, 14.50,
     15000.00, 650, NULL, 21, 60,
     ARRAY['salaried', 'self-employed', 'business'], TRUE,
     'Standard criteria', NULL, FALSE)
ON CONFLICT (product_name, source) DO UPDATE SET
    source_url = EXCLUDED.source_url,
    interest_rate = EXCLUDED.interest_rate,
    min_income = EXCLUDED.min_income,
    min_credit_score = EXCLUDED.min_credit_score,
    max_credit_score = EXCLUDED.max_credit_score,
    min_age = EXCLUDED.min_age,
    max_age = EXCLUDED.max_age,
    employment_status = EXCLUDED.employment_status,
    is_active = EXCLUDED.is_active,
    criteria_text = EXCLUDED.criteria_text,
    criteria_hash = EXCLUDED.criteria_hash,
    needs_llm_check = EXCLUDED.needs_llm_check,
    last_crawled_at = now();

-- 2. Starter Loan (seed) — 6,466 matches, avg score 82.00.
--    Entry-level safety net: lowest income/credit bars, open to ALL
--    employment types (NULL filter). Catches users nothing else matches.
INSERT INTO loan_products
    (product_name, source, source_url, interest_rate,
     min_income, min_credit_score, max_credit_score, min_age, max_age,
     employment_status, is_active, criteria_text, criteria_hash, needs_llm_check)
VALUES
    ('Starter Loan', 'seed', NULL, 18.00,
     10000.00, 600, 749, 21, 65,
     NULL, TRUE,
     'Open to all employment types', NULL, FALSE)
ON CONFLICT (product_name, source) DO UPDATE SET
    source_url = EXCLUDED.source_url,
    interest_rate = EXCLUDED.interest_rate,
    min_income = EXCLUDED.min_income,
    min_credit_score = EXCLUDED.min_credit_score,
    max_credit_score = EXCLUDED.max_credit_score,
    min_age = EXCLUDED.min_age,
    max_age = EXCLUDED.max_age,
    employment_status = EXCLUDED.employment_status,
    is_active = EXCLUDED.is_active,
    criteria_text = EXCLUDED.criteria_text,
    criteria_hash = EXCLUDED.criteria_hash,
    needs_llm_check = EXCLUDED.needs_llm_check,
    last_crawled_at = now();

-- 3. SBI Personal Loan (sbi.bank.in) — 3,389 matches, avg score 80.00.
--    Real crawled product (https://sbi.bank.in/web/faq-s/faq-personal-loan).
--    Salaried-only mid-market. Refresh criteria from the source page when
--    the crawler updates it; do not hand-edit the thresholds.
INSERT INTO loan_products
    (product_name, source, source_url, interest_rate,
     min_income, min_credit_score, max_credit_score, min_age, max_age,
     employment_status, is_active, criteria_text, criteria_hash, needs_llm_check)
VALUES
    ('SBI Personal Loan', 'sbi.bank.in',
     'https://sbi.bank.in/web/faq-s/faq-personal-loan', NULL,
     20000.00, 650, NULL, NULL, 60,
     ARRAY['salaried'], TRUE,
     'Minimum Salary required for availing a Personal Loan is ₹ 20', NULL, FALSE)
ON CONFLICT (product_name, source) DO UPDATE SET
    source_url = EXCLUDED.source_url,
    interest_rate = EXCLUDED.interest_rate,
    min_income = EXCLUDED.min_income,
    min_credit_score = EXCLUDED.min_credit_score,
    max_credit_score = EXCLUDED.max_credit_score,
    min_age = EXCLUDED.min_age,
    max_age = EXCLUDED.max_age,
    employment_status = EXCLUDED.employment_status,
    is_active = EXCLUDED.is_active,
    criteria_text = EXCLUDED.criteria_text,
    criteria_hash = EXCLUDED.criteria_hash,
    needs_llm_check = EXCLUDED.needs_llm_check,
    last_crawled_at = now();

-- 4. Premium Personal Loan (seed) — 759 matches, avg score 75.00.
--    Niche high-end product: high income + 750 score + salaried only, and it
--    carries needs_llm_check so borderline applicants get LLM review instead
--    of a hard SQL reject. Low volume by design; keep thresholds strict.
INSERT INTO loan_products
    (product_name, source, source_url, interest_rate,
     min_income, min_credit_score, max_credit_score, min_age, max_age,
     employment_status, is_active, criteria_text, criteria_hash, needs_llm_check)
VALUES
    ('Premium Personal Loan', 'seed', NULL, 10.75,
     50000.00, 750, NULL, 25, 58,
     ARRAY['salaried'], TRUE,
     'Salaried applicant with stable income. Income should comfortably cover EMI, at least 3x a typical 15000 EMI. Credit score should show disciplined repayment.',
     NULL, TRUE)
ON CONFLICT (product_name, source) DO UPDATE SET
    source_url = EXCLUDED.source_url,
    interest_rate = EXCLUDED.interest_rate,
    min_income = EXCLUDED.min_income,
    min_credit_score = EXCLUDED.min_credit_score,
    max_credit_score = EXCLUDED.max_credit_score,
    min_age = EXCLUDED.min_age,
    max_age = EXCLUDED.max_age,
    employment_status = EXCLUDED.employment_status,
    is_active = EXCLUDED.is_active,
    criteria_text = EXCLUDED.criteria_text,
    criteria_hash = EXCLUDED.criteria_hash,
    needs_llm_check = EXCLUDED.needs_llm_check,
    last_crawled_at = now();
