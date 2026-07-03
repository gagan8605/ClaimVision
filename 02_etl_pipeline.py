"""
=======================================================================
Insurance Claims Analytics — ETL Pipeline
=======================================================================
Extracts the raw Kaggle "Auto Insurance Claims Data" CSV, cleans and
transforms it, and loads it into the normalized PostgreSQL schema
defined in 01_schema.sql (dim_customers, dim_policies, dim_vehicles,
fact_incidents, fact_claims).

Usage:
    python 02_etl_pipeline.py --csv ..\insurance_claims.csv --reset-schema
    python 02_etl_pipeline.py --csv ..\insurance_claims.csv --truncate
    python 02_etl_pipeline.py --csv ..\insurance_claims.csv

Connection is read from environment variables (see .env.example):
    DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
or from a single DATABASE_URL env var if provided.

Author: Data Engineering — Insurance Claims Analytics Project
=======================================================================
"""

import argparse
import logging
import os
from pathlib import Path

import numpy as np
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("insurance_etl")


def get_db_engine():
    """Build a SQLAlchemy engine from environment variables."""
    load_dotenv()

    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        host = os.getenv("DB_HOST", "localhost")
        port = os.getenv("DB_PORT", "5432")
        name = os.getenv("DB_NAME", "insurance_claims_db")
        user = os.getenv("DB_USER", "postgres")
        password = os.getenv("DB_PASSWORD", "postgres")
        database_url = URL.create(
            "postgresql+psycopg2",
            username=user,
            password=password,
            host=host,
            port=int(port),
            database=name,
        )

    engine = create_engine(database_url, pool_pre_ping=True)
    logger.info("Connected to database at %s", engine.url.render_as_string(hide_password=True))
    return engine


def apply_schema(engine, schema_path: str):
    """Run the DDL file to (re)create the schema."""
    logger.info("Applying schema from %s (existing tables will be dropped)", schema_path)
    ddl = Path(schema_path).read_text(encoding="utf-8")
    with engine.begin() as conn:
        conn.execute(text(ddl))
    logger.info("Schema applied successfully.")


def truncate_target_tables(engine):
    """Clear ETL target tables while preserving schema objects."""
    logger.info("Truncating target tables (schema preserved, identities reset)")
    with engine.begin() as conn:
        conn.execute(text(
            "TRUNCATE TABLE "
            "fact_claims, fact_incidents, dim_vehicles, dim_policies, dim_customers "
            "RESTART IDENTITY CASCADE"
        ))
    logger.info("Target tables truncated successfully.")


def extract(csv_path: str) -> pd.DataFrame:
    logger.info("Reading source CSV: %s", csv_path)
    df = pd.read_csv(csv_path)
    logger.info("Extracted %d rows, %d columns", *df.shape)
    return df


def transform(df: pd.DataFrame) -> dict:
    """Clean the raw dataframe and split it into normalized dataframes."""
    df = df.copy()
    report = {}

    if "_c39" in df.columns:
        df = df.drop(columns=["_c39"])
        logger.info("Dropped junk trailing column '_c39' (source export artifact)")

    df = df.rename(columns={
        "capital-gains": "capital_gains",
        "capital-loss": "capital_loss",
    })

    placeholder_cols = ["collision_type", "property_damage", "police_report_available"]
    for col in placeholder_cols:
        n_placeholders = (df[col] == "?").sum()
        df[col] = df[col].replace("?", np.nan)
        report[f"{col}_placeholders_nulled"] = int(n_placeholders)
        logger.info("Column '%s': converted %d '?' placeholders to NULL", col, n_placeholders)

    df["policy_bind_date"] = pd.to_datetime(df["policy_bind_date"]).dt.date
    df["incident_date"] = pd.to_datetime(df["incident_date"]).dt.date

    yn_map = {"YES": True, "NO": False}
    df["property_damage"] = df["property_damage"].map(yn_map)
    df["police_report_available"] = df["police_report_available"].map(yn_map)

    df["fraud_reported"] = df["fraud_reported"].map({"Y": True, "N": False})
    if df["fraud_reported"].isnull().any():
        raise ValueError("Unexpected null in fraud_reported after mapping")

    n_negative_umbrella = (df["umbrella_limit"] < 0).sum()
    if n_negative_umbrella:
        logger.warning(
            "%d row(s) have a NEGATIVE umbrella_limit. This is preserved but flagged.",
            n_negative_umbrella,
        )
    report["negative_umbrella_limit_rows"] = int(n_negative_umbrella)

    claim_sum_check = (
        df["total_claim_amount"] - (df["injury_claim"] + df["property_claim"] + df["vehicle_claim"])
    ).abs()
    n_mismatch = (claim_sum_check > 0.01).sum()
    if n_mismatch:
        logger.warning("%d row(s) where total_claim_amount != sum of claim parts", n_mismatch)
    report["claim_sum_mismatches"] = int(n_mismatch)

    n_age_out_of_range = (~df["age"].between(16, 100)).sum()
    if n_age_out_of_range:
        logger.warning("%d row(s) with age outside plausible 16-100 range", n_age_out_of_range)
    report["age_out_of_range_rows"] = int(n_age_out_of_range)

    dup_policy_numbers = df["policy_number"].duplicated().sum()
    if dup_policy_numbers:
        logger.warning("%d duplicate policy_number values found", dup_policy_numbers)
    report["duplicate_policy_numbers"] = int(dup_policy_numbers)

    df["claim_status"] = np.where(df["fraud_reported"], "Denied", "Approved")

    df = df.reset_index(drop=True)
    df["customer_id"] = df.index + 1
    df["incident_id"] = df.index + 1

    customers = df[[
        "customer_id", "age", "insured_sex", "insured_education_level",
        "insured_occupation", "insured_hobbies", "insured_relationship",
        "capital_gains", "capital_loss", "insured_zip",
    ]].copy()

    policies = df[[
        "policy_number", "customer_id", "months_as_customer", "policy_bind_date",
        "policy_state", "policy_csl", "policy_deductable", "policy_annual_premium",
        "umbrella_limit",
    ]].copy()

    vehicles = df[["policy_number", "auto_make", "auto_model", "auto_year"]].copy()

    incidents = df[[
        "incident_id", "policy_number", "incident_date", "incident_type",
        "collision_type", "incident_severity", "authorities_contacted",
        "incident_state", "incident_city", "incident_location",
        "incident_hour_of_the_day", "number_of_vehicles_involved",
        "property_damage", "bodily_injuries", "witnesses",
        "police_report_available",
    ]].copy()

    claims = df[[
        "incident_id", "policy_number", "total_claim_amount", "injury_claim",
        "property_claim", "vehicle_claim", "fraud_reported", "claim_status",
    ]].copy()

    logger.info("Transform complete. Data-quality report: %s", report)

    return {
        "dim_customers": customers,
        "dim_policies": policies,
        "dim_vehicles": vehicles,
        "fact_incidents": incidents,
        "fact_claims": claims,
        "_report": report,
    }


