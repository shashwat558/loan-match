CREATE TABLE IF NOT EXISTS users (
    user_id            TEXT PRIMARY KEY,
    email              TEXT NOT NULL,
    monthly_income     NUMERIC(12, 2) NOT NULL CHECK (monthly_income >=0),
    credit_score       INTEGER NOT NULL CHECK (credit_score BETWEEN 300 AND 900),
    employment_status  TEXT NOT NULL,
    age                INTEGER NOT NULL CHECK (age BETWEEN 18 AND 100),
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
    last_crawled_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()

);

CREATE TABLE IF NOT EXISTS matches (
    match_id          BIGSERIAL PRIMARY KEY,
    user_id     TEXT   NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    product_id  BIGINT NOT NULL REFERENCES loan_products (product_id) ON DELETE CASCADE,
    match_stage TEXT NOT NULL DEFAULT 'sql' CHECK (match_stage IN ('sql', 'rules', 'llm')),
    score       NUMERIC(6, 2),
    notified    BOOLEAN NOT NULL DEFAULT FALSE,
    notified_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_match_user_product UNIQUE (user_id, product_id)
);
