SELECT
    COUNT(*) AS total_claims,
    ROUND(AVG(total_claim_amount), 2) AS avg_claim_amount,
    ROUND(100.0 * SUM(CASE WHEN fraud_reported THEN 1 ELSE 0 END) / COUNT(*), 2) AS fraud_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN claim_status = 'Approved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS approval_rate_pct
FROM fact_claims;

SELECT
    i.incident_severity,
    COUNT(*) AS claim_count,
    ROUND(AVG(c.total_claim_amount),2) AS avg_claim_amount,
    ROUND(SUM(c.total_claim_amount),2) AS total_claim_amount
FROM fact_claims c
JOIN fact_incidents i ON c.incident_id = i.incident_id
GROUP BY i.incident_severity
ORDER BY total_claim_amount DESC;

SELECT
    p.policy_state,
    COUNT(*) AS total_claims,
    SUM(CASE WHEN c.fraud_reported THEN 1 ELSE 0 END) AS fraud_claims,
    ROUND(100.0 * SUM(CASE WHEN c.fraud_reported THEN 1 ELSE 0 END) / COUNT(*), 2) AS fraud_rate_pct
FROM fact_claims c
JOIN dim_policies p ON c.policy_number = p.policy_number
GROUP BY p.policy_state
ORDER BY fraud_rate_pct DESC;

SELECT
    p.policy_csl,
    COUNT(*) AS policy_count,
    ROUND(AVG(p.policy_annual_premium), 2) AS avg_annual_premium,
    ROUND(AVG(c.total_claim_amount), 2) AS avg_claim_amount
FROM dim_policies p
JOIN fact_claims c ON p.policy_number = c.policy_number
GROUP BY p.policy_csl
HAVING COUNT(*) > 50
ORDER BY avg_claim_amount DESC;

SELECT
    DATE_TRUNC('month', i.incident_date)::date AS claim_month,
    COUNT(*) AS claim_count,
    ROUND(SUM(c.total_claim_amount), 2) AS total_claim_amount,
    ROUND(100.0 * SUM(CASE WHEN c.fraud_reported THEN 1 ELSE 0 END) / COUNT(*), 2) AS fraud_rate_pct
FROM fact_claims c
JOIN fact_incidents i ON c.incident_id = i.incident_id
GROUP BY 1
ORDER BY 1;

SELECT
    cl.claim_id,
    cu.customer_id,
    cu.age,
    cu.insured_sex,
    cu.insured_occupation,
    p.policy_number,
    p.policy_state,
    p.policy_csl,
    p.policy_annual_premium,
    v.auto_make,
    v.auto_model,
    v.auto_year,
    i.incident_date,
    i.incident_type,
    i.incident_severity,
    i.incident_state,
    cl.total_claim_amount,
    cl.fraud_reported,
    cl.claim_status
FROM fact_claims cl
JOIN dim_policies  p  ON cl.policy_number = p.policy_number
JOIN dim_customers cu ON p.customer_id    = cu.customer_id
JOIN dim_vehicles  v  ON p.policy_number  = v.policy_number
JOIN fact_incidents i ON cl.incident_id   = i.incident_id
ORDER BY cl.claim_id
LIMIT 100;

SELECT i.incident_id, i.policy_number
FROM fact_incidents i
LEFT JOIN fact_claims c ON i.incident_id = c.incident_id
WHERE c.claim_id IS NULL;

SELECT
    v.auto_make,
    v.auto_model,
    COUNT(*) AS claim_count,
    ROUND(AVG(c.total_claim_amount), 2) AS avg_claim_amount
FROM dim_vehicles v
JOIN fact_claims c ON v.policy_number = c.policy_number
GROUP BY v.auto_make, v.auto_model
HAVING COUNT(*) >= 5
ORDER BY avg_claim_amount DESC
LIMIT 10;

SELECT
    cu.customer_id,
    cu.insured_occupation,
    cl.total_claim_amount,
    occ_avg.avg_amount_in_occupation
