# 🛡️ Insurance Claims Analytics

> **End-to-end data engineering & analytics project** — from raw CSV to a Power BI executive dashboard, built using PostgreSQL, Python ETL, and advanced SQL analysis.

---

## 📌 Project Goal

To design and deliver a **production-grade insurance claims analytics pipeline** that:

- Transforms a flat Kaggle auto-insurance CSV into a **normalized star-schema** in PostgreSQL
- Surfaces actionable **fraud detection**, **claim performance**, and **underwriting insights** via a multi-page Power BI dashboard
- Demonstrates end-to-end data engineering skills: schema design → ETL → SQL analytics → DAX measures → BI delivery

---

## 🌟 STAR Method — Project Narrative

### 📍 Situation
An auto-insurance portfolio of **1,000 policies** was generating a significant volume of claims, but the raw data existed only as a **flat, denormalized CSV** with no analytical layer. Business stakeholders had no visibility into:
- Which states or customer segments were driving **fraud**
- Whether claim approval rates were **aligned with risk exposure**
- How **claim costs were trending** month-over-month

The data also had **quality issues**: `?` placeholders for missing fields, negative umbrella limit values, and no derived adjudication outcome (`claim_status`).

---

### 🎯 Task
Design and build a complete analytics solution to:
1. **Clean and model** the raw insurance data into a structured PostgreSQL star schema
2. **Develop analytical SQL** covering aggregations, joins, CTEs, window functions, stored procedures, and performance tuning
3. **Build a Power BI dashboard** with executive KPI cards, fraud analysis, regional drill-through, and RAG (Red-Amber-Green) status indicators
4. Deliver transparent, documented data quality notes suitable for a production-facing EXL-style deliverable

---

### ⚙️ Action

#### 1. Data Modelling (Schema Design)
Designed a **3NF star-ish schema** with 5 tables to separate business entities cleanly:

```
dim_customers  ──┐
dim_policies   ──┼──▶  fact_incidents  ──▶  fact_claims
dim_vehicles   ──┘
```

| Table | Purpose | Key Columns |
|---|---|---|
| `dim_customers` | Insured demographics | age, sex, occupation, education, hobbies |
| `dim_policies` | Policy terms & coverage | policy_number, CSL, premium, deductible, state |
| `dim_vehicles` | Vehicle on the policy | auto_make, auto_model, auto_year |
| `fact_incidents` | Loss event triggering claim | incident_date, severity, state, collision_type |
| `fact_claims` | Financial claim outcome | total_claim_amount, fraud_reported, claim_status |

Performance indexes were added on all FK join columns, filter predicates (`incident_state`, `incident_date`, `fraud_reported`), and a composite index for the monthly × state fraud trend query.

---

#### 2. ETL Pipeline (`02_etl_pipeline.py`)
Built a Python ETL with 4 explicit stages and post-load validation:

| Stage | What it does |
|---|---|
| **Extract** | Reads raw CSV using Pandas |
| **Transform** | Cleans `?` placeholders → NULL, standardizes booleans (Y/N → TRUE/FALSE), derives `claim_status`, assigns surrogate keys, validates data quality |
| **Load** | Inserts into PostgreSQL in FK-safe order using SQLAlchemy bulk insert (`method="multi"`) |
| **Validate** | Confirms row counts match across all 5 tables; checks for orphan claims |

**Data quality flags handled transparently:**
- `collision_type`, `property_damage`, `police_report_available` — `?` → NULL (not imputed)
- `umbrella_limit` — 1 negative value flagged, not corrected (kept per business decision)
- `claim_status` — derived field (fraud=Y → Denied, fraud=N → Approved); clearly documented as a simplifying assumption

---

#### 3. SQL Analysis (`03_analysis_queries.sql`)
24 analytical queries organized across 6 sections:

| Section | Queries | Techniques |
|---|---|---|
| **A. Aggregations** | Q1–Q5 | GROUP BY, HAVING, CASE WHEN, date truncation |
| **B. Joins** | Q6–Q9 | 5-table JOIN, LEFT JOIN integrity checks, subquery joins |
| **C. CTEs** | Q10–Q13 | Multi-CTE pipelines, PERCENTILE_CONT, claim tiering |
| **D. Window Functions** | Q14–Q17 | RANK, SUM OVER, NTILE, 3-month moving average |
| **E. Stored Procedures** | Q18–Q20 | plpgsql functions, parameterized KPI snapshots, bulk UPDATE |
| **F. Performance Tuning** | Q21–Q24 | EXPLAIN ANALYZE, materialized view, EXISTS vs IN |

---

#### 4. Power BI Dashboard (`Dashboard.pbix`)
Built a **4-page interactive Power BI dashboard** connected to PostgreSQL via Import mode:

| Page | Content |
|---|---|
| **Page 1 — Executive Overview** | KPI cards (Total Claims, Avg Claim Amount, Fraud Rate %, Approval Rate %) with RAG conditional formatting; monthly trend line; severity bar chart; regional fraud map |
| **Page 2 — Fraud Analysis** | State-level fraud rate bar chart (RAG colored); occupation × fraud rate; top-20 high-value fraud claims table; severity/CSL slicers |
| **Page 3 — Claim Details (Drill-Through)** | Full flattened claim row (customer → policy → vehicle → incident → claim); drill-through enabled per state/CSL; Back button navigation |
| **Page 4 — Portfolio / Underwriting View** | Policy CSL tier comparison; age band claim distribution; claim tier donut chart |

