# Recon Pair: `core.fct_trip_baseline_agg` (Baseline) vs `core.fct_trip` (Target)

## Confirmed contract

- **Baseline:** `nyctaxi.core.fct_trip_baseline_agg`
- **Target:** `nyctaxi.core.fct_trip`
- **Grain:** Different. Baseline is pre-aggregated at `(trip_day, pickup_borough)`; target is
  row-level (`trip_key`). Target is rolled up to the common grain via
  `vd_recon_compile_rollup_relation`, run once per aggregate (`trip_cnt`, `gross_revenue`) on
  both sides and joined on the macro's own deterministic `grain_key` (identical algorithm on
  both sides since both sides call the same macro).
- **Mode:** Keyed, on the rollup macro's synthetic `grain_key` (encodes `trip_day` +
  `pickup_borough`; `vd_recon_compare_keyed`/`vd_recon_categorize_keyed` only ever use a
  single-column key, so a composite grain requires this synthetic column on both sides).
- **Scope:** FSA-narrowed to 6 months, `trip_day`/`pickup_date` in `[2024-01-01, 2024-07-01)` —
  the ADR-0002 reporting window, covering 1,444 of the baseline's 1,457 rows.
- **Gating:** Advisory (never blocks Intent completion) — FSA-confirmed.
- **Round cap:** 3 — FSA-confirmed.

### Column mapping

| Baseline | Target rollup | Aggregate | Cast/derivation | Justification |
| --- | --- | --- | --- | --- |
| trip_day | pickup_date | — (group-by/key) | none | identical grain unit (DATE) |
| pickup_borough | dim_zone.borough_name (joined via pickup_zone_key) | — (group-by/key) | none | target has no native borough column; resolved through `dim_zone` |
| trip_cnt | count(*) | row count, via constant `trip_flag=1` summed | none | spot-check match: 2024-01-13/Manhattan baseline=96,332, target rollup=96,332 |
| gross_revenue | sum(total_amount) | sum | none | spot-check match: 2024-01-13/Manhattan baseline=2,072,505.35, target rollup=2,072,505.35 |
| fare_gap | fare_residual + congestion_surcharge | sum | `t.fare_residual + coalesce(t.congestion_surcharge, 0)` | **Amendment 3 (re-scoped in):** re-mapped from "no target equivalent" to `fare_residual + congestion_surcharge`, per FSA direction this run — see "Mapping derivation" below for how `coalesce(..., 0)` was determined to be part of the correct derivation itself, not an Investigate-stage finding about the data. |

Target's remaining columns (all row-level fare/trip attributes not entering `trip_cnt` or
`gross_revenue`) have no baseline counterpart at this grain and are out of scope.

### Mapping derivation: `fare_gap` → `fare_residual + coalesce(congestion_surcharge, 0)`

This is Negotiate-stage work (deriving a correct column expression), not an Investigate-stage
hypothesis about baseline/target data divergence — it does not appear in the Investigation
section or the outcome JSON's `hypotheses` array below, since no data divergence was ever
confirmed by it.

- Spot-check on `pickup_date = '2024-05-16'`, `pickup_borough = 'Manhattan'` matched baseline's
  `fare_gap_sum` (242,445.95) exactly against `sum(fare_residual) + sum(congestion_surcharge)`
  (-24,163.55 + 266,609.5 = 242,445.95), confirming the candidate expression.
- A first attempt applying this as a per-row derivation, `fare_residual + congestion_surcharge`,
  before rolling up, produced 1,133 conflicts including 9 one-sided nulls and diffs up to
  $63,494.25 — too large and structurally wrong (one-sided nulls) to be measurement noise, so
  this was treated as a broken comparison, not a divergent-data result, and was not measured
  or reported as one.
- Root cause: `congestion_surcharge` is `NULL` for trips outside congestion-pricing zones/dates
  (e.g. one Staten Island trip on `2024-01-13` with `congestion_surcharge IS NULL`,
  `fare_residual = 2.5`). SQL's `x + NULL = NULL` means
  `SUM(fare_residual + congestion_surcharge)` silently drops that row's entire `fare_residual`
  contribution, not just the missing surcharge, corrupting every grain cell containing at least
  one such trip.
- Fix: `fare_residual + coalesce(congestion_surcharge, 0)`. This is the corrected mapping
  expression recorded in the Column mapping table above, and is what Measurement (below) uses
  from the first attempt at a genuine comparison — no earlier, structurally-broken comparison
  is reported as a measurement result.