FROM fact_claims cl
JOIN dim_policies p ON cl.policy_number = p.policy_number
JOIN dim_customers cu ON p.customer_id = cu.customer_id
JOIN (
    SELECT cu2.insured_occupation, ROUND(AVG(cl2.total_claim_amount), 2) AS avg_amount_in_occupation
    FROM fact_claims cl2
    JOIN dim_policies p2 ON cl2.policy_number = p2.policy_number
    JOIN dim_customers cu2 ON p2.customer_id = cu2.customer_id
    GROUP BY cu2.insured_occupation
) occ_avg ON cu.insured_occupation = occ_avg.insured_occupation
WHERE cl.total_claim_amount > occ_avg.avg_amount_in_occupation
ORDER BY cl.total_claim_amount DESC
LIMIT 20;

WITH state_fraud AS (
    SELECT
        p.policy_state,
        COUNT(*) AS total_claims,
        SUM(CASE WHEN c.fraud_reported THEN 1 ELSE 0 END) AS fraud_claims
    FROM fact_claims c
    JOIN dim_policies p ON c.policy_number = p.policy_number
    GROUP BY p.policy_state
),
overall_rate AS (
    SELECT 100.0 * SUM(fraud_claims) / SUM(total_claims) AS avg_fraud_rate_pct
    FROM state_fraud
)
SELECT
    sf.policy_state,
    sf.total_claims,
    sf.fraud_claims,
    ROUND(100.0 * sf.fraud_claims / sf.total_claims, 2) AS state_fraud_rate_pct,
    ROUND(o.avg_fraud_rate_pct, 2) AS overall_fraud_rate_pct
FROM state_fraud sf
CROSS JOIN overall_rate o
WHERE 100.0 * sf.fraud_claims / sf.total_claims > o.avg_fraud_rate_pct
ORDER BY state_fraud_rate_pct DESC;

WITH monthly AS (
    SELECT
        DATE_TRUNC('month', i.incident_date)::date AS claim_month,
        COUNT(*) AS claim_count,
        SUM(c.total_claim_amount) AS total_amount
    FROM fact_claims c
    JOIN fact_incidents i ON c.incident_id = i.incident_id
    GROUP BY 1
),
with_prior AS (
    SELECT
        claim_month,
        claim_count,
        total_amount,
        LAG(claim_count) OVER (ORDER BY claim_month) AS prior_month_count,
        LAG(total_amount) OVER (ORDER BY claim_month) AS prior_month_amount
    FROM monthly
)
SELECT
    claim_month,
    claim_count,
    total_amount,
    prior_month_count,
    CASE
        WHEN prior_month_count IS NULL OR prior_month_count = 0 THEN NULL
        ELSE ROUND(100.0 * (claim_count - prior_month_count) / prior_month_count, 2)
    END AS mom_volume_change_pct
FROM with_prior
ORDER BY claim_month;

WITH claim_median AS (
    SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_claim_amount) AS median_amount
    FROM fact_claims
)
SELECT
    cl.claim_id,
    cl.policy_number,
    cl.total_claim_amount,
    cm.median_amount
FROM fact_claims cl
CROSS JOIN claim_median cm
WHERE cl.total_claim_amount > cm.median_amount
ORDER BY cl.total_claim_amount DESC
LIMIT 20;

WITH tiered AS (
    SELECT
        claim_id,
        total_claim_amount,
        CASE
            WHEN total_claim_amount < 5000 THEN 'Low'
            WHEN total_claim_amount < 30000 THEN 'Medium'
            ELSE 'High'
        END AS claim_tier
    FROM fact_claims
)
SELECT
    claim_tier,
    COUNT(*) AS claim_count,
    ROUND(AVG(total_claim_amount), 2) AS avg_amount_in_tier,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_all_claims
FROM tiered
GROUP BY claim_tier
ORDER BY avg_amount_in_tier;

SELECT
    i.incident_state,
    c.claim_id,
    c.total_claim_amount,
    RANK() OVER (PARTITION BY i.incident_state ORDER BY c.total_claim_amount DESC) AS rank_in_state
FROM fact_claims c
JOIN fact_incidents i ON c.incident_id = i.incident_id
ORDER BY i.incident_state, rank_in_state
LIMIT 30;