**DAX Measures Library** — 25+ measures across 5 groups:
- `Base` — Total Claims, Total/Avg Claim Amount, Fraud Claims, Approved/Denied Claims, Total Policies, Avg Premium
- `Rates` — Fraud Rate %, Approval Rate %, Denial Rate %, Avg Claim (Approved Only)
- `RAG` — Data-driven RAG status + hex color measures for all 3 KPIs + Overall Book RAG
- `Trend` — Prior Month Claims, MoM % Change, MoM Fraud Rate Change (pp), 3-Month Moving Avg, YTD Claims
- `Drill-through` — Claims in Selected Region, Fraud Rate % (Selected Region), Rank of Region by Fraud Rate, Claims by Policy Type

---

### 📊 Result

#### Key Dashboard Outcomes (from data spanning Jan–Mar 2015)

| KPI | Value | RAG Status |
|---|---|---|
| **Total Claims** | 1,000 | — |
| **Fraud Rate %** | ~24.7% (avg across states) | 🟡 Amber |
| **Approval Rate %** | ~75.3% | 🟡 Amber |
| **Avg Claim Amount** | ~$58,055 (median) | 🟡 Amber |
| **Highest Fraud State** | OH — 43.48% | 🔴 Red |
| **Lowest Fraud State** | WV — 17.97% | 🟢 Green |
| **Best Approval Rate** | Trivial Damage severity — 93.33% | 🟢 Green |
| **Worst Approval Rate** | Major Damage severity — 39.49% | 🔴 Red |

#### Claim Amount Distribution

| Percentile | Claim Amount |
|---|---|
| P25 | $41,813 |
| P50 (Median) | $58,055 |
| P75 | $70,593 |

#### RAG Thresholds (Data-Driven, Not Arbitrary)

| Metric | 🟢 Green | 🟡 Amber | 🔴 Red |
|---|---|---|---|
| Fraud Rate % | < 20% | 20%–30% | > 30% |
| Approval Rate % | ≥ 80% | 60%–80% | < 60% |
| Avg Claim Amount | < $45,000 | $45k–$70k | > $70,000 |

#### Regional Fraud Findings
`incident_state` (where accident happened) shows dramatically more spread than `policy_state` (where underwritten):

| Incident State | Fraud Rate | RAG |
|---|---|---|
| OH | 43.48% | 🔴 Red |
| SC | ~35%+ | 🔴 Red |
| WV | 17.97% | 🟢 Green |
| IN | ~22% | 🟡 Amber |

---

## 📐 KPIs Used

### Primary KPIs (Executive Dashboard Cards)
| KPI | Definition | DAX Measure |
|---|---|---|
| **Total Claims** | Count of all claim records | `COUNTROWS(fact_claims)` |
| **Avg Claim Amount** | Average total claim value | `AVERAGE(fact_claims[total_claim_amount])` |
| **Fraud Rate %** | % of claims flagged as fraudulent | `DIVIDE([Fraud Claims], [Total Claims], 0)` |
| **Approval Rate %** | % of claims with status = Approved | `DIVIDE([Approved Claims], [Total Claims], 0)` |

### Supporting KPIs
| KPI | Definition |
|---|---|
| **Total Claim Amount** | Sum of all claim payouts |
| **Total Injury Claim** | Sum of injury sub-component |
| **Total Property Claim** | Sum of property sub-component |
| **Total Vehicle Claim** | Sum of vehicle sub-component |
| **Denial Rate %** | 1 − Approval Rate |
| **Avg Annual Premium** | Average policy premium across portfolio |
| **Total Policies** | Count of distinct policy numbers |
| **MoM Claim Volume Change %** | Month-over-month change in claim count |
| **MoM Fraud Rate Change (pp)** | Month-over-month fraud rate shift in percentage points |
| **3-Month Moving Avg Claims** | Smoothed rolling claim count trend |
| **YTD Total Claims** | Year-to-date cumulative claim count |
| **Overall Book RAG Status** | Worst-of-three composite RAG for the full portfolio |

---

## 🛠️ Tech Stack

| Layer | Technology | Version / Notes |
|---|---|---|
| **Database** | PostgreSQL | 14+ (tested on PG 16) |
| **ORM / Connectivity** | SQLAlchemy | ≥ 2.0.0 |
| **DB Driver** | psycopg2-binary | ≥ 2.9.0 |
| **ETL / Data Processing** | Python + Pandas | ≥ 2.0.0 |
| **Numerical Computing** | NumPy | ≥ 1.24.0 |
| **Config Management** | python-dotenv | ≥ 1.0.0 |
| **BI / Visualisation** | Microsoft Power BI Desktop | Import mode |
| **Query Language** | SQL (PostgreSQL dialect) | Aggregations, CTEs, Window Functions, Stored Procs |
| **DAX** | Power BI DAX | 25+ measures; time intelligence, RAG, drill-through |
| **Source Data** | Kaggle — Auto Insurance Claims (buntyshah) | 1,000 rows, 40 columns |



*Source data: Kaggle — Auto Insurance Claims Dataset (buntyshah)*

---