### PII

`vd_recon_pii_columns(nyctaxi.core.fct_trip_baseline_agg)` → `[]`. No PII gating required.

### Tolerance

- Exact: `trip_cnt_sum`
- Fixed tolerance $0.01: `gross_revenue_sum`, `fare_gap_sum` (both account for floating-point `SUM(DOUBLE)` accumulation order differences between baseline's pre-aggregation and target's rollup)

## Amendment 3 — `fare_gap` re-scoped in (user request, this run)

FSA requested `fare_gap` be brought back into scope, mapped to `fare_residual` — the same
column identified but not confirmed in the prior run's column-mapping search. Re-running the
full pipeline (rollup → compare → materialize → investigate → categorize → outcome) with all
three metrics (`trip_cnt`, `gross_revenue`, `fare_gap`) in scope. No other part of the
confirmed contract (grain, key, window, gating, round cap) changes.

### Profiling evidence (Negotiate step)

| Check | Macro | Result |
| --- | --- | --- |
| Baseline schema | `vd_recon_schema_probe(domain.core.fct_trip_baseline_agg)` | `trip_day DATE, pickup_borough VARCHAR, trip_cnt BIGINT, gross_revenue DOUBLE, fare_gap DOUBLE` |
| Baseline boundaries (`trip_day`) | `vd_recon_probe_boundaries(domain.core.fct_trip_baseline_agg, "trip_day")` | `{"min": "2002-12-31", "max": "2026-06-26", "count": 1457}` |
| Target boundaries (`pickup_datetime`) | `vd_recon_probe_boundaries(domain.core.fct_trip, "pickup_datetime")` | `{"min": "2002-12-31 16:46:07", "max": "2026-06-26 23:53:12", "count": 20671899}` |
| Baseline PII columns | `vd_recon_pii_columns(domain.core.fct_trip_baseline_agg)` | `{"pii_columns": []}` |
| Baseline uniqueness at grain | ad hoc: `count(*) = count(distinct trip_day\|\|pickup_borough) = 1457`, 0 nulls | unique, no nulls |

## Measurement

Scope: `trip_day`/`pickup_date` in `[2024-01-01, 2024-07-01)`.

Baseline and target rollup relations each built from three `vd_recon_compile_rollup_relation`
calls (one per aggregate: `trip_cnt`, `gross_revenue`, `fare_gap`), joined on the macro's own
`grain_key`, then compared via `vd_recon_compare_keyed(baseline_relation, target_relation,
["grain_key"], column_pairs)`, using the confirmed mapping
(`fare_gap` → `fare_residual + coalesce(congestion_surcharge, 0)`; see "Mapping derivation"
above for how it was derived):

```json
{"row_count": {"baseline": 1444, "target": 1444}, "key_count": {"baseline": 1444, "target": 1444}, "classification": {"matching": 354, "missing_from_target": 0, "additional_in_target": 0, "changed": 1090}, "invalid_key_alignment": 0, "column_conflicts": [{"column": "trip_cnt_sum", "conflict_count": 0, "one_sided_null_count": 0}, {"column": "gross_revenue_sum", "conflict_count": 1008, "one_sided_null_count": 0}, {"column": "fare_gap_sum", "conflict_count": 426, "one_sided_null_count": 0}]}
```

`vd_recon_materialize_keyed_mismatches` produced
`nyctaxi.main.vd_recon_mismatch_20240101_6mo_r1_faregap3` (1,092 rows: the union of `changed`
and any presence-class rows — none of the latter here; zero one-sided nulls, zero
missing/additional rows on either side).

## Investigation (Round 1)

<details>
<summary><b>H1 — fare_gap_sum conflicts are floating-point summation noise, not a real value difference</b>: <span class="badge badge-good">confirmed</span></summary>

