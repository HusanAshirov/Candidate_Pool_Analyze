-- sql/01_schema.sql
-- IT Candidate Pool: base schema (PostgreSQL)
-- Flow: raw -> staging -> analytics (views) ; ref = lookup tables
-- Safe to re-run: uses IF NOT EXISTS everywhere.

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS ref;

------------------------------------------------------------
-- RAW: exactly what each source returned, one row per record per snapshot
------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw.records (
    id               BIGSERIAL PRIMARY KEY,
    source           TEXT        NOT NULL
                     CHECK (source IN ('hh_uz','hh_ru','linkedin','telegram','upwork','slack','referral')),
    record_type      TEXT        NOT NULL
                     CHECK (record_type IN ('resume','vacancy','post','profile','referral')),
    source_record_id TEXT        NOT NULL,          -- id on the platform (or message id for Telegram)
    payload          JSONB       NOT NULL,          -- original JSON / parsed fields
    collected_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    snapshot_date    DATE        NOT NULL DEFAULT current_date,  -- weekly snapshot key
    UNIQUE (source, source_record_id, snapshot_date)
);

CREATE INDEX IF NOT EXISTS ix_raw_records_source_snapshot
    ON raw.records (source, snapshot_date);

------------------------------------------------------------
-- STAGING: cleaned + normalized, same columns for every source
-- No names or contacts are stored here (personal data rule).
------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.candidates (
    candidate_id     BIGSERIAL PRIMARY KEY,
    raw_id           BIGINT REFERENCES raw.records(id) ON DELETE SET NULL,
    source           TEXT        NOT NULL,
    source_record_id TEXT        NOT NULL,
    record_type      TEXT        NOT NULL,
    title            TEXT,                          -- title as written by the candidate
    title_norm       TEXT,                          -- normalized role, e.g. 'Python Developer'
    level            TEXT CHECK (level IN ('intern','junior','middle','senior','lead')),
    skills           TEXT[]      NOT NULL DEFAULT '{}',   -- normalized, lowercase
    experience_years NUMERIC(4,1) CHECK (experience_years >= 0),
    salary           NUMERIC(14,2) CHECK (salary >= 0),
    currency         CHAR(3),                       -- ISO code: USD, UZS, RUB, EUR
    salary_usd       NUMERIC(12,2) CHECK (salary_usd >= 0),
    city             TEXT,
    country          CHAR(2) CHECK (country = upper(country)),  -- ISO: UZ, RU, KZ
    remote_ok        BOOLEAN,
    profile_date     DATE,                          -- when the profile/post was updated
    collected_at     TIMESTAMPTZ NOT NULL,
    snapshot_date    DATE        NOT NULL,
    person_key       TEXT,                          -- hash for cross-platform dedup (never raw contacts)
    UNIQUE (source, source_record_id, snapshot_date)
);

CREATE INDEX IF NOT EXISTS ix_cand_role_level  ON staging.candidates (title_norm, level);
CREATE INDEX IF NOT EXISTS ix_cand_snapshot    ON staging.candidates (snapshot_date);
CREATE INDEX IF NOT EXISTS ix_cand_country     ON staging.candidates (country);
CREATE INDEX IF NOT EXISTS ix_cand_person_key  ON staging.candidates (person_key);
CREATE INDEX IF NOT EXISTS ix_cand_skills_gin  ON staging.candidates USING GIN (skills);

------------------------------------------------------------
-- REF: lookup tables used by the cleaning pipeline
------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ref.currency_rates (
    currency     CHAR(3)        NOT NULL,
    rate_date    DATE           NOT NULL,
    usd_per_unit NUMERIC(18,8)  NOT NULL CHECK (usd_per_unit > 0),  -- 1 UZS = x USD
    PRIMARY KEY (currency, rate_date)
);

CREATE TABLE IF NOT EXISTS ref.skill_aliases (
    alias TEXT PRIMARY KEY,      -- lowercase variant, e.g. 'py', 'postgres'
    skill TEXT NOT NULL          -- canonical name, e.g. 'python', 'postgresql'
);

CREATE TABLE IF NOT EXISTS ref.role_aliases (
    keyword TEXT PRIMARY KEY,    -- lowercase keyword found in a title, e.g. 'django'
    role    TEXT NOT NULL        -- normalized role, e.g. 'Python Developer'
);