-- =====================================================================
-- Insurance Claims Analytics — PostgreSQL DDL Schema
-- Source: Auto Insurance Claims Data (Kaggle, buntyshah)
-- Design: Star-ish 3NF — dim_customers, dim_policies, dim_vehicles
--         feed fact_incidents and fact_claims.
--
-- Notes / assumptions (see ETL script for full data-quality log):
--   * The raw CSV has 1 row = 1 policy = 1 customer = 1 incident = 1 claim.
--     There is no repeated-customer key in the source data, so
--     customer_id is a surrogate generated during ETL (1:1 with policy
--     for this dataset, but modeled separately since a real insurer's
--     customer table would NOT be 1:1 with policies).
--   * claim_status is DERIVED, not present in source data:
--       fraud_reported = 'Y' -> 'Denied'
--       fraud_reported = 'N' -> 'Approved'
--     This is a simplifying assumption for demo purposes and is
--     documented here and in the ETL script — it is not a real
--     claims-adjudication outcome.
--   * '?' placeholders in collision_type / property_damage /
--     police_report_available are converted to NULL during ETL.
-- =====================================================================

DROP TABLE IF EXISTS fact_claims CASCADE;
DROP TABLE IF EXISTS fact_incidents CASCADE;
DROP TABLE IF EXISTS dim_vehicles CASCADE;
DROP TABLE IF EXISTS dim_policies CASCADE;
DROP TABLE IF EXISTS dim_customers CASCADE;