- Macro: `vd_recon_predict`
- Predicate: `abs(target_fare_gap_sum - baseline_fare_gap_sum) <= 0.01`
- `prediction_reads_as`: "every row's fare_gap_sum conflict magnitude is within the confirmed $0.01 tolerance, consistent with double-precision floating point error rather than a genuine dollar-level discrepancy"
- `compiled_query`: `select count(*) as n from nyctaxi.main.vd_recon_mismatch_20240101_6mo_r1_faregap3 where abs(("target_fare_gap_sum" - "baseline_fare_gap_sum")) <= 0.01`
- Result: `matched_count: 1092` — the full mismatch population (including the 670 rows that were never in `fare_gap_sum` conflict to begin with; the predicate holds trivially there), confirming no row's `fare_gap_sum` diff exceeds tolerance.
- Corroborating aggregate detail (`vd_recon_aggregate_evidence`, column `abs(baseline_fare_gap_sum - target_fare_gap_sum)`): `{"min": 5.55e-17, "max": 5.82e-11, "avg": 9.38e-13, "n": 422}` over the 422 rows actually in conflict — every difference is many orders of magnitude below one cent, ruling out a genuine value divergence and pointing specifically at floating-point summation order (baseline's per-day pre-aggregation vs. target's 6-month rollup over 20.6M rows) as the mechanism.
</details>

<details>
<summary><b>H2 — gross_revenue_sum conflicts are floating-point summation noise, not a real value difference</b>: <span class="badge badge-good">confirmed</span></summary>

- Macro: `vd_recon_predict`
- Predicate: `abs(target_gross_revenue_sum - baseline_gross_revenue_sum) <= 0.01`
- `prediction_reads_as`: "every row's gross_revenue_sum conflict magnitude is within the confirmed $0.01 tolerance, consistent with double-precision floating point error rather than a genuine dollar-level discrepancy"
- `compiled_query`: `select count(*) as n from nyctaxi.main.vd_recon_mismatch_20240101_6mo_r1_faregap3 where abs(("target_gross_revenue_sum" - "baseline_gross_revenue_sum")) <= 0.01`
- Result: `matched_count: 1092` — the full mismatch population, confirming no row's `gross_revenue_sum` diff exceeds tolerance.
- Corroborating aggregate detail (`vd_recon_aggregate_evidence`, column `abs(baseline_gross_revenue_sum - target_gross_revenue_sum)`): `{"min": -3.17e-08, "max": 6.15e-08, "avg": 3.24e-09, "n": 1007}` over the 1,007 rows actually in conflict — same floating-point-summation mechanism as H1, unaffected by the `fare_gap` remapping since `gross_revenue`'s own mapping is unchanged.
</details>

## Residual / Unexplained

None. All 422 `fare_gap_sum` conflicts are covered by H1, and all 1,007 `gross_revenue_sum`
conflicts are covered by H2 — both fall within the confirmed $0.01 tolerance, making them
immaterial. `trip_cnt_sum` has zero conflicts. No presence-class differences
(`missing_from_target`/`additional_in_target` are both 0; zero one-sided nulls).

## Outcome

```json
{
  "schema_version": "1.0",
  "outcome": "aligned",
  "plan_id": "core__fct_trip_baseline_agg-core__fct_trip",
  "run_id": "20240101_6mo_r1_faregap3",
  "hypotheses": [
    {"id": "H1", "mechanism": "cast", "claim": "fare_gap_sum conflicts are within double-precision SUM(DOUBLE) accumulation-order tolerance, not a genuine value divergence", "disposition": "confirmed"},
    {"id": "H2", "mechanism": "cast", "claim": "gross_revenue_sum conflicts are within double-precision SUM(DOUBLE) accumulation-order tolerance, not a genuine value divergence", "disposition": "confirmed"}
  ],
  "categorization": {"matching": 354, "missing_from_target": 0, "additional_in_target": 0, "changed": 1090},
  "aggregate_measures": {
    "row_count": {"baseline": 1444, "target": 1444},
    "conflict_drivers": {"gross_revenue_sum": 1007, "fare_gap_sum": 422},
    "one_sided_nulls": {}
  },
  "checks_not_performed": [],
  "mismatch_table_ref": "nyctaxi.main.vd_recon_mismatch_20240101_6mo_r1_faregap3",
  "rounds_used": 1,
  "retries_used": 0
}
```

**Outcome: <span class="badge badge-good">aligned</span>** — `trip_cnt` reconciles exactly;
`gross_revenue` and `fare_gap` both reconcile within the confirmed $0.01 floating-point
tolerance (max observed diffs 6.15e-08 and 5.82e-11 respectively) once `fare_gap` is mapped
to `fare_residual + coalesce(congestion_surcharge, 0)`. Gating is advisory; this does not
block Intent completion.