SELECT
    i.incident_date,
    c.claim_id,
    c.total_claim_amount,
    SUM(c.total_claim_amount) OVER (ORDER BY i.incident_date, c.claim_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total_claim_amount
FROM fact_claims c
JOIN fact_incidents i ON c.incident_id = i.incident_id
ORDER BY i.incident_date, c.claim_id
LIMIT 30;

SELECT
    policy_number,
    policy_annual_premium,
    NTILE(4) OVER (ORDER BY policy_annual_premium) AS premium_quartile
FROM dim_policies
ORDER BY policy_annual_premium DESC
LIMIT 30;

WITH monthly AS (
    SELECT
        DATE_TRUNC('month', i.incident_date)::date AS claim_month,
        COUNT(*) AS claim_count
    FROM fact_claims c
    JOIN fact_incidents i ON c.incident_id = i.incident_id
    GROUP BY 1
)
SELECT
    claim_month,
    claim_count,
    ROUND(AVG(claim_count) OVER (
        ORDER BY claim_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_3mo
FROM monthly
ORDER BY claim_month;

CREATE OR REPLACE FUNCTION get_fraud_rate_by_state(p_state CHAR(2))
RETURNS TABLE (
    policy_state CHAR(2),
    total_claims BIGINT,
    fraud_claims BIGINT,
    fraud_rate_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.policy_state,
        COUNT(*)::BIGINT AS total_claims,
        SUM(CASE WHEN c.fraud_reported THEN 1 ELSE 0 END)::BIGINT AS fraud_claims,
        ROUND(100.0 * SUM(CASE WHEN c.fraud_reported THEN 1 ELSE 0 END) / COUNT(*), 2) AS fraud_rate_pct
    FROM fact_claims c
    JOIN dim_policies p ON c.policy_number = p.policy_number
    WHERE p.policy_state = p_state
    GROUP BY p.policy_state;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE refresh_claim_status()
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE fact_claims
    SET claim_status = CASE WHEN fraud_reported THEN 'Denied' ELSE 'Approved' END
    WHERE claim_status IS DISTINCT FROM (CASE WHEN fraud_reported THEN 'Denied' ELSE 'Approved' END);

    RAISE NOTICE 'claim_status refreshed for all fact_claims rows.';
END;
$$;

CREATE OR REPLACE FUNCTION get_kpi_snapshot(p_start_date DATE, p_end_date DATE)
RETURNS TABLE (
    total_claims BIGINT,
    avg_claim_amount NUMERIC,
    fraud_rate_pct NUMERIC,
    approval_rate_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT,
        ROUND(AVG(c.total_claim_amount), 2),
        ROUND(100.0 * SUM(CASE WHEN c.fraud_reported THEN 1 ELSE 0 END) / COUNT(*), 2),
        ROUND(100.0 * SUM(CASE WHEN c.claim_status = 'Approved' THEN 1 ELSE 0 END) / COUNT(*), 2)
    FROM fact_claims c
    JOIN fact_incidents i ON c.incident_id = i.incident_id
    WHERE i.incident_date BETWEEN p_start_date AND p_end_date;
END;
$$ LANGUAGE plpgsql;

EXPLAIN ANALYZE
SELECT
    cl.claim_id, cu.customer_id, p.policy_number, i.incident_date, cl.total_claim_amount
FROM fact_claims cl
JOIN dim_policies  p  ON cl.policy_number = p.policy_number
JOIN dim_customers cu ON p.customer_id    = cu.customer_id
JOIN fact_incidents i ON cl.incident_id   = i.incident_id
WHERE i.incident_state = 'OH';

EXPLAIN ANALYZE
SELECT DATE_TRUNC('month', incident_date), incident_state, COUNT(*)
FROM fact_incidents
WHERE incident_date >= '2015-01-01' AND incident_state = 'OH'
GROUP BY 1, 2;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_monthly_kpi_summary AS
SELECT
    DATE_TRUNC('month', i.incident_date)::date AS claim_month,
    COUNT(*) AS total_claims,
    ROUND(AVG(c.total_claim_amount), 2) AS avg_claim_amount,
    ROUND(100.0 * SUM(CASE WHEN c.fraud_reported THEN 1 ELSE 0 END) / COUNT(*), 2) AS fraud_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN c.claim_status = 'Approved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS approval_rate_pct
FROM fact_claims c
JOIN fact_incidents i ON c.incident_id = i.incident_id
GROUP BY 1
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_monthly_kpi_month ON mv_monthly_kpi_summary(claim_month);

SELECT * FROM mv_monthly_kpi_summary ORDER BY claim_month;

SELECT p.*
FROM dim_policies p
WHERE EXISTS (
    SELECT 1 FROM fact_claims c
    WHERE c.policy_number = p.policy_number
    AND c.fraud_reported = TRUE
)
LIMIT 20;