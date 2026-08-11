# Design: core.fct_trip

## Architecture

**Grain**: One row per trip, keyed on `trip_key` (VARCHAR surrogate key, pre-computed in `silver.trips`).

**Materialization**: `core.fct_trip` as a table. Staging and intermediate models as views. Dimensions as tables.

**Platform**: DuckDB-local. dbt-duckdb adapter. Domain DB attached as `domain` for source reads; models materialize into the ephemeral DuckDB. Schema layout: `staging` → `intermediate` → `core`.

**Approach**: Standard star-schema fact table with conformed dimensions. Staging layer is 1:1 with silver sources (column renaming, derived columns like `pickup_date`, `pickup_hour`, `trip_seconds`, `avg_mph`). Intermediate layer enriches with fare component normalization, quality flags, and fleet-ops classification. Dimensions resolved from silver reference tables (`silver.zones`, `silver.payment_types`, `silver.rate_codes`) and distinct values from trip data (`dim_vendor`, `dim_date`). The fact table `core.fct_trip` holds foreign keys to all dimensions plus additive measures and quality flags.

**Decision — Zone dimension**: Use `silver.zones` (265 rows: location_id, borough, zone_name, service_zone) as source. Single zone dimension serves both pickup and dropoff via role-playing aliases.

**Decision — Payment/Rate dims**: Use `silver.payment_types` (7 rows) and `silver.rate_codes` (6 rows) as sources.

**Decision — Vendor dim**: Derived from distinct `vendor_id` values in trip data. Labels from domain knowledge (1 = Creative Mobile Technologies, 2 = VeriFone Inc).

**Decision — Date dim**: Generated from the date range in trip data (2024-01-01 through 2024-06-30), with daypart classification seeded from standard bands.

## Inventory

### Model Inventory

| # | Model | Layer | Grain | Materialization | Depends On | Status |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `stg_silver__trips` | staging | 1:1 with `silver.trips` | view | source: `silver.trips` | working |
| 2 | `stg_silver__zones` | staging | 1:1 with `silver.zones` | view | source: `silver.zones` | working |
| 3 | `stg_silver__payment_types` | staging | 1:1 with `silver.payment_types` | view | source: `silver.payment_types` | working |
| 4 | `stg_silver__rate_codes` | staging | 1:1 with `silver.rate_codes` | view | source: `silver.rate_codes` | working |
| 5 | `dim_zone` | dim | One row per `location_id` | table | `stg_silver__zones` | working |
| 6 | `dim_date` | dim | One row per date | table | `stg_silver__trips` (date range) | working |
| 7 | `dim_vendor` | dim | One row per `vendor_id` | table | `stg_silver__trips` | working |
| 8 | `dim_payment_type` | dim | One row per `payment_type` | table | `stg_silver__payment_types` | working |
| 9 | `dim_rate_code` | dim | One row per `rate_code_id` | table | `stg_silver__rate_codes` | working |
| 10 | `int_trip_enriched` | intermediate | One row per trip (trip_key) | view | `stg_silver__trips`, all dims | working |
| 11 | `core.fct_trip` | mart | One row per trip, keyed on `trip_key` | table | `int_trip_enriched` | working |

**Model details**:

