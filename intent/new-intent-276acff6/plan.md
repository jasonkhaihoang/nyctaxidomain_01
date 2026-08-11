# Plan: core.fct_trip

> **For agentic workers:** REQUIRED SUB-SKILL: use `executing-the-plan` to run this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build dbt models from `silver.trips` through staging, dimensions, intermediate to `core.fct_trip`.

**Architecture:** DuckDB-local dbt project in `/workspace/transformation/`. Domain DB attached as `domain` for source reads. Models materialize into ephemeral DuckDB. Schema layout: staging → intermediate → core.

**Tech Stack:** dbt-duckdb, dbt_utils

## Global Constraints

- Platform: DuckDB-local. Domain DB attached as `domain` for source reads.
- Model naming: `stg_{source}__{table}` for staging, `dim_{entity}` for dimensions, `int_{description}` for intermediate, `core.fct_trip` for the fact table.
- Materialization: staging/intermediate as views, dimensions as tables, fact as table.
- Grain: one row per trip, keyed on `trip_key`.
- Required tests: `not_null` on primary keys, `unique` on primary keys, `relationships` on foreign keys.

---

## Tasks

### Task 1: dbt project scaffold + sources

**Files:**
- Create: `transformation/dbt_project.yml`
- Create: `transformation/profiles.yml`
- Create: `transformation/models/sources.yml`
- Create: `transformation/packages.yml`

**Interfaces:**
- Produces: dbt project root with DuckDB profile, `sources.yml` declaring `silver.trips`, `silver.zones`, `silver.payment_types`, `silver.rate_codes` from attached `domain` database

- [ ] **Step 1: Generate project scaffold and sources**
- [ ] **Step 2: `dbt deps` to install dbt_utils**
- [ ] **Step 3: `dbt debug` to verify connection**
- [ ] **Step 4: Commit**

### Task 2: Staging models (4 views)

**Files:**
- Create: `transformation/models/staging/stg_silver__trips.sql`
- Create: `transformation/models/staging/stg_silver__zones.sql`
- Create: `transformation/models/staging/stg_silver__payment_types.sql`
- Create: `transformation/models/staging/stg_silver__rate_codes.sql`
- Create: `transformation/models/staging/_staging.yml`

**Interfaces:**
- Consumes: `sources.yml` from Task 1
- Produces: `stg_silver__trips`, `stg_silver__zones`, `stg_silver__payment_types`, `stg_silver__rate_codes` views

- [ ] **Step 1: Generate all staging SQL models**
- [ ] **Step 2: `dbt run --select staging` to materialize views**
- [ ] **Step 3: Commit**

### Task 3: Dimension tables (5 tables)

**Files:**
- Create: `transformation/models/marts/dimensions/dim_zone.sql`
- Create: `transformation/models/marts/dimensions/dim_date.sql`
- Create: `transformation/models/marts/dimensions/dim_vendor.sql`
- Create: `transformation/models/marts/dimensions/dim_payment_type.sql`
- Create: `transformation/models/marts/dimensions/dim_rate_code.sql`
- Create: `transformation/models/marts/dimensions/_dimensions.yml`

**Interfaces:**
- Consumes: staging models from Task 2
- Produces: `dim_zone`, `dim_date`, `dim_vendor`, `dim_payment_type`, `dim_rate_code` tables

- [ ] **Step 1: Generate all dimension SQL models**
- [ ] **Step 2: `dbt run --select dim_zone dim_vendor dim_payment_type dim_rate_code dim_date`**
- [ ] **Step 3: Commit**

### Task 4: Intermediate model int_trip_enriched

**Files:**
- Create: `transformation/models/intermediate/int_trip_enriched.sql`

**Interfaces:**
- Consumes: `stg_silver__trips` and all dimension tables from Tasks 2-3
- Produces: `int_trip_enriched` view (trip grain, joined to all dims, with computed fare/quality/fleet columns)

- [ ] **Step 1: Generate int_trip_enriched SQL**
- [ ] **Step 2: `dbt run --select int_trip_enriched`**
- [ ] **Step 3: Commit**

### Task 5: core.fct_trip fact table

**Files:**
- Create: `transformation/models/marts/core/fct_trip.sql`
- Create: `transformation/models/marts/core/_core.yml`

**Interfaces:**
- Consumes: `int_trip_enriched` from Task 4
- Produces: `core.fct_trip` table (trip grain, keyed on trip_key)

- [ ] **Step 1: Generate core.fct_trip SQL**
- [ ] **Step 2: `dbt run --select fct_trip`**
- [ ] **Step 3: Commit**

### Task 6: Full build + schema tests

**Files:**
- Create: `transformation/models/marts/core/_core_tests.yml` (schema tests: not_null, unique, relationships)
- Create: `transformation/models/marts/dimensions/_dimensions_tests.yml`

**Interfaces:**
- Consumes: all models from Tasks 2-5

- [ ] **Step 1: Add schema tests (not_null, unique, relationships)**
- [ ] **Step 2: `dbt build` full DAG**
- [ ] **Step 3: Commit**

## Execution evidence

