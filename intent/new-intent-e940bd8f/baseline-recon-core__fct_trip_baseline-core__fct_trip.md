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

## Amendment 2 — Scope narrowed further (persistent OOM at 6-month window)

`vd_recon_compare_keyed` against the Amendment 1 scope (`2024-01-01` to `2024-07-01`,
~6 months) was retried twice more (`--threads 1`, both with and without the payment
method cast folded into the relation subquery) and was killed by OOM (exit 137) both
times — exhausting the infra-retry cap again.

**FSA-confirmed further narrowing:** Scope changes from the Amendment 1 window to
`pickup_datetime >= '2024-01-01' AND pickup_datetime < '2024-02-01'` (1 calendar month,
the first month of the ADR-0002 reporting window). No other part of the confirmed
contract changes.

## Measurement

Scope: Amendment 2 (`pickup_datetime >= '2024-01-01' AND pickup_datetime < '2024-02-01'`).

`vd_recon_compare_keyed(baseline_relation, target_relation, ["trip_key"], column_pairs)`
(run with `--threads 1`; the target relation subquery folds the `payment_method_key`
cast so the macro's literal `t.<target_column>` templating stays a bare column reference):

```json
{"row_count": {"baseline": 3021172, "target": 3021172}, "key_count": {"baseline": 3021172, "target": 3021172}, "classification": {"matching": 7735, "missing_from_target": 0, "additional_in_target": 0, "changed": 3013437}, "invalid_key_alignment": 0, "column_conflicts": [{"column": "pickup_zone_key", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "dropoff_zone_key", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "payment_method_key", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "rate_plan_key", "conflict_count": 0, "one_sided_null_count": 143577}, {"column": "pickup_datetime", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "dropoff_datetime", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "pickup_location_id", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "dropoff_location_id", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "passenger_count", "conflict_count": 0, "one_sided_null_count": 143577}, {"column": "store_and_fwd_flag", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "trip_distance", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "fare_amount", "conflict_count": 2628323, "one_sided_null_count": 0}, {"column": "extra", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "mta_tax", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "tip_amount", "conflict_count": 1821428, "one_sided_null_count": 0}, {"column": "tolls_amount", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "improvement_surcharge", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "congestion_surcharge", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "total_amount", "conflict_count": 2775302, "one_sided_null_count": 0}, {"column": "fare_residual", "conflict_count": 2622167, "one_sided_null_count": 0}, {"column": "is_billable", "conflict_count": 2429, "one_sided_null_count": 0}]}
```

Summary:

- Row/key counts match exactly on both sides (3,021,172).
- No `missing_from_target`, `additional_in_target`, or `invalid_key_alignment`.
- 7,735 rows fully `matching`; 3,013,437 rows (~99.7%) `changed`.
- Conflict drivers: `total_amount` (2,775,302), `fare_amount` (2,628,323), `fare_residual`
  (2,622,167), `tip_amount` (1,821,428), `is_billable` (2,429).
- One-sided nulls only on `rate_plan_key` and `passenger_count` (143,577 each, same count
  — suggests one join-survival/null-handling mechanism affecting both together, not two
  independent ones).
- All zone/date/location/flag columns show zero conflicts.

## Investigation

_Pending._

## Residual / Unexplained

_Pending._

## Outcome

_Pending._
