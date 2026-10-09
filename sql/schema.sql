--
-- PostgreSQL database dump
--

\restrict NfPcdZqyxI1aQLvtod1kv6cyf0j9kvNFFiHv7mvo4zosFQHwbm96bXnFM0c6AsA

-- Dumped from database version 16.15
-- Dumped by pg_dump version 16.15

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: loan_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loan_products (
    product_id bigint NOT NULL,
    product_name text NOT NULL,
    source text NOT NULL,
    source_url text,
    interest_rate numeric(5,2),
    min_income numeric(12,2),
    min_credit_score integer,
    max_credit_score integer,
    min_age integer,
    max_age integer,
    employment_status text[],
    is_active boolean DEFAULT true NOT NULL,
    criteria_text text,
    criteria_hash text,
    last_crawled_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    needs_llm_check boolean DEFAULT false NOT NULL
);


--
-- Name: loan_products_product_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.loan_products_product_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: loan_products_product_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.loan_products_product_id_seq OWNED BY public.loan_products.product_id;


--
-- Name: matches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.matches (
    match_id bigint NOT NULL,
    user_id uuid NOT NULL,
    product_id bigint NOT NULL,
    match_stage text DEFAULT 'sql'::text NOT NULL,
    score numeric(6,2),
    notified boolean DEFAULT false NOT NULL,
    notified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT matches_match_stage_check CHECK ((match_stage = ANY (ARRAY['sql'::text, 'rules'::text, 'llm'::text])))
);


--
-- Name: matches_match_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.matches_match_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: matches_match_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.matches_match_id_seq OWNED BY public.matches.match_id;


--
-- Name: upload_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.upload_batches (
    batch_id uuid DEFAULT gen_random_uuid() NOT NULL,
    s3_key text,
    status text DEFAULT 'uploaded'::text NOT NULL,
    total_rows integer DEFAULT 0 NOT NULL,
    inserted_rows integer DEFAULT 0 NOT NULL,
    skipped_rows integer DEFAULT 0 NOT NULL,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT upload_batches_status_check CHECK ((status = ANY (ARRAY['uploaded'::text, 'processing'::text, 'done'::text, 'failed'::text])))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    user_id uuid NOT NULL,
    email text NOT NULL,
    name text NOT NULL,
    monthly_income numeric(12,2) NOT NULL,
    credit_score integer NOT NULL,
    employment_status text NOT NULL,
    age integer NOT NULL,
    batch_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT users_age_check CHECK (((age >= 18) AND (age <= 100))),
    CONSTRAINT users_credit_score_check CHECK (((credit_score >= 300) AND (credit_score <= 900))),
    CONSTRAINT users_monthly_income_check CHECK ((monthly_income >= (0)::numeric))
);


--
-- Name: loan_products product_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_products ALTER COLUMN product_id SET DEFAULT nextval('public.loan_products_product_id_seq'::regclass);


--
-- Name: matches match_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matches ALTER COLUMN match_id SET DEFAULT nextval('public.matches_match_id_seq'::regclass);


--
-- Name: loan_products loan_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_products
    ADD CONSTRAINT loan_products_pkey PRIMARY KEY (product_id);


--
-- Name: matches matches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_pkey PRIMARY KEY (match_id);


--
-- Name: upload_batches upload_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_batches
    ADD CONSTRAINT upload_batches_pkey PRIMARY KEY (batch_id);


--
-- Name: matches uq_match_user_product; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT uq_match_user_product UNIQUE (user_id, product_id);


--
-- Name: loan_products uq_product_source; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_products
    ADD CONSTRAINT uq_product_source UNIQUE (product_name, source);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: idx_matches_unnotified; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_matches_unnotified ON public.matches USING btree (user_id) WHERE (notified = false);


--
-- Name: idx_products_filter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_filter ON public.loan_products USING btree (min_income, min_credit_score, max_credit_score);


--
-- Name: idx_users_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_batch_id ON public.users USING btree (batch_id);


--
-- Name: idx_users_income_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_income_score ON public.users USING btree (credit_score, monthly_income);


--
-- Name: matches matches_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.loan_products(product_id) ON DELETE CASCADE;


--
-- Name: matches matches_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: users users_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.upload_batches(batch_id);


--
-- LLM verdict cache (see sql/migrations/001_llm_verdicts.sql).
-- IF NOT EXISTS so re-applying the schema never fails.
--

CREATE TABLE IF NOT EXISTS public.llm_verdicts (
    product_key text NOT NULL,
    product_id bigint NOT NULL REFERENCES public.loan_products(product_id) ON DELETE CASCADE,
    income_band integer NOT NULL,
    score_band integer NOT NULL,
    employment text NOT NULL,
    eligible boolean NOT NULL,
    decided_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT uq_verdict UNIQUE (product_key, income_band, score_band, employment)
);

CREATE INDEX IF NOT EXISTS idx_verdicts_lookup
    ON public.llm_verdicts USING btree (product_key, income_band, score_band, employment);


--
-- PostgreSQL database dump complete
--

\unrestrict NfPcdZqyxI1aQLvtod1kv6cyf0j9kvNFFiHv7mvo4zosFQHwbm96bXnFM0c6AsA

