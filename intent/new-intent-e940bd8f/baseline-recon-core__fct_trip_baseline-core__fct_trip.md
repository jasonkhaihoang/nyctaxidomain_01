# Recon Pair: `core.fct_trip_baseline` (Baseline) vs `core.fct_trip` (Target)

## Confirmed contract

- **Baseline:** `nyctaxi.core.fct_trip_baseline`
- **Target:** `nyctaxi.core.fct_trip`
- **Source premise:** Same source pipeline/snapshot (FSA-stated). Row counts and `pickup_datetime` boundaries match exactly on both sides at profiling time.
- **Mode:** Keyed, on `trip_key` — unique and non-null on both sides (20,671,899 total = distinct, 0 nulls each).
- **Scope:** Whole-dataset (row counts and datetime boundaries already coincide; no overlap-window trimming needed).
- **Common grain:** One row per `trip_key` (native grain on both sides; no aggregation).
- **Gating:** Advisory (never blocks Intent completion).
- **Round cap:** 5 (default), raisable by the FSA without ceiling.

### Column mapping

| Baseline | Target | Cast | Justification |
| --- | --- | --- | --- |
| trip_key | trip_key | none | key |
| pickup_zone_key | pickup_zone_key | none | identical type (VARCHAR) |
| dropoff_zone_key | dropoff_zone_key | none | identical type (VARCHAR) |
| payment_method_key | payment_method_key | `cast(target.payment_method_key as varchar)` | baseline VARCHAR vs target BIGINT — widening to text, value-identity preserving |
| rate_plan_key | rate_plan_key | none | identical type (BIGINT) |
| pickup_datetime | pickup_datetime | none | identical type |
| dropoff_datetime | dropoff_datetime | none | identical type |
| pickup_location_id | pickup_location_id | none | identical type |
| dropoff_location_id | dropoff_location_id | none | identical type |
| passenger_count | passenger_count | none | identical type |
| store_and_fwd_flag | store_and_fwd_flag | none | identical type |
| trip_distance | trip_distance | none | identical type |
| fare_amount | fare_amount | none | identical type |
| extra | extra | none | identical type |
| mta_tax | mta_tax | none | identical type |
| tip_amount | tip_amount | none | identical type |
| tolls_amount | tolls_amount | none | identical type |
| improvement_surcharge | improvement_surcharge | none | identical type |
| congestion_surcharge | congestion_surcharge | none | identical type |
| total_amount | total_amount | none | identical type |
| fare_residual | fare_residual | none | identical type |
| is_billable | is_billable | none | identical type |

Target's remaining 18 columns (`pickup_date_key`, `pickup_date`, `pickup_hour`, `daypart_code`, `service_type_key`, `vendor_key`, `trip_quality_key`, `shift_id`, `driver_key`, `vehicle_key`, `assignment_method`, `is_fleet_attributed`, `trip_type`, `trip_seconds`, `avg_mph`, `airport_fee`, `ehail_fee`, `total_surcharges`, `measurable_tip_rate`, `airport_fee_status`) have no baseline counterpart and are out of scope for this comparison.

### PII

`vd_recon_pii_columns(nyctaxi.core.fct_trip_baseline)` → `[]`. No PII gating required.

### Tolerance

- Exact: `trip_key`, `pickup_zone_key`, `dropoff_zone_key`, `payment_method_key`, `rate_plan_key`, `pickup_datetime`, `dropoff_datetime`, `pickup_location_id`, `dropoff_location_id`, `passenger_count`, `store_and_fwd_flag`, `trip_distance`, `is_billable`
- Fixed tolerance $0.01: `fare_amount`, `extra`, `mta_tax`, `tip_amount`, `tolls_amount`, `improvement_surcharge`, `congestion_surcharge`, `total_amount`, `fare_residual`

### Profiling evidence (Negotiate step)

| Check | Macro | Result |
| --- | --- | --- |
| Target schema | `vd_recon_schema_probe(nyctaxi.core.fct_trip)` | 40 columns |
| Baseline schema | `vd_recon_schema_probe(nyctaxi.core.fct_trip_baseline)` | 22 columns |
| Target key uniqueness | `vd_recon_key_uniqueness(nyctaxi.core.fct_trip, ["trip_key"])` | `{"total": 20671899, "distinct": 20671899, "nulls": 0}` |
| Baseline key uniqueness | `vd_recon_key_uniqueness(nyctaxi.core.fct_trip_baseline, ["trip_key"])` | `{"total": 20671899, "distinct": 20671899, "nulls": 0}` |
| Target boundaries (`pickup_datetime`) | `vd_recon_probe_boundaries(nyctaxi.core.fct_trip, "pickup_datetime")` | `{"min": "2002-12-31 16:46:07", "max": "2026-06-26 23:53:12", "count": 20671899}` |
| Baseline boundaries (`pickup_datetime`) | `vd_recon_probe_boundaries(nyctaxi.core.fct_trip_baseline, "pickup_datetime")` | `{"min": "2002-12-31 16:46:07", "max": "2026-06-26 23:53:12", "count": 20671899}` |
| Baseline PII columns | `vd_recon_pii_columns(nyctaxi.core.fct_trip_baseline)` | `{"pii_columns": []}` |

## Amendment 1 — Scope narrowed (infra-memory constraint)

Whole-dataset measurement via `vd_recon_compare_keyed` was attempted and killed by the
sandbox's OOM condition (exit 137) on two consecutive attempts (default threads, then
`--threads 1`) — both exhausted the infra-retry cap (max 2) per
`references/investigation-and-mechanism.md`. Neither attempt reached the macro's own
`VD_RECON_RESULT` line, so no partial measurement exists to report as an alternative to
this amendment.

**FSA-confirmed narrowing:** Scope changes from whole-dataset to the overlap window
`pickup_datetime >= '2024-01-01' AND pickup_datetime < '2024-07-01'` — the `report_start`/
`report_end` reporting window already confirmed for this domain (ADR-0002, recorded in
`transformation/dbt_project.yml`'s `vars` block), which falls entirely inside the
whole-dataset boundaries both sides already share. The filter is applied identically to
both sides as a row predicate on the shared `pickup_datetime` column — no other part of
the confirmed contract (key, mapping, casts, tolerance, gating=advisory) changes.

## Measurement

_Pending — Step 3 rerun against the narrowed scope not yet executed._

## Investigation

_Pending._

## Residual / Unexplained

_Pending._

## Outcome

_Pending._
