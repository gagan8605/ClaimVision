BEGIN;

-- ==========================
-- Load Customer Dimension
-- ==========================

INSERT INTO dim_customers
(
    age,
    insured_sex,
    insured_education_level,
    insured_occupation,
    insured_hobbies,
    insured_relationship,
    capital_gains,
    capital_loss,
    insured_zip,
    created_at
)
SELECT
    age,
    insured_sex,
    insured_education_level,
    insured_occupation,
    insured_hobbies,
    insured_relationship,
    "capital-gains",
    "capital-loss",
    insured_zip,
    policy_bind_date
FROM staging_insurance
ORDER BY policy_number;


-- ==========================
-- Load Policy Dimension
-- ==========================

INSERT INTO dim_policies
(
    policy_number,
    customer_id,
    months_as_customer,
    policy_bind_date,
    policy_state,
    policy_csl,
    policy_deductable,
    policy_annual_premium,
    umbrella_limit,
    created_at
)
SELECT
    s.policy_number,
    c.customer_id,
    s.months_as_customer,
    s.policy_bind_date,
    s.policy_state,
    s.policy_csl,
    s.policy_deductable,
    s.policy_annual_premium,
    s.umbrella_limit,
    NOW()
FROM staging_insurance s
JOIN dim_customers c
ON c.age = s.age
AND c.insured_zip = s.insured_zip
ORDER BY s.policy_number;


-- ==========================
-- Load Vehicle Dimension
-- ==========================

INSERT INTO dim_vehicles
(
    policy_number,
    auto_make,
    auto_model,
    auto_year
)
SELECT
    policy_number,
    auto_make,
    auto_model,
    auto_year
FROM staging_insurance
ORDER BY policy_number;


-- ==========================
-- Load Incident Fact
-- ==========================

INSERT INTO fact_incidents
(
    policy_number,
    incident_date,
    incident_type,
    collision_type,
    incident_severity,
    authorities_contacted,
    incident_state,
    incident_city,
    incident_location,
    incident_hour_of_the_day,
    number_of_vehicles_involved,
    property_damage,
    bodily_injuries,
    witnesses,
    police_report_available,
    created_at
)
SELECT
    policy_number,
    incident_date,
    incident_type,
    NULLIF(collision_type,'?'),
    incident_severity,
    NULLIF(authorities_contacted,'?'),
    incident_state,
    incident_city,
    incident_location,
    incident_hour_of_the_day,
    number_of_vehicles_involved,
    CASE
        WHEN property_damage='YES' THEN TRUE
        WHEN property_damage='NO' THEN FALSE
        ELSE NULL
    END,
    bodily_injuries,
    witnesses,
    CASE
        WHEN police_report_available='YES' THEN TRUE
        WHEN police_report_available='NO' THEN FALSE
        ELSE NULL
    END,
    NOW()
FROM staging_insurance
ORDER BY policy_number;


-- ==========================
-- Load Claims Fact
-- ==========================

INSERT INTO fact_claims
(
    policy_number,
    incident_id,
    total_claim_amount,
    injury_claim,
    property_claim,
    vehicle_claim,
    fraud_reported,
    claim_status,
    created_at
)
SELECT
    s.policy_number,
    i.incident_id,
    s.total_claim_amount,
    s.injury_claim,
    s.property_claim,
    s.vehicle_claim,
    CASE
        WHEN s.fraud_reported='Y' THEN TRUE
        ELSE FALSE
    END,
    CASE
        WHEN s.fraud_reported='Y' THEN 'Denied'
        ELSE 'Approved'
    END,
    NOW()
FROM staging_insurance s
JOIN fact_incidents i
ON i.policy_number = s.policy_number
ORDER BY s.policy_number;

COMMIT;