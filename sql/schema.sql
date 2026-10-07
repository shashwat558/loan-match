CREATE TABLE IF NOT EXISTS upload_batches (
    batch_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    s3_key             TEXT,
    status             TEXT NOT NULL DEFAULT 'uploaded' CHECK (status IN ('uploaded', 'processing', 'done', 'failed')),
    total_rows         INTEGER NOT NULL DEFAULT 0,
    inserted_rows      INTEGER NOT NULL DEFAULT 0,
    skipped_rows       INTEGER NOT NULL DEFAULT 0,
    error_message      TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);



CREATE TABLE IF NOT EXISTS users (
    user_id            UUID PRIMARY KEY,
    email              TEXT NOT NULL,
    name               TEXT NOT NULL,
    monthly_income     NUMERIC(12, 2) NOT NULL CHECK (monthly_income >=0),
    credit_score       INTEGER NOT NULL CHECK (credit_score BETWEEN 300 AND 900),
    employment_status  TEXT NOT NULL,
    age                INTEGER NOT NULL CHECK (age BETWEEN 18 AND 100),
    batch_id           UUID REFERENCES upload_batches (batch_id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()

);

CREATE TABLE IF NOT EXISTS loan_products (
    product_id         BIGSERIAL PRIMARY KEY,
    product_name       TEXT NOT NULL,
    source             TEXT NOT NULL,
    source_url         TEXT,
    interest_rate      NUMERIC(5, 2),
    min_income         NUMERIC(12, 2),
    min_credit_score   INTEGER,
    max_credit_score   INTEGER,
    min_age            INTEGER,
    max_age            INTEGER,
    employment_status  TEXT[],
    is_active          BOOLEAN NOT NULL DEFAULT TRUE,
    criteria_text      TEXT,
    criteria_hash      TEXT,
    last_crawled_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT         uq_product_source UNIQUE (product_name, source)

);

CREATE TABLE IF NOT EXISTS matches (
    match_id          BIGSERIAL PRIMARY KEY,
    user_id     UUID  NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    product_id  BIGINT NOT NULL REFERENCES loan_products (product_id) ON DELETE CASCADE,
    match_stage TEXT NOT NULL DEFAULT 'sql' CHECK (match_stage IN ('sql', 'rules', 'llm')),
    score       NUMERIC(6, 2),
    notified    BOOLEAN NOT NULL DEFAULT FALSE,
    notified_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_match_user_product UNIQUE (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_matches_unnotified
    ON matches (user_id) where notified = FALSE;

CREATE INDEX IF NOT EXISTS idx_products_filter
    ON loan_products (min_income, min_credit_score, max_credit_score);

CREATE INDEX IF NOT EXISTS idx_users_batch_id ON users (batch_id);

CREATE INDEX IF NOT EXISTS idx_users_income_score
    ON users (credit_score, monthly_income);
