# Reconciliation: `core.fct_trip_baseline_agg` vs `core.fct_trip`

## Artifacts

- [`comparison-contract.json`](./comparison-contract.json)
- [`outcome.json`](./outcome.json)

**Outcome:** divergent-explained

## Comparison summary

- **Baseline:** `domain.core.fct_trip_baseline_agg` — a plain, non-dbt-modeled snapshot table, 1457 rows, grain `(trip_day, pickup_borough)`, columns `trip_cnt`, `gross_revenue`, `fare_gap`.
- **Target:** `domain.core.fct_trip` — the dbt-modeled trip fact, rolled up to the same `(trip_day, pickup_borough)` grain via `pickup_datetime`/`dim_zone.borough_name` for this comparison (grain mismatch mode, FSA-confirmed `mode_grain=opt-0`).
- **Configured scope:** whole-dataset overlap window, `2002-12-31` through `2026-06-26` (boundaries matched exactly between both sides at profiling time — no trimming needed).
- **Observed coverage:** this run measured every one of the 1457 baseline rows against the rolled-up target at the confirmed grain; no truncation occurred.
- **Gating:** advisory (FSA-confirmed, `gating=opt-0`).
- **Key:** synthetic `grain_key` built from `(trip_day, pickup_borough)`.

### Column mapping

| Baseline column | Target column | Tolerance | Notes |
| --- | --- | --- | --- |
| `trip_cnt` | `trip_cnt` (rolled up as `count(*)`) | exact | 0 conflicts measured |
| `gross_revenue` | `gross_revenue` (rolled up as `sum(total_amount)`) | fixed 0.02 | float rounding only |
| `fare_gap` | `fare_gap` (rolled up as `sum(total_amount - fare_amount - tip_amount - tolls_amount - extra - mta_tax - improvement_surcharge)`) | fixed 0.02 | ungrounded derived column on baseline; formula reverse-engineered and confirmed (see H_001) |

## Measured difference

`vd_recon_compare_keyed` (baseline rows: 1457, target rows: 1451):

- `matching`: 351
- `changed`: 1100 (`trip_cnt`: 0 conflicts; `gross_revenue`: 1018 conflicts; `fare_gap`: 432 conflicts — pre-tolerance SQL `IS DISTINCT FROM` counts, before the 0.02 fixed tolerance narrows these to 0 material conflicts)
- `missing_from_target`: 6
- `additional_in_target`: 0
- `invalid_key_alignment`: 0

The materialized mismatch table (`vd_recon_mismatch_recon_fct_trip_r1`) holds 1098 rows: 1092 changed + 6 missing_from_target.

## Hypotheses

### H_001

- **Mechanism:** `derived_expression`
- **Disposition:** confirmed
- **Claim predicate:** `abs(baseline_fare_gap - target_fare_gap) <= 0.02`
- **Prediction reads as:** Baseline's `fare_gap` equals `total_amount - fare_amount - tip_amount - tolls_amount - extra - mta_tax - improvement_surcharge` (i.e. `congestion_surcharge` and `airport_fee` are NOT netted out, unlike the Target's own modeled `fare_residual` measure) — for every conflicting row, within a 0.02 float-rounding tolerance.

##### Test 1

- **Macro:** `vd_recon_predict`
- **Predicate:** `abs(baseline_fare_gap - target_fare_gap) <= 0.02`, scoped against the identical claim predicate.
- **Result:** `matched_count=1092` (all 1092 fare_gap-conflicting rows), `scope_match=true`.
- **Provenance:** `invocation_id=1d46dab7-515a-4f1b-bb5b-4afb507d635d`, captured at `2026-08-24T01:25:47Z`.

### H_003

- **Mechanism:** `derived_expression`
- **Disposition:** confirmed
- **Claim predicate:** `abs(baseline_gross_revenue - target_gross_revenue) <= 0.02`
- **Prediction reads as:** Baseline's `gross_revenue` equals the sum of Target's `total_amount` at the `(trip_day, pickup_borough)` grain, within a 0.02 float-rounding tolerance.

##### Test 1

- **Macro:** `vd_recon_predict`
- **Predicate:** `abs(baseline_gross_revenue - target_gross_revenue) <= 0.02`, scoped against the identical claim predicate.
- **Result:** `matched_count=1092` (all 1092 gross_revenue-conflicting rows), `scope_match=true`.
- **Provenance:** `invocation_id=1ac8507f-8580-464e-9e4b-5f2f0663c673`, captured at `2026-08-24T01:26:51Z`.

### H_002

- **Mechanism:** `join`
- **Disposition:** confirmed
- **Claim predicate:** `baseline_trip_day < '2019-01-01'`
- **Prediction reads as:** Every key present only on the baseline side (`missing_from_target`) corresponds to a `trip_day` before `2019-01-01` — the earliest `valid_from_date` in `dim_zone` — so the Target's role-playing as-of join to `dim_zone` (`fct_trip.sql`'s `zp`/`zd` joins, `valid_from_date`/`valid_to_date` half-open interval) silently drops these trips rather than emitting a null-zone row.

##### Test 1 (positive prediction)

- **Macro:** `vd_recon_predict`
- **Predicate:** `baseline_trip_day < '2019-01-01'`, scoped against the identical claim.
- **Result:** `matched_count=6` (all 6 `missing_from_target` keys), `scope_match=true`.
- **Provenance:** `invocation_id=e770b615-066d-43c7-b8a3-1dd4cad78a6a`, captured at `2026-08-24T01:19:03Z`.

##### Test 2 (eliminative, direction 1)

- **Macro:** `vd_recon_predict`
- **Predicate:** `baseline_trip_day < '2019-01-01' AND target_present = true`
- **Result:** `matched_count=0` — no pre-2019 baseline row leaks into the Target.
- **Provenance:** `invocation_id=7f71c585-9f1d-45d5-8511-c92fde4c1178`, captured at `2026-08-24T01:20:18Z`.

##### Test 3 (eliminative, direction 2)

- **Macro:** `vd_recon_predict`
- **Predicate:** `target_present = false AND baseline_trip_day >= '2019-01-01'`
- **Result:** `matched_count=0` — no `missing_from_target` row has any other cause.
- **Provenance:** `invocation_id=2be86a68-de3d-4027-8fe1-902d4e0e2cd0`, captured at `2026-08-24T01:20:49Z`.

## Residual

None.

## Unexplained

None.

## Amendments

### A_001

- **What changed:** `fare_gap`'s target-side expression was grounded against the wider Target column inventory (no dbt-manifest expression exists for this baseline-only derived measure) after FSA confirmation via the `derived_column_fsa_confirmations` fallback path (`fare_gap_fallback=opt-0`).
- **Why:** the baseline table `core.fct_trip_baseline_agg` is a plain snapshot with no dbt lineage; `fare_gap`'s formula could not be traced from a manifest and had to be reverse-engineered from profiling (see H_001).