- **`stg_silver__trips`**: 1:1 with `silver.trips`. Adds computed columns: `pickup_date`, `pickup_hour`, `trip_seconds` (pickup→dropoff), `avg_mph` (trip_distance / trip_hours, null when duration=0). Retains all source columns.
- **`stg_silver__zones`**: 1:1 with `silver.zones`. Renames: `location_id` → `zone_id`, `zone_name` → `zone`, `borough` → `borough_name`.
- **`stg_silver__payment_types`**: 1:1 with `silver.payment_types`. Renames: `payment_type_desc` → `payment_type_name`.
- **`stg_silver__rate_codes`**: 1:1 with `silver.rate_codes`. Renames: `rate_code_desc` → `rate_code_name`.
- **`dim_zone`**: From `stg_silver__zones`. Columns: `zone_key`, `zone_id`, `zone_name`, `borough_name`, `service_zone`, `is_airport` (EWR zone or zone_name contains 'Airport').
- **`dim_date`**: Generated via `dbt_utils.date_spine` from trip date range. Columns: `date_key` (YYYYMMDD integer), `calendar_date`, `year`, `quarter`, `month`, `month_name`, `day_of_week`, `day_name`, `is_weekend`, `daypart_code` (morning/afternoon/evening/night based on standard bands).
- **`dim_vendor`**: Distinct `vendor_id` from trips with descriptive label. Columns: `vendor_key`, `vendor_id`, `vendor_name`.
- **`dim_payment_type`**: From `stg_silver__payment_types`. Columns: `payment_type_key`, `payment_type_id`, `payment_type_name`.
- **`dim_rate_code`**: From `stg_silver__rate_codes`. Columns: `rate_code_key`, `rate_code_id`, `rate_code_name`.
- **`int_trip_enriched`**: Joins `stg_silver__trips` to all dimensions. Computes:
  - Fare components: `total_surcharges` (sum of extra, mta_tax, improvement_surcharge, congestion_surcharge), `fare_residual` (total_amount - fare_amount - tip_amount - tolls_amount - total_surcharges)
  - Quality flags: `is_quality_flagged` (trip_seconds <= 0 OR trip_distance < 0 OR fare_amount < 0 OR (trip_distance = 0 AND total_amount > 0) OR avg_mph > 100)
  - Fleet ops: `assignment_method` ('yellow_v{id}' / 'green'), `is_fleet_attributed` (service_type = 'yellow')
  - Tip metrics: `tip_rate` (tip_amount / fare_amount, null when fare=0)
- **`core.fct_trip`**: Fact table. Key columns: `trip_key`, `pickup_date_key`, `daypart_code`, `service_type`, `pickup_zone_key`, `dropoff_zone_key`, `vendor_key`, `payment_type_key`, `rate_code_key`. Measures: `passenger_count`, `trip_distance`, `trip_seconds`, `avg_mph`, `fare_amount`, `extra`, `mta_tax`, `tip_amount`, `tolls_amount`, `improvement_surcharge`, `congestion_surcharge`, `total_surcharges`, `total_amount`, `fare_residual`, `tip_rate`. Flags: `is_quality_flagged`, `is_fleet_attributed`. Metadata: `assignment_method`, `pickup_datetime`, `dropoff_datetime`, `pickup_location_id`, `dropoff_location_id`, `store_and_fwd_flag`.

## Source Mapping / Discovery

| Source | Layer | Model | Key columns |
| --- | --- | --- | --- |
| `silver.trips` (20,671,899 rows) | staging | `stg_silver__trips` | trip_key (VARCHAR, unique), vendor_id, pickup/dropoff_datetime, pickup/dropoff_location_id, rate_code_id, payment_type, passenger_count, trip_distance, fare_amount, extra, mta_tax, tip_amount, tolls_amount, improvement_surcharge, congestion_surcharge, total_amount, service_type, store_and_fwd_flag |
| `silver.zones` (265 rows) | staging | `stg_silver__zones` | location_id, borough, zone_name, service_zone |
| `silver.payment_types` (7 rows) | staging | `stg_silver__payment_types` | payment_type, payment_type_desc |
| `silver.rate_codes` (6 rows) | staging | `stg_silver__rate_codes` | rate_code_id, rate_code_desc |

**Bronze Adequacy**: `READY` — `silver.trips` has 20.7M rows, no nulls on critical keys (trip_key, pickup/dropoff_datetime, pickup/dropoff_location_id, fare_amount, total_amount). Minor nulls on rate_code_id/passenger_count/store_and_fwd_flag (~9.6%, all from green taxis — expected). Reference tables are complete and consistent.

**Profiling highlights**:
- Date range: 2024-01-01 → 2024-06-30
- service_type: yellow (20.3M), green (340k)
- vendor_id: 1, 2
- rate_code_id: 1 (Standard, 17.5M), 2 (JFK), 3 (Newark), 4 (Nassau/Westchester), 5 (Negotiated), 99, 6 — null for green taxis
- payment_type: 1 (Credit card, 15.3M), 2 (Cash, 2.9M), 0 (Flex Fare), 4 (Dispute), 3 (No charge)
- trip_distance: positive, reasonable range (median ~1.6mi from domain knowledge)

## Change Impact

No existing models in workspace — this is a fresh build. The domain DB has existing `core.fct_trip` and supporting models; this project builds a parallel clean implementation in the workspace transformation directory.

## Approvals

- [x] User approved design — 2026-08-11 06:19 (UTC)