def load(engine, tables: dict):
    """Load dataframes into PostgreSQL in FK-safe order."""
    load_order = ["dim_customers", "dim_policies", "dim_vehicles", "fact_incidents", "fact_claims"]

    for table_name in load_order:
        df = tables[table_name]
        logger.info("Loading %d rows into %s ...", len(df), table_name)
        df.to_sql(table_name, engine, if_exists="append", index=False, method="multi", chunksize=500)
        logger.info("Loaded %s successfully.", table_name)

    with engine.begin() as conn:
        conn.execute(text(
            "SELECT setval(pg_get_serial_sequence('dim_customers','customer_id'), "
            "(SELECT MAX(customer_id) FROM dim_customers));"
        ))
        conn.execute(text(
            "SELECT setval(pg_get_serial_sequence('fact_incidents','incident_id'), "
            "(SELECT MAX(incident_id) FROM fact_incidents));"
        ))
    logger.info("Sequences realigned for dim_customers and fact_incidents.")


def validate_load(engine, expected_rows: int):
    checks = {
        "dim_customers": expected_rows,
        "dim_policies": expected_rows,
        "dim_vehicles": expected_rows,
        "fact_incidents": expected_rows,
        "fact_claims": expected_rows,
    }
    with engine.connect() as conn:
        for table, expected in checks.items():
            actual = conn.execute(text(f"SELECT COUNT(*) FROM {table}")).scalar()
            status = "OK" if actual == expected else "MISMATCH"
            logger.info("Validation [%s]: expected=%d actual=%d -> %s", table, expected, actual, status)
            if actual != expected:
                raise AssertionError(f"Row count mismatch in {table}: expected {expected}, got {actual}")

        orphan_claims = conn.execute(text(
            "SELECT COUNT(*) FROM fact_claims c "
            "LEFT JOIN fact_incidents i ON c.incident_id = i.incident_id "
            "WHERE i.incident_id IS NULL"
        )).scalar()
        logger.info("Validation [orphan claims check]: %d orphan rows (expected 0)", orphan_claims)
        if orphan_claims:
            raise AssertionError(f"{orphan_claims} claims have no matching incident")

    logger.info("All post-load validation checks passed.")


def main():
    parser = argparse.ArgumentParser(description="Insurance Claims ETL Pipeline")
    parser.add_argument("--csv", required=True, help="Path to insurance_claims.csv")
    parser.add_argument("--schema", default="01_schema.sql", help="Path to DDL schema file")
    parser.add_argument("--reset-schema", action="store_true", help="Drop and recreate all tables before loading")
    parser.add_argument("--truncate", action="store_true", help="Truncate ETL target tables before loading")
    args = parser.parse_args()

    logger.info("========== Insurance Claims ETL — START ==========")

    engine = get_db_engine()

    if args.reset_schema:
        apply_schema(engine, args.schema)
    elif args.truncate:
        truncate_target_tables(engine)

    raw_df = extract(args.csv)
    tables = transform(raw_df)
    row_count = len(raw_df)

    load(engine, {k: v for k, v in tables.items() if k != "_report"})
    validate_load(engine, expected_rows=row_count)

    logger.info("Data-quality summary: %s", tables["_report"])
    logger.info("========== Insurance Claims ETL — COMPLETE ==========")


if __name__ == "__main__":
    main()