-- ---------------------------------------------------------------------
-- dim_customers: demographic attributes of the insured
-- ---------------------------------------------------------------------
CREATE TABLE dim_customers (
    customer_id             SERIAL PRIMARY KEY,
    age                     SMALLINT       NOT NULL CHECK (age BETWEEN 16 AND 100),
    insured_sex             VARCHAR(10)    NOT NULL CHECK (insured_sex IN ('MALE', 'FEMALE')),
    insured_education_level VARCHAR(50)    NOT NULL,
    insured_occupation      VARCHAR(50)    NOT NULL,
    insured_hobbies         VARCHAR(50)    NOT NULL,
    insured_relationship    VARCHAR(50)    NOT NULL,
    capital_gains           INTEGER        NOT NULL DEFAULT 0,
    capital_loss            INTEGER        NOT NULL DEFAULT 0,
    insured_zip             VARCHAR(10)    NOT NULL,
    created_at              TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- dim_policies: policy terms and coverage
-- ---------------------------------------------------------------------
CREATE TABLE dim_policies (
    policy_id               SERIAL PRIMARY KEY,
    policy_number           BIGINT         NOT NULL UNIQUE,
    customer_id             INTEGER        NOT NULL REFERENCES dim_customers(customer_id),
    months_as_customer      INTEGER        NOT NULL CHECK (months_as_customer >= 0),
    policy_bind_date        DATE           NOT NULL,
    policy_state            CHAR(2)        NOT NULL,
    policy_csl              VARCHAR(20)    NOT NULL,   -- Combined Single Limit e.g. '250/500'
    policy_deductable       INTEGER        NOT NULL CHECK (policy_deductable >= 0),
    policy_annual_premium   NUMERIC(10,2)  NOT NULL CHECK (policy_annual_premium >= 0),
    umbrella_limit          BIGINT         NOT NULL,   -- can legitimately be negative in source data; flagged not corrected
    created_at              TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- dim_vehicles: vehicle associated with the policy/claim
-- ---------------------------------------------------------------------
CREATE TABLE dim_vehicles (
    vehicle_id              SERIAL PRIMARY KEY,
    policy_number           BIGINT         NOT NULL REFERENCES dim_policies(policy_number),
    auto_make                VARCHAR(50)   NOT NULL,
    auto_model                VARCHAR(50)  NOT NULL,
    auto_year                SMALLINT      NOT NULL CHECK (auto_year BETWEEN 1980 AND 2030),
    created_at               TIMESTAMP     NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- fact_incidents: the loss event that triggers a claim
-- ---------------------------------------------------------------------
CREATE TABLE fact_incidents (
    incident_id              SERIAL PRIMARY KEY,
    policy_number            BIGINT        NOT NULL REFERENCES dim_policies(policy_number),
    incident_date             DATE         NOT NULL,
    incident_type             VARCHAR(50)  NOT NULL,
    collision_type             VARCHAR(50) NULL,        -- NULL = '?' in source (not applicable, e.g. theft)
    incident_severity          VARCHAR(50) NOT NULL,
    authorities_contacted       VARCHAR(50) NULL,
    incident_state              CHAR(2)    NOT NULL,
    incident_city                VARCHAR(50) NOT NULL,
    incident_location             VARCHAR(200) NOT NULL,
    incident_hour_of_the_day       SMALLINT NOT NULL CHECK (incident_hour_of_the_day BETWEEN 0 AND 23),
    number_of_vehicles_involved    SMALLINT NOT NULL CHECK (number_of_vehicles_involved >= 0),
    property_damage                  BOOLEAN NULL,      -- NULL = '?' in source
    bodily_injuries                  SMALLINT NOT NULL CHECK (bodily_injuries >= 0),
    witnesses                        SMALLINT NOT NULL CHECK (witnesses >= 0),
    police_report_available            BOOLEAN NULL,    -- NULL = '?' in source
    created_at                        TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- fact_claims: the financial claim tied to an incident
-- ---------------------------------------------------------------------
CREATE TABLE fact_claims (
    claim_id                 SERIAL PRIMARY KEY,
    policy_number            BIGINT        NOT NULL REFERENCES dim_policies(policy_number),
    incident_id              INTEGER       NOT NULL REFERENCES fact_incidents(incident_id),
    total_claim_amount       NUMERIC(12,2) NOT NULL CHECK (total_claim_amount >= 0),
    injury_claim              NUMERIC(12,2) NOT NULL CHECK (injury_claim >= 0),
    property_claim              NUMERIC(12,2) NOT NULL CHECK (property_claim >= 0),
    vehicle_claim                 NUMERIC(12,2) NOT NULL CHECK (vehicle_claim >= 0),
    fraud_reported                  BOOLEAN NOT NULL,
    claim_status                      VARCHAR(10) NOT NULL CHECK (claim_status IN ('Approved', 'Denied')),
    created_at                       TIMESTAMP NOT NULL DEFAULT NOW(),

    -- integrity check confirmed on the raw data: parts always sum to total
    CONSTRAINT chk_claim_sum CHECK (
        total_claim_amount = injury_claim + property_claim + vehicle_claim
    )
);

-- =====================================================================
-- Indexes — chosen for the query patterns in 02_analysis_queries.sql
-- (fraud trend, regional drill-through, joins on FK columns)
-- =====================================================================

-- FK lookups
CREATE INDEX idx_policies_customer_id      ON dim_policies(customer_id);
CREATE INDEX idx_vehicles_policy_number    ON dim_vehicles(policy_number);
CREATE INDEX idx_incidents_policy_number   ON fact_incidents(policy_number);
CREATE INDEX idx_claims_policy_number      ON fact_claims(policy_number);
CREATE INDEX idx_claims_incident_id        ON fact_claims(incident_id);

-- Common filter/group-by columns for analytics + dashboard queries
CREATE INDEX idx_incidents_date            ON fact_incidents(incident_date);
CREATE INDEX idx_incidents_state           ON fact_incidents(incident_state);
CREATE INDEX idx_incidents_severity        ON fact_incidents(incident_severity);
CREATE INDEX idx_claims_fraud_reported     ON fact_claims(fraud_reported);
CREATE INDEX idx_claims_status             ON fact_claims(claim_status);
CREATE INDEX idx_policies_state            ON dim_policies(policy_state);
CREATE INDEX idx_policies_bind_date        ON dim_policies(policy_bind_date);

-- Composite index for the "fraud trend by month" dashboard query
CREATE INDEX idx_incidents_date_state      ON fact_incidents(incident_date, incident_state);

-- =====================================================================
-- End of schema
-- =====================================================================
